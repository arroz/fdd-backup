//
//  StopBits.swift
//  FDD Backup
//
//  Created by Miguel Arroz on 01/03/2026.
//


struct StopBits: Identifiable, Hashable {
    let stopBits: Int
    let letter: String

    var id: Int { stopBits }

    static let defaultValues: [StopBits] = [
        StopBits(stopBits: 1, letter: "A"),
        StopBits(stopBits: 2, letter: "C")
    ]
}
