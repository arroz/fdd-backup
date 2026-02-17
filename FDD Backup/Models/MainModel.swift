//
//  MainModel.swift
//  FDD Backup
//
//  Created by Miguel Arroz on 16/02/2026.
//

import Foundation
import ORSSerial
import Combine

@Observable
class MainModel: NSObject, ORSSerialPortDelegate {
    
    class File: Identifiable, Hashable {
        static func == (lhs: MainModel.File, rhs: MainModel.File) -> Bool {
            lhs.id == rhs.id
        }
        
        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
        }
        
        let id = UUID()
        
        init(name: String, receivedFile: DataReceiver.CompleteFile) {
            self.name = name
            self.receivedFile = receivedFile
        }
        
        var name: String
        let receivedFile: DataReceiver.CompleteFile
    }
    
    private(set) var serialPort: ORSSerialPort?
    
    let dataReceiver = DataReceiver()
    
    private(set) var availablePorts: [ORSSerialPort] = []
    
    private var observation: NSObjectProtocol?
    
    private(set) var logs: [String] = []
    
    var files: [File] = []
    
    private var subscriptions: [AnyCancellable] = []
    
    override init() {
        super.init()
        observation = ORSSerialPortManager.shared().observe(\.availablePorts, options: [.initial, .new]) { [weak self] manager, values in
            values.newValue.map { self?.availablePorts = $0 }
        }
        
        dataReceiver.logPublisher.sink { [weak self] in self?.logs.append($0) }.store(in: &subscriptions)
        dataReceiver.completeFilePublisher.sink { [weak self] in
            guard let self else { return }
            
            self.files.append(File(name: self.makeNewFileName(), receivedFile: $0))
        }.store(in: &subscriptions)
    }
    
    private func makeNewFileName() -> String {
        var number = 1
        
        repeat {
            let fileName = number == 1 ? String(localized: "File") : String(localized: "File \(number)")
            if files.contains(where: { $0.name == fileName }) == false {
                return String(fileName.prefix(10))
            }
            number += 1
        } while true
    }
    
    func connect(serialPort: ORSSerialPort) {
        self.serialPort = serialPort
        serialPort.delegate = self
        serialPort.baudRate = 19200
        serialPort.usesRTSCTSFlowControl = true
        serialPort.usesDTRDSRFlowControl = true
        serialPort.usesDCDOutputFlowControl = false
        serialPort.numberOfDataBits = 8
        serialPort.numberOfStopBits = 1
        serialPort.parity = .even
        serialPort.open()
        
    }
    
    func serialPortWasRemovedFromSystem(_ serialPort: ORSSerialPort) {
        if self.serialPort == serialPort {
            serialPort.close()
            self.serialPort = nil
            self.dataReceiver.reset()
        }
    }
    
    func serialPort(_ serialPort: ORSSerialPort, didEncounterError error: any Error) {
        print(error)
        serialPort.close()
        self.serialPort = nil
        self.dataReceiver.reset()
    }
    
    func serialPort(_ serialPort: ORSSerialPort, didReceive data: Data) {
        dataReceiver.received(data: data)
    }
    
    func resetDataReceiver() {
        self.dataReceiver.reset()
    }
    
    enum FileSaveError: LocalizedError {
        case tapesFileIsNotDirectory
        case originalsFileIsNotDirectory
        case repeatedNames
    }
    
    func saveFiles(to baseUrl: URL) throws {
        let fileNames = Set(files.map { $0.name })
        if fileNames.count != files.count {
            throw FileSaveError.repeatedNames
        }
        
        let fileManager = FileManager.default
        
        func createDirIfNeeded(at dirUrl: URL, notDirectoryError: FileSaveError) throws {
            var isDirectory: ObjCBool = true
            let dirExists = fileManager.fileExists(atPath: dirUrl.path(), isDirectory: &isDirectory)
            if dirExists {
                if isDirectory.boolValue == false {
                    throw notDirectoryError
                }
            } else {
                try fileManager.createDirectory(at: dirUrl, withIntermediateDirectories: false)
            }
        }
        
        let tapesURL = baseUrl.appendingPathComponent("Tapes")
        let originalsURL = baseUrl.appendingPathComponent("Originals")
        
        try createDirIfNeeded(at: tapesURL, notDirectoryError: .tapesFileIsNotDirectory)
        try createDirIfNeeded(at: originalsURL, notDirectoryError: .originalsFileIsNotDirectory)
        
        try files.forEach { file in
            try file.receivedFile.rawData.write(to: originalsURL.appendingPathComponent("\(file.name).data"))
            try file.receivedFile.tapData(named: file.name).write(to: tapesURL.appendingPathComponent("\(file.name).tap"))
        }
    }
    
}
