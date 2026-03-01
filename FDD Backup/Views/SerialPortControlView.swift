//
//  SerialPortControlView.swift
//  FDD Backup
//
//  Created by Miguel Arroz on 16/02/2026.
//

import SwiftUI
import ORSSerial

struct SerialPortControlView: View {
    let model: MainModel
    
    @State private var selectedSerialPort: ORSSerialPort?
    
    @State private var connectionSpeed = SerialPortSpeed.defaultSpeeds.last!
    
    @State private var dataBits = DataBits.defaultValues.last!
    
    @State private var stopBits = StopBits.defaultValues.first!
    
    @State private var parity = ORSSerialPortParity.even
    
    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Form {
                    Picker(selection: $selectedSerialPort) {
                        ForEach(model.availablePorts, id: \.self) { serialPort in
                            Text(serialPort.name).tag(serialPort)
                        }
                    } label: {
                        Text("Device:")
                    }
                    
                    ConnectionSpeedMenu(speed: $connectionSpeed)
                    
                    ParityMenu(parity: $parity)
                    
                    StopBitsMenu(stopBits: $stopBits)
                    
                    DataBitsMenu(dataBits: $dataBits)
                }
            }
            .padding(.trailing, 8)
            .fixedSize(horizontal: true, vertical: true)
            
            if model.serialPort != nil {
                Button("Disconnect") {
                    model.disconnect()
                }
                .fixedSize(horizontal: true, vertical: false)
            } else {
                Button("Connect") {
                    if let port = selectedSerialPort {
                        model.connect(
                            serialPort: port,
                            baudRate: connectionSpeed,
                            parity: parity,
                            stopBits: stopBits,
                            dataBits: dataBits
                        )
                    }
                }
                .disabled(selectedSerialPort == nil)
                .fixedSize(horizontal: true, vertical: false)
            }
            
            Spacer()
            
            Divider()
                .padding(.horizontal, 20)
            
            VStack(alignment: .leading) {
                Text("FORMAT *\":CH_A\"\n").foregroundStyle(.secondary)
                HStack { Text("Text or Bytes (T/B): ").foregroundStyle(.secondary); Text("B") }
                HStack { Text("XON / XOFF) (Y/N): ").foregroundStyle(.secondary); Text("N") }
                HStack { Text("Input with wait (Y/N): ").foregroundStyle(.secondary); Text("Y") }
                HStack { Text("Baud Rate: ").foregroundStyle(.secondary); Text("\(connectionSpeed.letter)") }
                HStack { Text("Parity: ").foregroundStyle(.secondary); Text("\(parity.letter)") }
                HStack { Text("Stop Bits: ").foregroundStyle(.secondary); Text("\(stopBits.letter)") }
                HStack { Text("Bits/char: ").foregroundStyle(.secondary); Text("\(dataBits.letter)") }
            }
            .monospaced()
            .fixedSize(horizontal: true, vertical: true)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

#Preview {
    SerialPortControlView(model: MainModel())
        .padding()
}

