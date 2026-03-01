//
//  DataReceiver.swift
//  FDD Backup
//
//  Created by Miguel Arroz on 17/02/2026.
//

import Foundation
import Combine

/**
 Note: all numbers are in little endian format
 */
@MainActor
class DataReceiver {
    
    struct Progress {
        let progressValue: ProgressValue
        let description: String
        
        static var indeterminate: Progress {
            Progress(progressValue: .indeterminate, description: String(localized: "Waiting for file header…"))
        }
    }
    
    enum ProgressValue {
        case indeterminate
        case value(Int, of: Int)
    }
    
    enum FileType: UInt8 {
        case program = 0
        case numericArray = 1
        case alphanumericArray = 2
        case bytes = 3
        
        var headerSize: Int {
            switch self {
            case .program: 8
            case .numericArray: 8
            case .alphanumericArray: 8
            case .bytes: 6
            }
        }
        
        var localizedDescription: String {
            switch self {
            case .program: String(localized: "Program")
            case .numericArray: String(localized: "Numeric Array")
            case .alphanumericArray: String(localized: "Alphanumeric Array")
            case .bytes: String(localized: "Bytes")
            }
        }
        
        var isArray: Bool {
            switch self {
            case .numericArray, .alphanumericArray: true
            case .program, .bytes: false
            }
        }
    }
    
    protocol FileMetadata {
        var fileType: FileType { get }
        var headerSize: Int { get }
        var dataLength: UInt16 { get }
        var expectedRawSize: Int { get }
        
        func tapHeaderData(named name: String) -> Data
        var specificHeaderData: Data { get }
    }
    
    struct ProgramMetadata: FileMetadata {
        var fileType: FileType { .program }
        
        let autoStart: UInt16
        let dataLength: UInt16
        let programLength: UInt16
        
        var specificHeaderData: Data {
            return Data(
                dataLength.littleEndianData +
                autoStart.littleEndianData +
                programLength.littleEndianData
            )
        }
    }
    
    struct ArrayMetadata: FileMetadata {
        let fileType: FileType // Must be .numericArray or .alphanumericArray
        
        let fullLength: UInt16
        let address: UInt16
        let dataLength: UInt16
        
        var specificHeaderData: Data {
            return Data(
                dataLength.littleEndianData +
                UInt8(0).littleEndianData +
                UInt8(fileType == .numericArray ? 129 : 193).littleEndianData + // Hack, we always use var name
                // a or $a. Does not matter really since the user always needs to specify the var name on LOAD.
                UInt16(32768).littleEndianData // Unused
            )
        }
        
        init(fileType: FileType, fullLength: UInt16, address: UInt16, dataLength: UInt16) {
            guard fileType.isArray else { fatalError() }
            
            self.fileType = fileType
            self.fullLength = fullLength
            self.address = address
            self.dataLength = dataLength
        }
    }
    
    enum Status {
        case waiting
        case receiving(FileMetadata)
    }
    
    struct CompleteFile {
        let metadata: FileMetadata
        let data: Data
        let rawData: Data
        
        func tapData(named name: String) -> Data {
            var result = metadata.tapHeaderData(named: name)
            
            let firstIndexOfSecondBlock = result.endIndex
            
            // Second block size
            result.append(UInt16(data.count + 2).littleEndianData)
            // Loading flag
            result.append(0xff)
            
            result.append(data)
            
            result.append(result[firstIndexOfSecondBlock.advanced(by: 2)..<result.endIndex].checksum)
            
            return result
        }
    }
    
    private(set) var buffer = Data()
    
    private(set) var status: Status = .waiting {
        didSet {
            switch status {
            case .waiting:
                progressPublisher.send(.indeterminate)
            case .receiving(let fileMetadata):
                progressPublisher.send(Progress(progressValue: .value(min(buffer.count, fileMetadata.expectedRawSize), of: Int(fileMetadata.dataLength)), description: String(localized: "Receiving \(fileMetadata.fileType.localizedDescription)")))
            }
        }
    }
    
    let logPublisher = PassthroughSubject<String, Never>()
    
    let completeFilePublisher = PassthroughSubject<CompleteFile, Never>()
    
    let progressPublisher = CurrentValueSubject<Progress, Never>(.indeterminate)
    
    init() {
        self.buffer.reserveCapacity(0x10000)
    }
    
    func received(data: Data) {
        process(data: data)
    }
    
    /**
     
     - returns: `false` if processing should continue on caller, `true` otherwise.
     */
    private func processInitialData() -> Bool {
        var done = false
        
        repeat {
            // No bytes to process, leave and wait for more
            if buffer.isEmpty { break }
            
            // First byte must be 0, so consume buffer until we found a 0
            guard let firstByte = buffer[safe: buffer.startIndex],
                  firstByte == 0 else {
                logPublisher.send("Initial byte is not 0, skipping.")
                buffer.removeFirst()
                continue
            }
            
            // Let's look into the file type.
            guard let secondByte = buffer[safe: buffer.startIndex.advanced(by: 1)] else {
                break // Wait for the second byte to arrive
            }
            
            guard let fileType = FileType(rawValue: secondByte) else {
                logPublisher.send("Invalid file type, skipping first two bytes.")
                buffer.removeFirst(2)
                continue
            }
            
            done = true
            
            switch fileType {
            case .program: return processProgram()
            case .numericArray: return processArray()
            case .alphanumericArray: return processArray()
            case .bytes: fatalError()
            }
        } while done == false
        
        return true
    }
    
    private func processProgram() -> Bool {
        /*
         The program file header sent by the FDD has 8 bytes in the following structure:
         
         +----+----+----+----+----+----+----+----+
         | 00 | 00 |  start  |  data   | program |
         |    |    |  line   | length  | length  |
         +----+----+----+----+----+----+----+----+
         
          ^^^^ -> Initial header mark, already processed
               ^^^^ -> File type, 00 is "Basic program".
         
         Start line is 0x00 when not defined;
         Program length <= data length (the difference is the offset for variables)
         
         So, we already processed the first two bytes to get here, let's address the other 6:
         */
        
        guard buffer.count >= 8 else {
            return true // The full header has not arrived yet, wait
        }
        
        let autoStart = UInt16(fromDataInLittleEndian: buffer.suffix(from: buffer.startIndex.advanced(by: 2)))
        let dataLength = UInt16(fromDataInLittleEndian: buffer.suffix(from: buffer.startIndex.advanced(by: 4)))
        let programLength = UInt16(fromDataInLittleEndian: buffer.suffix(from: buffer.startIndex.advanced(by: 6)))
        
        status = .receiving(ProgramMetadata(autoStart: autoStart, dataLength: dataLength, programLength: programLength))
        
        return false
    }
    
    private func processArray() -> Bool {
        /*
         The array file header (both alphanumeric and numeric) sent by the FDD has 8 bytes in the following structure:
         
         +----+----+----+----+----+----+----+----+
         | 00 | xx |  full   | address |  array  |
         |    |    |  length |         |  length |
         +----+----+----+----+----+----+----+----+
         
          ^^^^ -> Initial header mark, already processed
               ^^^^ -> File type, 01 for numeric array, 02 for alphanumeric array
         
         The address is not used on tape files.
         Full length = array length + 2
         */
        
        guard buffer.count >= 8 else {
            return true // The full header has not arrived yet, wait
        }
        
        guard let type = FileType(rawValue: UInt8(fromDataInLittleEndian: buffer.suffix(from: buffer.startIndex.advanced(by: 1)))) else {
            fatalError()
        }
        let fullLength = UInt16(fromDataInLittleEndian: buffer.suffix(from: buffer.startIndex.advanced(by: 2)))
        let address = UInt16(fromDataInLittleEndian: buffer.suffix(from: buffer.startIndex.advanced(by: 4)))
        let dataLength = UInt16(fromDataInLittleEndian: buffer.suffix(from: buffer.startIndex.advanced(by: 6)))
        
        status = .receiving(ArrayMetadata(fileType: type, fullLength: fullLength, address: address, dataLength: dataLength))
        
        return false
    }
    
    private func processContent(for metadata: FileMetadata) -> Bool {
        progressPublisher
            .send(
                Progress(
                    progressValue: .value(min(buffer.count - metadata.headerSize, Int(metadata.dataLength)), of: Int(metadata.dataLength)),
                    description: String(localized: "Receiving \(metadata.fileType.localizedDescription)")))
        
        guard buffer.count >= metadata.expectedRawSize else {
            return true // We don't have the full file yet, wait
        }
        
        let file = CompleteFile(
            metadata: metadata,
            data: buffer[buffer.startIndex.advanced(by: metadata.headerSize)..<buffer.startIndex.advanced(by: metadata.expectedRawSize)],
            rawData: buffer[buffer.startIndex..<buffer.startIndex.advanced(by: metadata.expectedRawSize)])
        completeFilePublisher.send(file)
        status = .waiting
        buffer.removeFirst(metadata.expectedRawSize)
        return false
    }
    
    private func process(data: Data) {
        buffer.append(data)
        
        var done = false
        
        repeat {
            
//            print("Buffer: \(buffer.map { String(format:"%02X", $0) }.joined(separator: " "))")
            
            switch status {
            case .waiting:
                done = processInitialData()

            case .receiving(let metadata):
                done = processContent(for: metadata)
            }
        } while done == false
    }
    
    func reset() {
        buffer.removeAll()
        status = .waiting
    }
    
}



extension DataReceiver.FileMetadata {
    var headerSize: Int { fileType.headerSize }
    
    var expectedRawSize: Int {
        fileType.headerSize + Int(dataLength)
    }
    
    func tapHeaderData(named name: String) -> Data {
        var tapeName = (name.data(using: .isoLatin1) ?? Data("??????????".utf8)).prefix(10)
        tapeName += Data(repeating: 0x20, count: 10 - tapeName.count) // Pad with spaces
        
        var result = Data()
        
        // First block size
        result.append(UInt16(0x13).littleEndianData)
        
        // Loading flag
        result.append(00)
        
        result.append(fileType.rawValue)
        result.append(contentsOf: tapeName)
        
        result.append(specificHeaderData)
        
        result.append(result[result.startIndex.advanced(by: 2)..<result.endIndex].checksum)
        
        return result
    }
}
