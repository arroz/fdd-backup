//
//  DataBitsMenu.swift
//  FDD Backup
//
//  Created by Miguel Arroz on 01/03/2026.
//

import SwiftUI


struct DataBitsMenu: View {
    @Binding var dataBits: DataBits

    var body: some View {
        HStack {
            Picker(selection: $dataBits) {
                ForEach(DataBits.defaultValues) { value in
                    Text("\(value.dataBits)").tag(value)
                }
            } label: {
                Text("Data bits:")
            }

            Text("\(dataBits.letter)")
                .foregroundStyle(.secondary)
                .monospaced()
        }
    }
}

#Preview("DataBitsMenu") {
    @State @Previewable var selected = DataBits.defaultValues.last!
    DataBitsMenu(dataBits: $selected)
        .padding()
}
