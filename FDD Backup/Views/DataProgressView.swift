//
//  DataProgressView.swift
//  FDD Backup
//
//  Created by Miguel Arroz on 17/02/2026.
//

import SwiftUI

struct DataProgressView: View {
    let model: MainModel
    
    @State fileprivate var progress: DataReceiver.Progress = .indeterminate
    
    var body: some View {
        VStack(alignment: .leading) {
            if model.serialPort != nil {
                if case let .value(current, of: total) = progress.progressValue {
                    ProgressView(value: Double(current), total: Double(total))
                } else {
                    ProgressView()
                }
                
                HStack {
                    Text(progress.description)
                    if case let .value(current, of: total) = progress.progressValue {
                        Spacer()
                        Text("\(current)/\(total) bytes")
                            .monospacedDigit()
                    }
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
            } else {
                Text("Serial Port not connected.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity)
        .progressViewStyle(.linear)
        .onReceive(model.dataReceiver.progressPublisher) { progress in
            self.progress = progress
        }
    }
}

#Preview {
    DataProgressView(model: MainModel())
}
