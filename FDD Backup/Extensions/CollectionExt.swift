//
//  CollectionExt.swift
//  FDD Backup
//
//  Created by Miguel Arroz on 17/02/2026.
//

import Foundation

extension Collection {
    
    @inlinable public subscript(safe index: Index) -> Element? {
        let isValidIndex = index >= startIndex && index < endIndex
        return isValidIndex ? self[index] : nil
    }
    
}
