//
//  DataBits.swift
//  FDD Backup
//
//  Created by Miguel Arroz on 01/03/2026.
//

struct DataBits: Identifiable, Hashable {
    let dataBits: Int
    let letter: String

    var id: Int { dataBits }

    static let defaultValues: [DataBits] = [
        DataBits(dataBits: 5, letter: "A"),
        DataBits(dataBits: 6, letter: "B"),
        DataBits(dataBits: 7, letter: "C"),
        DataBits(dataBits: 8, letter: "D")
    ]
}


