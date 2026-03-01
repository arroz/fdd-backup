//
//  ConnectionSpeedMenu.swift
//  FDD Backup
//
//  Created by Miguel Arroz on 01/03/2026.
//

import SwiftUI

struct ConnectionSpeedMenu: View {
    
    @Binding var speed: SerialPortSpeed
    
    var body: some View {
        HStack {
            Picker(selection: $speed) {
                ForEach(SerialPortSpeed.defaultSpeeds) { speed in
                    Text("\(speed.bps)").tag(speed)
                }
            } label: {
                Text("Baud rate:")
            }
         
            Text("\(speed.letter)")
                .foregroundStyle(.secondary)
                .monospaced()
        }
    }
}

#Preview {
    @State @Previewable var serialPortSpeed = SerialPortSpeed.defaultSpeeds.last!
    
    ConnectionSpeedMenu(speed: $serialPortSpeed)
        .padding()
}


