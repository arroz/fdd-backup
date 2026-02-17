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
    
    var body: some View {
        VStack {
            HStack {
                Picker(selection: $selectedSerialPort) {
                    ForEach(model.availablePorts, id: \.self) { serialPort in
                        Text(serialPort.name).tag(serialPort)
                    }
                } label: {
                    Text("Serial Port:")
                }
             
                Button("Connect") {
                    selectedSerialPort.map { model.connect(serialPort: $0) }
                }
                .disabled(selectedSerialPort == nil || model.serialPort != nil)
            }
        }
    }
}

#Preview {
    SerialPortControlView(model: MainModel())
        .padding()
}
