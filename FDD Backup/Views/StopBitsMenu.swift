//
//  StopBitsMenu.swift
//  FDD Backup
//
//  Created by Miguel Arroz on 01/03/2026.
//

import SwiftUI


struct StopBitsMenu: View {
    @Binding var stopBits: StopBits

    var body: some View {
        HStack {
            Picker(selection: $stopBits) {
                ForEach(StopBits.defaultValues) { value in
                    Text("\(value.stopBits)").tag(value)
                }
            } label: {
                Text("Stop bits:")
            }

            Text("\(stopBits.letter)")
                .foregroundStyle(.secondary)
                .monospaced()
        }
    }
}

#Preview("StopBitsMenu") {
    @State @Previewable var selected = StopBits.defaultValues.first!
    StopBitsMenu(stopBits: $selected)
        .padding()
}
