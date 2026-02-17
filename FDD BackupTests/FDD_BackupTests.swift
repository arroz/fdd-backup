//
//  FDD_BackupTests.swift
//  FDD BackupTests
//
//  Created by Miguel Arroz on 16/02/2026.
//

import Testing
import Foundation
@testable import FDD_Backup
internal import Combine

@MainActor
struct FDD_BackupTests {
    
    private class DummyClass { }
    
    static var redAlertData: Data {
        guard let url = Bundle(for: DummyClass.self).url(forResource: "redalert", withExtension: "dat"),
              let data = try? Data(contentsOf: url) else {
            
            preconditionFailure("Unable to load redalert.dat from test resources")
        }
        return data
    }
    
    static var numberData: Data {
        guard let url = Bundle(for: DummyClass.self).url(forResource: "number", withExtension: "dat"),
              let data = try? Data(contentsOf: url) else {
            
            preconditionFailure("Unable to load number.dat from test resources")
        }
        return data
    }

    @Test func readAllAtOnce() async throws {
        let dataReceiver = DataReceiver()
        var files = [DataReceiver.CompleteFile]()
        var logs = [String]()
        let fileSubscription = dataReceiver.completeFilePublisher
            .sink { file in
                files.append(file)
            }
        let logSubscription = dataReceiver.logPublisher
            .sink { log in
                logs.append(log)
            }
        dataReceiver.received(data: Self.redAlertData)
        
        #expect(logs.count == 0)
        #expect(files.count == 1)
        let file = try #require(files.first)
        let metadata = try #require(file.metadata as? DataReceiver.ProgramMetadata)
        
        #expect(metadata.autoStart == 0x0001)
        #expect(metadata.programLength == 0x00f2)
        #expect(metadata.dataLength == 0x0115)

        #expect(file.data.count == 0x0115)
        #expect(file.data == Self.redAlertData.suffix(from: 8))
        
        fileSubscription.cancel()
        logSubscription.cancel()
    }
    
    @Test func readByteByByte() async throws {
        let dataReceiver = DataReceiver()
        var files = [DataReceiver.CompleteFile]()
        var logs = [String]()
        let fileSubscription = dataReceiver.completeFilePublisher
            .sink { file in
                files.append(file)
            }
        let logSubscription = dataReceiver.logPublisher
            .sink { log in
                logs.append(log)
            }
        
        let data = Self.redAlertData
        
        for (index, element) in data.enumerated() {
            dataReceiver.received(data: Data([element]))
            
            switch dataReceiver.status {
            case .waiting:
                #expect(index < 8 || index == data.count - 1)
            case .receiving(let metadata):
                let metadata = try #require(metadata as? DataReceiver.ProgramMetadata)
                #expect(metadata.autoStart == 0x0001)
                #expect(metadata.programLength == 0x00f2)
                #expect(metadata.dataLength == 0x0115)
            }
            
            if index < data.count - 1 {
                #expect(dataReceiver.buffer.count == index + 1)
            } else {
                #expect(dataReceiver.buffer.count == 0)
            }
            
        }
        
        #expect(logs.count == 0)
        #expect(files.count == 1)
        let file = try #require(files.first)
        let metadata = try #require(file.metadata as? DataReceiver.ProgramMetadata)
        
        #expect(metadata.autoStart == 0x0001)
        #expect(metadata.programLength == 0x00f2)
        #expect(metadata.dataLength == 0x0115)

        #expect(file.data.count == 0x0115)
        #expect(file.data == Self.redAlertData.suffix(from: 8))
        
        fileSubscription.cancel()
        logSubscription.cancel()
    }
    
    @Test func sendGarbageBeforeFile() async throws {
        let dataReceiver = DataReceiver()
        var files = [DataReceiver.CompleteFile]()
        var logs = [String]()
        let fileSubscription = dataReceiver.completeFilePublisher
            .sink { file in
                files.append(file)
            }
        let logSubscription = dataReceiver.logPublisher
            .sink { log in
                logs.append(log)
            }
        dataReceiver.received(data: "Garbage".data(using: .utf8)! + Self.redAlertData)
        
        #expect(logs.count == 7)
        logs.forEach { log in
            #expect(log == "Initial byte is not 0, skipping.")
        }
        
        #expect(files.count == 1)
        let file = try #require(files.first)
        let metadata = try #require(file.metadata as? DataReceiver.ProgramMetadata)
        
        #expect(metadata.autoStart == 0x0001)
        #expect(metadata.programLength == 0x00f2)
        #expect(metadata.dataLength == 0x0115)

        #expect(file.data.count == 0x0115)
        #expect(file.data == Self.redAlertData.suffix(from: 8))
        
        fileSubscription.cancel()
        logSubscription.cancel()
    }
    
    @Test func sendInvalidFileType() async throws {
        let dataReceiver = DataReceiver()
        var files = [DataReceiver.CompleteFile]()
        var logs = [String]()
        let fileSubscription = dataReceiver.completeFilePublisher
            .sink { file in
                files.append(file)
            }
        let logSubscription = dataReceiver.logPublisher
            .sink { log in
                logs.append(log)
            }
        dataReceiver.received(data: Data([0, 5]) + Self.redAlertData)
        
        #expect(logs.count == 1)
        logs.forEach { log in
            #expect(log == "Invalid file type, skipping first two bytes.")
        }
        
        #expect(files.count == 1)
        let file = try #require(files.first)
        let metadata = try #require(file.metadata as? DataReceiver.ProgramMetadata)
        
        #expect(metadata.autoStart == 0x0001)
        #expect(metadata.programLength == 0x00f2)
        #expect(metadata.dataLength == 0x0115)

        #expect(file.data.count == 0x0115)
        #expect(file.data == Self.redAlertData.suffix(from: 8))
        
        fileSubscription.cancel()
        logSubscription.cancel()
    }
    
    @Test func sendMixOfGarbageAndInvalidFileType() async throws {
        let dataReceiver = DataReceiver()
        var files = [DataReceiver.CompleteFile]()
        var logs = [String]()
        let fileSubscription = dataReceiver.completeFilePublisher
            .sink { file in
                files.append(file)
            }
        let logSubscription = dataReceiver.logPublisher
            .sink { log in
                logs.append(log)
            }
        dataReceiver.received(data: Data([34, 12, 0, 5, 27]) + Self.redAlertData)
        
        #expect(logs.count == 4)
        #expect(logs[0] == "Initial byte is not 0, skipping.")
        #expect(logs[1] == "Initial byte is not 0, skipping.")
        #expect(logs[2] == "Invalid file type, skipping first two bytes.")
        #expect(logs[3] == "Initial byte is not 0, skipping.")
        
        #expect(files.count == 1)
        let file = try #require(files.first)
        let metadata = try #require(file.metadata as? DataReceiver.ProgramMetadata)
        
        #expect(metadata.autoStart == 0x0001)
        #expect(metadata.programLength == 0x00f2)
        #expect(metadata.dataLength == 0x0115)

        #expect(file.data.count == 0x0115)
        #expect(file.data == Self.redAlertData.suffix(from: 8))
        
        fileSubscription.cancel()
        logSubscription.cancel()
    }
    
    @Test func readTwoPrograms() async throws {
        let dataReceiver = DataReceiver()
        var files = [DataReceiver.CompleteFile]()
        var logs = [String]()
        let fileSubscription = dataReceiver.completeFilePublisher
            .sink { file in
                files.append(file)
            }
        let logSubscription = dataReceiver.logPublisher
            .sink { log in
                logs.append(log)
            }
        dataReceiver.received(data: Self.redAlertData + Self.numberData)
        
        #expect(logs.count == 0)
        #expect(files.count == 2)
        do {
            let file = try #require(files[safe: 0])
            let metadata = try #require(file.metadata as? DataReceiver.ProgramMetadata)
            
            #expect(metadata.autoStart == 0x0001)
            #expect(metadata.programLength == 0x00f2)
            #expect(metadata.dataLength == 0x0115)
            
            #expect(file.data.count == 0x0115)
            #expect(file.data == Self.redAlertData.suffix(from: 8))
        }
        do {
            let file = try #require(files[safe: 1])
            let metadata = try #require(file.metadata as? DataReceiver.ProgramMetadata)
            
            #expect(metadata.autoStart == 0x0000)
            #expect(metadata.programLength == 0x000e)
            #expect(metadata.dataLength == 0x0014)
            
            #expect(file.data.count == 0x0014)
            #expect(file.data == Self.numberData.suffix(from: 8))
        }
        
        fileSubscription.cancel()
        logSubscription.cancel()
    }

}
