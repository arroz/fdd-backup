# FDD Backup — Python cross-platform port

Cross-platform Python reimplementation of [@arroz/fdd-backup](https://github.com/arroz/fdd-backup).

Receives files from a **Timex FDD** drive over a serial port and saves them as
**ZX Spectrum TAP** files (plus raw `.data` originals).

## Requirements

- Python 3.10+
- `pyserial`
- `tkinter` (for the GUI — included with most Python distributions)

```
pip install pyserial
```

## Usage

### GUI mode (default)
```
python fdd_backup.py
```

### CLI (interactive) mode
```
python fdd_backup.py --cli
```

### CLI with options pre-set
```
python fdd_backup.py --cli --baud 9600 --output ~/my_backups
```

| Flag | Default | Description |
|------|---------|-------------|
| `--cli` | off | Use terminal UI instead of GUI |
| `--baud N` | 9600 | Serial baud rate |
| `--parity X` | N | Parity: N/E/O/M/S |
| `--stop-bits N` | 1 | Stop bits: 1 or 2 |
| `--data-bits N` | 8 | Data bits: 5–8 |
| `--output DIR` | FDDBackup | Output directory (CLI mode) |

## Output

Files are saved under the chosen output directory:

```
FDDBackup/
  Tapes/       ← ZX Spectrum TAP files (.tap)
  Originals/   ← raw bytes as received from the FDD (.data)
```

## How it works

The Timex FDD sends files as a raw binary stream over a serial link.
Each file starts with a small header (6–8 bytes, little-endian):

| Type | Byte 0 | Byte 1 | Bytes 2–3 | Bytes 4–5 | Bytes 6–7 |
|------|--------|--------|-----------|-----------|-----------|
| Program | 0x00 | 0x00 | auto-start line | data length | program length |
| Numeric Array | 0x00 | 0x01 | full length | address | array length |
| Alphanumeric Array | 0x00 | 0x02 | full length | address | array length |
| Bytes | 0x00 | 0x03 | data length | start address | *(6-byte header, no 7th/8th byte)* |

The received data is then wrapped in a standard two-block TAP file:
- **Block 1** (19 bytes): TAP header with filename and metadata
- **Block 2**: the actual data with a flag byte and XOR checksum

## Platform notes

- **Windows**: use a COM port name like `COM3`
- **Linux**: use `/dev/ttyUSB0`, `/dev/ttyACM0`, etc.
- **macOS**: use `/dev/tty.usbserial-*` etc.

RTS/CTS and DTR/DSR hardware flow control are enabled by default (matching the original app).
