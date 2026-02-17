//
//  FixedWidthIntegerExt.swift
//  FDD Backup
//
//  Created by Miguel Arroz on 16/02/2026.
//

import Foundation

extension FixedWidthInteger {
    
    var littleEndianData: Data {
        var data = Data()
        withUnsafeBytes(of: littleEndian, { (bytes) in
            data.append(contentsOf: bytes)
        })
        return data
    }
    
    init(fromDataInLittleEndian data: Data) {
        var output = Self()
        withUnsafeMutableBytes(of: &output) { outputPtr in
            data[data.startIndex ..< data.startIndex.advanced(by: MemoryLayout<Self>.size)].withUnsafeBytes { sourcePtr in
                outputPtr.copyMemory(from: sourcePtr)
            }
        }
        self = Self(littleEndian: output)
    }
    
}
