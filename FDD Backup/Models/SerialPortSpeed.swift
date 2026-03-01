//
//  Speed.swift
//  FDD Backup
//
//  Created by Miguel Arroz on 01/03/2026.
//


struct SerialPortSpeed: Identifiable, Hashable {
    let bps: Int
    let letter: String
    
    var id: Int { bps }
    
    static let defaultSpeeds: [SerialPortSpeed] = [
        SerialPortSpeed(bps: 50, letter: "A"),
        SerialPortSpeed(bps: 75, letter: "B"),
        SerialPortSpeed(bps: 110, letter: "C"),
        SerialPortSpeed(bps: 134, letter: "D"),
        SerialPortSpeed(bps: 150, letter: "E"),
        SerialPortSpeed(bps: 200, letter: "F"),
        SerialPortSpeed(bps: 300, letter: "G"),
        SerialPortSpeed(bps: 600, letter: "H"),
        SerialPortSpeed(bps: 1200, letter: "I"),
        SerialPortSpeed(bps: 1800, letter: "J"),
        SerialPortSpeed(bps: 2400, letter: "K"),
        SerialPortSpeed(bps: 4800, letter: "M"),
        SerialPortSpeed(bps: 7200, letter: "N"),
        SerialPortSpeed(bps: 9600, letter: "O"),
        SerialPortSpeed(bps: 19200, letter: "P")
    ]
}

