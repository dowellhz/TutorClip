enum KeyCodeDisplay {
    static let defaultKeyCode: UInt32 = 31
    static let defaultModifiers: UInt32 = 256 | 512
    static let legacyDefaultKeyCode: UInt32 = 31
    static let legacyDefaultModifiers: UInt32 = 256

    static func isDisallowedShortcutKey(_ keyCode: UInt32) -> Bool {
        [36, 48, 49, 51, 53, 117].contains(keyCode)
    }

    static func name(for keyCode: UInt32) -> String {
        switch keyCode {
        case 0: return "A"
        case 1: return "S"
        case 2: return "D"
        case 3: return "F"
        case 4: return "H"
        case 5: return "G"
        case 6: return "Z"
        case 7: return "X"
        case 8: return "C"
        case 9: return "V"
        case 11: return "B"
        case 12: return "Q"
        case 13: return "W"
        case 14: return "E"
        case 15: return "R"
        case 16: return "Y"
        case 17: return "T"
        case 31: return "O"
        case 35: return "P"
        case 36: return "Return"
        case 48: return "Tab"
        case 49: return "Space"
        case 51: return "Delete"
        case 53: return "Esc"
        case 117: return "Forward Delete"
        default: return "Key \(keyCode)"
        }
    }
}
