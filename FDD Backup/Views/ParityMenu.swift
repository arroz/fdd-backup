//
//  ParityMenu.swift
//  FDD Backup
//
//  Created by Miguel Arroz on 01/03/2026.
//

import SwiftUI
import ORSSerial

struct ParityMenu: View {
    
    @Binding var parity: ORSSerialPortParity
    
    var body: some View {
        HStack {
            Picker(selection: $parity) {
                ForEach([ORSSerialPortParity.even, .odd, .none], id: \.self) { parity in
                    Text("\(parity.localizedDescription)").tag(parity)
                }
            } label: {
                Text("Parity:")
            }
         
            Text("\(parity.letter)")
                .foregroundStyle(.secondary)
                .monospaced()
        }
    }
}

extension ORSSerialPortParity {
    
    var localizedDescription: String {
        switch self {
        case .even: String(localized: "Even")
        case .odd: String(localized: "Odd")
        case .none: String(localized: "None")
        @unknown default: String(localized: "Unknown")
        }
    }
    
    var letter: String {
        switch self {
        case .even: "E"
        case .odd: "O"
        case .none: "N"
        @unknown default: String(localized: "")
        }
    }
    
}

#Preview {
    @State @Previewable var parity: ORSSerialPortParity = .even
    
    ParityMenu(parity: $parity)
        .padding()
}
