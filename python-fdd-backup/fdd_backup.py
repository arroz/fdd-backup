#!/usr/bin/env python3
"""
fdd_backup.py — Cross-platform Python reimplementation of the fdd-backup macOS app.

Receives files from a Timex FDD drive over a serial port and saves them as
ZX Spectrum TAP files (plus raw .data originals).

Usage:
    python fdd_backup.py              # Launch GUI (requires tkinter)
    python fdd_backup.py --cli        # Run in interactive CLI mode
    python fdd_backup.py --help       # Show options

Requires:  pip install pyserial
"""

import argparse
import struct
import sys
import threading
import os
from dataclasses import dataclass, field
from enum import IntEnum
from pathlib import Path
from typing import Optional, Callable

# ---------------------------------------------------------------------------
# Protocol / TAP logic (pure Python, no GUI dependency)
# ---------------------------------------------------------------------------

class FileType(IntEnum):
    PROGRAM           = 0
    NUMERIC_ARRAY     = 1
    ALPHANUMERIC_ARRAY = 2
    BYTES             = 3

    @property
    def header_size(self) -> int:
        return 6 if self == FileType.BYTES else 8

    @property
    def description(self) -> str:
        return {
            FileType.PROGRAM:            "Program",
            FileType.NUMERIC_ARRAY:      "Numeric Array",
            FileType.ALPHANUMERIC_ARRAY: "Alphanumeric Array",
            FileType.BYTES:              "Bytes",
        }[self]


def _u16le(data: bytes, offset: int = 0) -> int:
    return struct.unpack_from("<H", data, offset)[0]

def _pack_u16le(value: int) -> bytes:
    return struct.pack("<H", value)

def _xor_checksum(data: bytes) -> int:
    result = 0
    for b in data:
        result ^= b
    return result


@dataclass
class ProgramMetadata:
    file_type:      FileType = FileType.PROGRAM
    auto_start:     int = 0
    data_length:    int = 0
    program_length: int = 0

    @property
    def header_size(self) -> int:
        return self.file_type.header_size

    @property
    def expected_raw_size(self) -> int:
        return self.header_size + self.data_length

    def specific_header_bytes(self) -> bytes:
        return (
            _pack_u16le(self.data_length) +
            _pack_u16le(self.auto_start) +
            _pack_u16le(self.program_length)
        )


@dataclass
class ArrayMetadata:
    file_type:   FileType
    full_length: int = 0
    address:     int = 0
    data_length: int = 0

    @property
    def header_size(self) -> int:
        return self.file_type.header_size

    @property
    def expected_raw_size(self) -> int:
        return self.header_size + self.data_length

    def specific_header_bytes(self) -> bytes:
        var_letter = 129 if self.file_type == FileType.NUMERIC_ARRAY else 193
        return (
            _pack_u16le(self.data_length) +
            bytes([0x00, var_letter]) +
            _pack_u16le(32768)          # unused
        )


@dataclass
class BytesMetadata:
    file_type:     FileType = FileType.BYTES
    data_length:   int = 0
    start_address: int = 0

    @property
    def header_size(self) -> int:
        return self.file_type.header_size

    @property
    def expected_raw_size(self) -> int:
        return self.header_size + self.data_length

    def specific_header_bytes(self) -> bytes:
        return (
            _pack_u16le(self.data_length) +
            _pack_u16le(self.start_address) +
            _pack_u16le(32768)          # unused
        )

    @property
    def description(self) -> str:
        if self.start_address == 16384 and self.data_length == 6912:
            return "Bytes (screen)"
        if self.start_address == 16384:
            return "Bytes (screen-ish)"
        return "Bytes"


Metadata = ProgramMetadata | ArrayMetadata | BytesMetadata


def build_tap_data(metadata: Metadata, payload: bytes, name: str) -> bytes:
    """Build a complete two-block TAP binary from metadata + payload."""
    # --- TAP header block ---
    tap_name = name.encode("latin-1", errors="replace")[:10]
    tap_name = tap_name + b" " * (10 - len(tap_name))   # pad to 10 bytes

    specific = metadata.specific_header_bytes()

    # Payload inside block 1:  flag(1) + type(1) + name(10) + specific(6) = 18
    block1_payload = bytes([0x00, metadata.file_type]) + tap_name + specific
    block1_checksum = _xor_checksum(block1_payload)

    header_block = _pack_u16le(0x13) + block1_payload + bytes([block1_checksum])

    # --- TAP data block ---
    block2_payload = bytes([0xFF]) + payload
    block2_checksum = _xor_checksum(block2_payload)

    data_block = _pack_u16le(len(payload) + 2) + block2_payload + bytes([block2_checksum])

    return header_block + data_block


@dataclass
class CompleteFile:
    metadata: Metadata
    payload:  bytes      # just the data portion
    raw_data: bytes      # header + data as received from FDD

    def tap_data(self, name: str) -> bytes:
        return build_tap_data(self.metadata, self.payload, name)


# ---------------------------------------------------------------------------
# DataReceiver  — stateful byte-stream parser
# ---------------------------------------------------------------------------

class DataReceiver:
    """
    Incrementally parses the binary stream from the Timex FDD.

    The FDD sends files as a raw binary header followed by the file data.
    All multi-byte integers are little-endian.

    Call received(data) whenever bytes arrive from the serial port.
    Pass on_file, on_log, on_progress callbacks to react to events.
    """

    def __init__(
        self,
        on_file:     Callable[[CompleteFile], None],
        on_log:      Callable[[str], None]          = lambda s: None,
        on_progress: Callable[[int, int, str], None] = lambda cur, tot, desc: None,
    ):
        self._buf = bytearray()
        self._metadata: Optional[Metadata] = None
        self.on_file     = on_file
        self.on_log      = on_log
        self.on_progress = on_progress

    def received(self, data: bytes) -> None:
        self._buf.extend(data)
        self._process()

    def reset(self) -> None:
        self._buf.clear()
        self._metadata = None
        self.on_progress(0, 0, "Waiting for file header…")

    # --- internals ---

    def _process(self) -> None:
        while True:
            if self._metadata is None:
                if not self._parse_header():
                    break
            else:
                if not self._parse_content():
                    break

    def _parse_header(self) -> bool:
        """Try to parse the next file header. Returns True if we should keep looping."""
        buf = self._buf

        if not buf:
            return False

        # First byte must be 0x00
        if buf[0] != 0:
            self.on_log(f"Initial byte is not 0 (got 0x{buf[0]:02X}), skipping.")
            del buf[0]
            return True         # try again

        if len(buf) < 2:
            return False        # wait for more data

        ftype_byte = buf[1]
        try:
            ftype = FileType(ftype_byte)
        except ValueError:
            self.on_log(f"Invalid file type 0x{ftype_byte:02X}, skipping 2 bytes.")
            del buf[:2]
            return True

        if len(buf) < ftype.header_size:
            return False        # header not fully arrived yet

        if ftype == FileType.PROGRAM:
            self._metadata = ProgramMetadata(
                auto_start     = _u16le(bytes(buf), 2),
                data_length    = _u16le(bytes(buf), 4),
                program_length = _u16le(bytes(buf), 6),
            )
        elif ftype in (FileType.NUMERIC_ARRAY, FileType.ALPHANUMERIC_ARRAY):
            self._metadata = ArrayMetadata(
                file_type   = ftype,
                full_length = _u16le(bytes(buf), 2),
                address     = _u16le(bytes(buf), 4),
                data_length = _u16le(bytes(buf), 6),
            )
        else:  # BYTES
            self._metadata = BytesMetadata(
                data_length   = _u16le(bytes(buf), 2),
                start_address = _u16le(bytes(buf), 4),
            )

        desc = f"Receiving {self._metadata.file_type.description}"
        self.on_progress(0, self._metadata.data_length, desc)
        return True

    def _parse_content(self) -> bool:
        """Try to collect the full file body. Returns True if we should keep looping."""
        meta = self._metadata
        assert meta is not None

        received_data = max(0, len(self._buf) - meta.header_size)
        self.on_progress(received_data, meta.data_length,
                         f"Receiving {meta.file_type.description}")

        if len(self._buf) < meta.expected_raw_size:
            return False        # wait for more data

        raw      = bytes(self._buf[:meta.expected_raw_size])
        payload  = raw[meta.header_size:]
        complete = CompleteFile(metadata=meta, payload=payload, raw_data=raw)
        self.on_file(complete)

        del self._buf[:meta.expected_raw_size]
        self._metadata = None
        self.on_progress(0, 0, "Waiting for file header…")
        return True             # might be another file in the buffer


# ---------------------------------------------------------------------------
# File saving helpers
# ---------------------------------------------------------------------------

def save_files(files: list[tuple[str, CompleteFile]], base_dir: Path) -> dict[str, Exception]:
    """
    Save a list of (name, CompleteFile) pairs under base_dir/Tapes/ and base_dir/Originals/.
    Returns a dict of name -> error for any that failed.
    """
    tapes_dir     = base_dir / "Tapes"
    originals_dir = base_dir / "Originals"

    for d in (tapes_dir, originals_dir):
        d.mkdir(parents=True, exist_ok=True)

    errors: dict[str, Exception] = {}

    for name, cf in files:
        try:
            # Find a unique filename (appends -1, -2, … if needed)
            actual = _unique_name(name, tapes_dir, originals_dir)
            (originals_dir / f"{actual}.data").write_bytes(cf.raw_data)
            (tapes_dir     / f"{actual}.tap" ).write_bytes(cf.tap_data(name))
        except Exception as exc:
            errors[name] = exc

    return errors


def _unique_name(base: str, tapes_dir: Path, originals_dir: Path) -> str:
    for suffix in [""] + [f"-{i}" for i in range(1, 10_000)]:
        candidate = base + suffix
        if (
            not (tapes_dir     / f"{candidate}.tap" ).exists() and
            not (originals_dir / f"{candidate}.data").exists()
        ):
            return candidate
    return base  # shouldn't happen


# ---------------------------------------------------------------------------
# Serial port helpers
# ---------------------------------------------------------------------------

def list_ports() -> list[str]:
    try:
        from serial.tools import list_ports as lp
        return [p.device for p in lp.comports()]
    except ImportError:
        return []


BAUD_RATES = [50, 75, 110, 134, 150, 200, 300, 600, 1200, 1800,
              2400, 4800, 7200, 9600, 19200]

# Letter codes shown in the Spectrum FORMAT command, matching the original app's models
BAUD_LETTERS  = {50: "A", 75: "B", 110: "C", 134: "D", 150: "E", 200: "F",
                 300: "G", 600: "H", 1200: "I", 1800: "J", 2400: "K",
                 4800: "M", 7200: "N", 9600: "O", 19200: "P"}
STOP_LETTERS  = {1: "A", 2: "C"}
DATA_LETTERS  = {5: "A", 6: "B", 7: "C", 8: "D"}
# Parity letters used by ORSSerial / Spectrum: Even=E, Odd=O, None=N
PARITIES      = {"None": "N", "Even": "E", "Odd": "O", "Mark": "M", "Space": "S"}
STOP_BITS     = [1, 2]
DATA_BITS     = [5, 6, 7, 8]


def open_serial(port: str, baud: int, parity: str = "N",
                stop_bits: int = 1, data_bits: int = 8):
    import serial
    return serial.Serial(
        port=port, baudrate=baud, parity=parity,
        stopbits=stop_bits, bytesize=data_bits,
        rtscts=True, dsrdtr=True, timeout=0.1,
    )


# ---------------------------------------------------------------------------
# CLI mode
# ---------------------------------------------------------------------------

def run_cli(args: argparse.Namespace) -> None:
    import serial

    ports = list_ports()
    if not ports:
        print("No serial ports found. Is your device connected?")
        sys.exit(1)

    print("Available serial ports:")
    for i, p in enumerate(ports):
        print(f"  [{i}] {p}")

    try:
        idx = int(input("Select port number: "))
        port = ports[idx]
    except (ValueError, IndexError):
        print("Invalid selection.")
        sys.exit(1)

    print(f"\nBaud rates: {BAUD_RATES}")
    baud_str = input(f"Baud rate [{args.baud}]: ").strip() or str(args.baud)
    try:
        baud = int(baud_str)
    except ValueError:
        baud = args.baud

    output_dir = Path(input(f"Output directory [{args.output}]: ").strip() or args.output)
    output_dir.mkdir(parents=True, exist_ok=True)

    print(f"\nConnecting to {port} at {baud} baud …  (Ctrl-C to stop)")

    files: list[tuple[str, CompleteFile]] = []
    file_counter = [0]
    lock = threading.Lock()

    def on_file(cf: CompleteFile) -> None:
        with lock:
            file_counter[0] += 1
            name = f"File{file_counter[0]}"
        print(f"\n✓ Received: {cf.metadata.file_type.description}  ({len(cf.payload)} bytes)")
        files.append((name, cf))

    def on_log(msg: str) -> None:
        print(f"  [log] {msg}")

    def on_progress(cur: int, tot: int, desc: str) -> None:
        if tot > 0:
            pct = int(100 * cur / tot)
            print(f"\r  {desc}: {cur}/{tot} bytes ({pct}%)   ", end="", flush=True)
        else:
            print(f"\r  {desc}   ", end="", flush=True)

    receiver = DataReceiver(on_file=on_file, on_log=on_log, on_progress=on_progress)

    try:
        with open_serial(port, baud, args.parity, args.stop_bits, args.data_bits) as ser:
            while True:
                chunk = ser.read(256)
                if chunk:
                    receiver.received(chunk)
    except serial.SerialException as exc:
        print(f"\nSerial error: {exc}")
    except KeyboardInterrupt:
        print("\n\nStopping…")

    if files:
        print(f"\nSaving {len(files)} file(s) to {output_dir} …")
        errors = save_files(files, output_dir)
        for name, err in errors.items():
            print(f"  ✗ Could not save '{name}': {err}")
        saved = len(files) - len(errors)
        print(f"  {saved} file(s) saved.")
    else:
        print("No files received.")


# ---------------------------------------------------------------------------
# GUI mode  (tkinter — built-in to Python, no extra install needed)
# ---------------------------------------------------------------------------

def run_gui() -> None:
    import tkinter as tk
    from tkinter import ttk, filedialog, messagebox

    root = tk.Tk()
    root.title("FDD Backup")
    root.resizable(True, True)

    # ---- State ----
    serial_thread: list[Optional[threading.Thread]] = [None]
    stop_event = threading.Event()
    ser_conn:    list[object] = [None]
    files: list[tuple[str, CompleteFile]] = []
    file_counter = [0]
    lock = threading.Lock()

    # ---- Variables ----
    port_var     = tk.StringVar()
    baud_var     = tk.StringVar(value="9600")
    parity_var   = tk.StringVar(value="None")
    stop_var     = tk.StringVar(value="1")
    data_var     = tk.StringVar(value="8")
    outdir_var   = tk.StringVar(value=str(Path.home() / "FDDBackup"))
    status_var   = tk.StringVar(value="Waiting for file header…")
    progress_var = tk.DoubleVar(value=0)

    # ---- Helpers that are safe to call from threads ----
    def _ui(fn):
        root.after(0, fn)

    def on_file(cf: CompleteFile) -> None:
        with lock:
            file_counter[0] += 1
            idx = file_counter[0]
        name = f"File {idx}" if idx > 1 else "File"
        name = name[:10]
        files.append((name, cf))
        size = len(cf.payload)
        ftype = cf.metadata.file_type.description
        _ui(lambda: file_list.insert("", "end", values=(name, ftype, size)))

    def on_log(msg: str) -> None:
        _ui(lambda: (
            log_text.configure(state="normal"),
            log_text.insert("end", msg + "\n"),
            log_text.see("end"),
            log_text.configure(state="disabled"),
        ))

    def on_progress(cur: int, tot: int, desc: str) -> None:
        def _update():
            status_var.set(desc)
            if tot > 0:
                progress_var.set(100.0 * cur / tot)
            else:
                progress_var.set(0)
        _ui(_update)

    # ---- Layout ----
    pad = dict(padx=6, pady=4)

    # Top: connection settings
    conn_frame = ttk.LabelFrame(root, text="Serial Port Settings")
    conn_frame.grid(row=0, column=0, columnspan=2, sticky="ew", **pad)
    # col 0=label, 1=chooser, 2=letter badge, 3=spacer, [4..]=FORMAT panel
    conn_frame.columnconfigure(3, weight=1)

    def refresh_ports():
        ports = list_ports()
        port_menu["values"] = ports
        if ports and not port_var.get():
            port_var.set(ports[0])

    # Port row (spans chooser + letter columns so the combobox is wider)
    ttk.Label(conn_frame, text="Port:").grid(row=0, column=0, sticky="w", **pad)
    port_menu = ttk.Combobox(conn_frame, textvariable=port_var, width=22)
    port_menu.grid(row=0, column=1, columnspan=2, sticky="ew", **pad)

    # Helper: letter badge label next to each chooser
    baud_letter_var   = tk.StringVar(value="O")
    parity_letter_var = tk.StringVar(value="N")
    stop_letter_var   = tk.StringVar(value="A")
    data_letter_var   = tk.StringVar(value="D")

    ttk.Label(conn_frame, text="Baud rate:").grid(row=1, column=0, sticky="w", **pad)
    ttk.Combobox(conn_frame, textvariable=baud_var,
                 values=[str(b) for b in BAUD_RATES], width=8).grid(row=1, column=1, sticky="w", **pad)
    ttk.Label(conn_frame, textvariable=baud_letter_var,
              font=("Courier", 10, "bold")).grid(row=1, column=2, sticky="w", padx=(0, 8))

    ttk.Label(conn_frame, text="Parity:").grid(row=2, column=0, sticky="w", **pad)
    ttk.Combobox(conn_frame, textvariable=parity_var,
                 values=list(PARITIES.keys()), width=8, state="readonly").grid(row=2, column=1, sticky="w", **pad)
    ttk.Label(conn_frame, textvariable=parity_letter_var,
              font=("Courier", 10, "bold")).grid(row=2, column=2, sticky="w", padx=(0, 8))

    ttk.Label(conn_frame, text="Stop bits:").grid(row=3, column=0, sticky="w", **pad)
    ttk.Combobox(conn_frame, textvariable=stop_var,
                 values=[str(s) for s in STOP_BITS], width=4, state="readonly").grid(row=3, column=1, sticky="w", **pad)
    ttk.Label(conn_frame, textvariable=stop_letter_var,
              font=("Courier", 10, "bold")).grid(row=3, column=2, sticky="w", padx=(0, 8))

    ttk.Label(conn_frame, text="Data bits:").grid(row=4, column=0, sticky="w", **pad)
    ttk.Combobox(conn_frame, textvariable=data_var,
                 values=[str(d) for d in DATA_BITS], width=4, state="readonly").grid(row=4, column=1, sticky="w", **pad)
    ttk.Label(conn_frame, textvariable=data_letter_var,
              font=("Courier", 10, "bold")).grid(row=4, column=2, sticky="w", padx=(0, 8))

    # Connect/Disconnect toggle button at the bottom of the settings column
    conn_btn_var = tk.StringVar(value="Connect")
    connect_btn  = ttk.Button(conn_frame, textvariable=conn_btn_var, width=14)
    connect_btn.grid(row=5, column=0, columnspan=3, sticky="w", padx=6, pady=(2, 6))
    ttk.Button(conn_frame, text="↺", width=3, command=refresh_ports).grid(row=5, column=0, columnspan=3, sticky="e", padx=6, pady=(2, 6))

    # Vertical separator between settings and Spectrum command panel
    ttk.Separator(conn_frame, orient="vertical").grid(row=0, column=3, rowspan=6, sticky="ns", padx=12, pady=4)

    # Spectrum FORMAT command panel (live-updating)
    fmt_frame = ttk.LabelFrame(conn_frame, text="Spectrum BASIC command")
    fmt_frame.grid(row=0, column=4, rowspan=6, sticky="nsw", padx=(0, 4), pady=4)

    fmt_text = tk.Text(fmt_frame, width=30, height=8, state="disabled",
                       font=("Courier", 10), relief="flat",
                       background=root.cget("background"))
    fmt_text.grid(row=0, column=0, padx=6, pady=4)

    fmt_text.tag_configure("cmd", foreground="#0000cc")
    fmt_text.tag_configure("dim", foreground="#888888")
    fmt_text.tag_configure("val", foreground="#000000")

    def _update_format_panel(*_):
        try:
            baud_letter = BAUD_LETTERS.get(int(baud_var.get()), "?")
        except ValueError:
            baud_letter = "?"
        try:
            stop_letter = STOP_LETTERS.get(int(stop_var.get()), "?")
        except ValueError:
            stop_letter = "?"
        try:
            data_letter = DATA_LETTERS.get(int(data_var.get()), "?")
        except ValueError:
            data_letter = "?"
        parity_letter = PARITIES.get(parity_var.get(), "N")

        # Update inline badge labels next to each chooser
        baud_letter_var.set(baud_letter)
        parity_letter_var.set(parity_letter)
        stop_letter_var.set(stop_letter)
        data_letter_var.set(data_letter)

        fmt_text.configure(state="normal")
        fmt_text.delete("1.0", "end")
        fmt_text.insert("end", 'FORMAT *":CH_A"\n', "cmd")
        fmt_text.insert("end", "Text or Bytes (T/B): ", "dim")
        fmt_text.insert("end", "B\n",                  "val")
        fmt_text.insert("end", "XON / XOFF (Y/N): ",  "dim")
        fmt_text.insert("end", "N\n",                  "val")
        fmt_text.insert("end", "Input with wait (Y/N): ", "dim")
        fmt_text.insert("end", "Y\n",                  "val")
        fmt_text.insert("end", "Baud Rate: ",          "dim")
        fmt_text.insert("end", f"{baud_letter}\n",     "val")
        fmt_text.insert("end", "Parity: ",             "dim")
        fmt_text.insert("end", f"{parity_letter}\n",   "val")
        fmt_text.insert("end", "Stop Bits: ",          "dim")
        fmt_text.insert("end", f"{stop_letter}\n",     "val")
        fmt_text.insert("end", "Bits/char: ",          "dim")
        fmt_text.insert("end", f"{data_letter}",       "val")
        fmt_text.configure(state="disabled")

    for var in (baud_var, parity_var, stop_var, data_var):
        var.trace_add("write", _update_format_panel)

    _update_format_panel()  # initial render

    # Collect the settings widgets that should be disabled while connected
    _settings_widgets = [port_menu] + [
        w for w in conn_frame.winfo_children()
        if isinstance(w, ttk.Combobox)
    ]

    # Output dir
    dir_frame = ttk.LabelFrame(root, text="Output Directory")
    dir_frame.grid(row=1, column=0, columnspan=2, sticky="ew", **pad)
    dir_frame.columnconfigure(0, weight=1)

    ttk.Entry(dir_frame, textvariable=outdir_var).grid(row=0, column=0, sticky="ew", padx=6, pady=4)

    def browse_dir():
        d = filedialog.askdirectory(title="Choose output directory")
        if d:
            outdir_var.set(d)

    ttk.Button(dir_frame, text="Browse…", command=browse_dir).grid(row=0, column=1, padx=4, pady=4)

    # Buttons row (connect/disconnect lives inside the serial settings panel)
    btn_frame = ttk.Frame(root)
    btn_frame.grid(row=2, column=0, columnspan=2, sticky="ew", **pad)

    reset_btn = ttk.Button(btn_frame, text="Reset receiver")
    save_btn  = ttk.Button(btn_frame, text="Save all files…")
    clear_btn = ttk.Button(btn_frame, text="Clear list")

    for i, b in enumerate([reset_btn, save_btn, clear_btn]):
        b.grid(row=0, column=i, padx=4)

    # File list
    list_frame = ttk.LabelFrame(root, text="Received Files")
    list_frame.grid(row=3, column=0, columnspan=2, sticky="nsew", **pad)
    list_frame.columnconfigure(0, weight=1)
    list_frame.rowconfigure(0, weight=1)
    root.rowconfigure(3, weight=1)
    root.columnconfigure(0, weight=1)

    cols = ("Name", "Type", "Size (bytes)")
    file_list = ttk.Treeview(list_frame, columns=cols, show="headings", height=8)
    for c in cols:
        file_list.heading(c, text=c)
        file_list.column(c, width=140)
    file_list.grid(row=0, column=0, sticky="nsew")
    ttk.Scrollbar(list_frame, orient="vertical", command=file_list.yview).grid(row=0, column=1, sticky="ns")
    file_list.configure(yscrollcommand=lambda *a: None)

    # Progress + status
    prog_frame = ttk.Frame(root)
    prog_frame.grid(row=4, column=0, columnspan=2, sticky="ew", **pad)
    prog_frame.columnconfigure(0, weight=1)

    ttk.Label(prog_frame, textvariable=status_var).grid(row=0, column=0, sticky="w")
    ttk.Progressbar(prog_frame, variable=progress_var, maximum=100, length=300).grid(row=1, column=0, sticky="ew", **pad)

    # Log
    log_frame = ttk.LabelFrame(root, text="Log")
    log_frame.grid(row=5, column=0, columnspan=2, sticky="ew", **pad)
    log_frame.columnconfigure(0, weight=1)

    log_text = tk.Text(log_frame, height=4, state="disabled", wrap="word")
    log_text.grid(row=0, column=0, sticky="ew", padx=4, pady=4)
    ttk.Scrollbar(log_frame, orient="vertical", command=log_text.yview).grid(row=0, column=1, sticky="ns")

    # ---- Serial reading thread ----
    receiver: list[Optional[DataReceiver]] = [None]

    def _serial_loop(port, baud, parity, stop, data_b):
        import serial
        try:
            with open_serial(port, baud, parity, stop, data_b) as ser:
                ser_conn[0] = ser
                while not stop_event.is_set():
                    chunk = ser.read(256)
                    if chunk:
                        receiver[0].received(chunk)
        except Exception as exc:
            _ui(lambda e=exc: (
                messagebox.showerror("Serial error", str(e)),
                do_disconnect(),
            ))
        finally:
            ser_conn[0] = None

    def do_connect():
        port = port_var.get()
        if not port:
            messagebox.showwarning("No port", "Please select a serial port.")
            return
        try:
            baud  = int(baud_var.get())
            stop  = int(stop_var.get())
            dbits = int(data_var.get())
        except ValueError:
            messagebox.showwarning("Invalid value", "Check baud/stop/data settings.")
            return

        parity = PARITIES.get(parity_var.get(), "N")

        receiver[0] = DataReceiver(on_file=on_file, on_log=on_log, on_progress=on_progress)
        stop_event.clear()

        t = threading.Thread(target=_serial_loop, args=(port, baud, parity, stop, dbits), daemon=True)
        serial_thread[0] = t
        t.start()

        conn_btn_var.set("Disconnect")
        connect_btn.configure(command=do_disconnect)
        for w in _settings_widgets:
            w.configure(state="disabled")
        status_var.set(f"Connected to {port}")

    def do_disconnect():
        stop_event.set()
        if ser_conn[0]:
            try:
                ser_conn[0].close()
            except Exception:
                pass
        conn_btn_var.set("Connect")
        connect_btn.configure(command=do_connect)
        for w in _settings_widgets:
            w.configure(state="normal")
        status_var.set("Disconnected.")

    def do_reset():
        if receiver[0]:
            receiver[0].reset()

    def do_save():
        if not files:
            messagebox.showinfo("Nothing to save", "No files received yet.")
            return

        out = Path(outdir_var.get())
        out.mkdir(parents=True, exist_ok=True)
        errors = save_files(files, out)

        if errors:
            msg = "\n".join(f"{n}: {e}" for n, e in errors.items())
            messagebox.showwarning("Some files failed", msg)
        else:
            messagebox.showinfo("Saved", f"{len(files)} file(s) saved to\n{out}")

        # Remove successfully saved items from the list
        saved_names = {n for n, _ in files if n not in errors}
        files[:] = [(n, cf) for n, cf in files if n in errors]
        for iid in file_list.get_children():
            if file_list.item(iid)["values"][0] in saved_names:
                file_list.delete(iid)

    def do_clear():
        files.clear()
        for iid in file_list.get_children():
            file_list.delete(iid)

    connect_btn.configure(command=do_connect)
    reset_btn.configure(command=do_reset)
    save_btn.configure(command=do_save)
    clear_btn.configure(command=do_clear)

    root.protocol("WM_DELETE_WINDOW", lambda: (do_disconnect(), root.destroy()))

    refresh_ports()
    root.mainloop()


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def main() -> None:
    parser = argparse.ArgumentParser(
        description="FDD Backup — receive files from a Timex FDD and save as ZX Spectrum TAP."
    )
    parser.add_argument("--cli",        action="store_true", help="Run in CLI mode instead of GUI")
    parser.add_argument("--baud",       type=int,  default=9600,  help="Baud rate (default: 9600)")
    parser.add_argument("--parity",     default="N", choices=list(PARITIES.values()), help="Parity (default: N)")
    parser.add_argument("--stop-bits",  type=int,  default=1,     help="Stop bits (default: 1)")
    parser.add_argument("--data-bits",  type=int,  default=8,     help="Data bits (default: 8)")
    parser.add_argument("--output",     default="FDDBackup",      help="Output directory (CLI mode)")
    args = parser.parse_args()

    try:
        import serial  # noqa: F401
    except ImportError:
        print("ERROR: pyserial is not installed. Run:  pip install pyserial")
        sys.exit(1)

    if args.cli:
        run_cli(args)
    else:
        try:
            run_gui()
        except Exception as exc:
            print(f"GUI failed ({exc}), falling back to CLI mode.")
            run_cli(args)


if __name__ == "__main__":
    main()
