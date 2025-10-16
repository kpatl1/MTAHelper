//
//  LineAppearance.swift
//  mtahelper
//
//  Created by Codex on 10/15/24.
//

import SwiftUI

enum LineAppearance {
    private static let palette: [String: Color] = [
        "1": Color(hex: 0xEE352E),
        "2": Color(hex: 0xEE352E),
        "3": Color(hex: 0xEE352E),
        "4": Color(hex: 0x00933C),
        "5": Color(hex: 0x00933C),
        "6": Color(hex: 0x00933C),
        "6X": Color(hex: 0x00933C),
        "7": Color(hex: 0xB933AD),
        "7X": Color(hex: 0xB933AD),
        "A": Color(hex: 0x0039A6),
        "C": Color(hex: 0x0039A6),
        "E": Color(hex: 0x0039A6),
        "B": Color(hex: 0xFF6319),
        "D": Color(hex: 0xFF6319),
        "F": Color(hex: 0xFF6319),
        "FX": Color(hex: 0xFF6319),
        "M": Color(hex: 0xFF6319),
        "G": Color(hex: 0x6CBE45),
        "J": Color(hex: 0x996633),
        "Z": Color(hex: 0x996633),
        "L": Color(hex: 0xA7A9AC),
        "N": Color(hex: 0xFCCC0A),
        "Q": Color(hex: 0xFCCC0A),
        "R": Color(hex: 0xFCCC0A),
        "W": Color(hex: 0xFCCC0A),
        "S": Color(hex: 0x808183),
        "SIR": Color(hex: 0x006BB6)
    ]

    static func color(for line: String) -> Color {
        palette[line.uppercased()] ?? Color.secondary
    }

    static func textColor(for line: String) -> Color {
        switch line.uppercased() {
        case "N", "Q", "R", "W", "L", "S":
            return Color.black
        default:
            return Color.white
        }
    }
}

extension Color {
    init(hex: UInt32, alpha: Double = 1.0) {
        let red = Double((hex & 0xFF0000) >> 16) / 255.0
        let green = Double((hex & 0x00FF00) >> 8) / 255.0
        let blue = Double(hex & 0x0000FF) / 255.0
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }
}
