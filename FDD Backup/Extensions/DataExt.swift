//
//  DataExt.swift
//  FDD Backup
//
//  Created by Miguel Arroz on 17/02/2026.
//

import Foundation

extension Data {
    
    var checksum: UInt8 {
        var checksum: UInt8 = 0
        for b in self {
            checksum ^= b
        }
        return checksum
    }
    
}
