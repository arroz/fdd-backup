//
//  FileTable.swift
//  FDD Backup
//
//  Created by Miguel Arroz on 17/02/2026.
//

import SwiftUI

struct FileTable: View {
    @Binding var model: MainModel
    
    var body: some View {
        Table(of: Binding<MainModel.File>.self) {
            TableColumn("Name") { file in
                TextField(text: file.name, label: {})
                    .labelsHidden()
            }
            
            TableColumn("Type") { file in
                Text(file.wrappedValue.receivedFile.metadata.fileType.localizedDescription)
            }
            
            TableColumn("Size") { file in
                Text("\(file.wrappedValue.receivedFile.metadata.dataLength) bytes")
                    .monospacedDigit()
            }
        } rows: {
            ForEach($model.files) { file in
                TableRow(file)
            }
        }
    }
}


