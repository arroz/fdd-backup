//
//  WithErrorAlert.swift
//  PaperVault
//
//  Created by Miguel Arroz on 28/02/2025.
//

import SwiftUI

@Observable
class ErrorProxy {
    fileprivate struct ErrorDisplayData {
        let title: String
        let detail: String?
    }
    
    fileprivate var errorDisplayData: ErrorDisplayData?
    
    fileprivate var showErrorAlert: Bool = false
    
    func showAlert(error: Error) {
        if let localizedError = error as? LocalizedError {
            let title = localizedError.errorDescription ?? localizedError.localizedDescription
            let detail = localizedError.recoverySuggestion
            let displayData = ErrorDisplayData(title: title, detail: detail)
            self.errorDisplayData = displayData
            self.showErrorAlert = true
        } else {
            let displayData = ErrorDisplayData(title: error.localizedDescription, detail: nil)
            self.errorDisplayData = displayData
            self.showErrorAlert = true
        }
    }
    
    func showAlert(title: String, detail: String?) {
        self.errorDisplayData = .init(title: title, detail: detail)
        self.showErrorAlert = true
    }
}

struct WithErrorAlert<Content: View, AlertContent: View>: View {
    
    @ViewBuilder
    let content: (ErrorProxy) -> Content
    
    @ViewBuilder
    let errorAlertContent: () -> AlertContent
    
    @State private var errorProxy = ErrorProxy()
    
    init(@ViewBuilder _ content: @escaping (ErrorProxy) -> Content,
    @ViewBuilder errorAlertContent: @escaping () -> AlertContent = { EmptyView() }) {
        self.content = content
        self.errorAlertContent = errorAlertContent
    }
    
    var body: some View {
        content(errorProxy)
            .alert(
                errorProxy.errorDisplayData.map { $0.title } ?? "An error occurred.",
                isPresented: $errorProxy.showErrorAlert,
                presenting: errorProxy.errorDisplayData) { errorDisplayData in
                    errorAlertContent()
                } message: { errorDisplayData in
                    if let detail = errorDisplayData.detail {
                        Text(detail)
                    }
                }
    }
}

#Preview {
    WithErrorAlert() { proxy in
        Group {
            Button("Push me!") {
                proxy.showAlert(title: "An error occurred.", detail: "Who knows!")
            }
            
            Text("Hello!")
        }
    } errorAlertContent: {
        EmptyView()
    }
}
