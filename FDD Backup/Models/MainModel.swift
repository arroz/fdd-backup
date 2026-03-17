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
    
    func connect(serialPort: ORSSerialPort, baudRate: SerialPortSpeed, parity: ORSSerialPortParity, stopBits: StopBits, dataBits: DataBits) {
        self.serialPort = serialPort
        serialPort.delegate = self
        serialPort.baudRate = baudRate.bps as NSNumber
        serialPort.usesRTSCTSFlowControl = true
        serialPort.usesDTRDSRFlowControl = true
        serialPort.usesDCDOutputFlowControl = false
        serialPort.numberOfDataBits = UInt(dataBits.dataBits)
        serialPort.numberOfStopBits = UInt(stopBits.stopBits)
        serialPort.parity = parity
        serialPort.open()
    }
    
    func disconnect() {
        self.serialPort?.close()
        self.serialPort = nil
        self.dataReceiver.reset()
    }
    
    func serialPortWasRemovedFromSystem(_ serialPort: ORSSerialPort) {
        if self.serialPort == serialPort {
            disconnect()
        }
    }
    
    func serialPort(_ serialPort: ORSSerialPort, didEncounterError error: any Error) {
        print(error)
        disconnect()
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
    
    struct FileSaveResult {
        let filesWithErrors: [File: Error]
    }
    
    func saveFiles(to baseUrl: URL) throws -> FileSaveResult {
        let fileNames = Set(files.map { $0.name })
        if fileNames.count != files.count {
            throw FileSaveError.repeatedNames
        }
        
        let fileManager = FileManager.default
        
        func createDirIfNeeded(at dirUrl: URL, notDirectoryError: FileSaveError) throws {
            var isDirectory: ObjCBool = true
            let dirExists = fileManager.fileExists(atPath: dirUrl.path(percentEncoded: false), isDirectory: &isDirectory)
            if dirExists {
                if isDirectory.boolValue == false {
                    throw notDirectoryError
                } else {
                    return
                }
            } else {
                try fileManager.createDirectory(at: dirUrl, withIntermediateDirectories: false)
            }
        }
        
        let tapesURL = baseUrl.appendingPathComponent("Tapes")
        let originalsURL = baseUrl.appendingPathComponent("Originals")
        
        try createDirIfNeeded(at: tapesURL, notDirectoryError: .tapesFileIsNotDirectory)
        try createDirIfNeeded(at: originalsURL, notDirectoryError: .originalsFileIsNotDirectory)
        
        var filesWithErrors = [File: Error]()
        
        files.forEach { file in
            do {
                let actualFileName = try fileNameFor(file: file, tapesDir: tapesURL, originalsDir: originalsURL)
                try file.receivedFile.rawData.write(to: urlForOriginal(originalsDir: originalsURL, fileName: actualFileName))
                try file.receivedFile.tapData(named: file.name).write(to: urlForTape(tapesDir: tapesURL, fileName: actualFileName))
            } catch let error {
                filesWithErrors[file] = error
            }
        }
        
        let filesWithErrorsKeys = filesWithErrors.keys
        self.files = files.filter { filesWithErrorsKeys.contains($0) }
        
        return FileSaveResult(filesWithErrors: filesWithErrors)
    }
    
    private func urlForTape(tapesDir: URL, fileName: String) -> URL {
        tapesDir.appendingPathComponent("\(fileName).tap")
    }
    
    private func urlForOriginal(originalsDir: URL, fileName: String) -> URL {
        originalsDir.appendingPathComponent("\(fileName).data")
    }
    
    struct FileNameIterator: IteratorProtocol {
        let originalFileName: String
        
        var value = 0
        
        mutating func next() -> String? {
            defer { value += 1 }
            
            if value == 0 {
                return originalFileName
            } else {
                return "\(originalFileName)-\(value)"
            }
        }
    }
    
    struct FileNameSequence: LazySequenceProtocol {
        let originalFileName: String
        
        func makeIterator() -> FileNameIterator {
            FileNameIterator(originalFileName: originalFileName)
        }
    }
    
    private func fileNameFor(file: File, tapesDir: URL, originalsDir: URL) throws -> String {
        let fileManager = FileManager.default
        
        for possibleName in FileNameSequence(originalFileName: file.name) {
            let fileExists = fileManager.fileExists(atPath: urlForOriginal(originalsDir: originalsDir, fileName: possibleName).path(percentEncoded: false)) ||
                             fileManager.fileExists(atPath: urlForTape(tapesDir: tapesDir, fileName: possibleName).path(percentEncoded: false))
            
            if fileExists == false {
                return possibleName
            }
        }
        
        return file.name // Should never happen, the sequence is "infinite" (well, until "FileName-Int.max").
    }
    
}
