//
//  ContentView.swift
//  FDD Backup
//
//  Created by Miguel Arroz on 16/02/2026.
//

import SwiftUI
import UniformTypeIdentifiers
import ORSSerial

struct ContentView: View {
    @State private var model = MainModel()
    
    @State private var showFileSelector = false
    
    struct X: Identifiable {
        let id = UUID()
    }
    
    var body: some View {
        WithErrorAlert { errorProxy in
            VStack(alignment: .leading, spacing: 0) {
                SerialPortControlView(model: model)
                    .padding()
                
                DataProgressView(model: model)
                    .padding()
                
                FileTable(model: $model)
                
                Divider()
                
                HStack {
                    Text("Rename (10 chars max) and save files to keep them permanently.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Save All…") {
                        showFileSelector = true
                    }
                    .disabled(model.files.isEmpty)
                }
                .padding()
            }
            .fileImporter(isPresented: $showFileSelector, allowedContentTypes: [.directory]) { result in
                switch result {
                case .success(let success):
                    do {
                        try model.saveFiles(to: success)
                    } catch let error {
                        errorProxy.showAlert(error: error)
                    }
                case .failure(let failure):
                    errorProxy.showAlert(error: failure)
                }
            }
            .fileDialogMessage("Choose a folder to save files to.")
        }
    }
}

#Preview {
    ContentView()
}

