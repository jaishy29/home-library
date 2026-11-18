import Foundation

enum ISBN {
    /// Keeps digits and X only.
    static func clean(_ s: String) -> String {
        String(s.uppercased().filter { $0.isNumber || $0 == "X" })
    }

    static func isValid13(_ d: String) -> Bool {
        let digits = d.compactMap { $0.wholeNumberValue }
        guard d.count == 13, digits.count == 13 else { return false }
        var sum = 0
        for i in 0..<12 { sum += digits[i] * (i % 2 == 0 ? 1 : 3) }
        return (10 - sum % 10) % 10 == digits[12]
    }

    static func isValid10(_ d: String) -> Bool {
        guard d.count == 10 else { return false }
        var sum = 0
        for (i, c) in d.enumerated() {
            let v: Int
            if c == "X" && i == 9 { v = 10 } else if let n = c.wholeNumberValue { v = n } else { return false }
            sum += v * (10 - i)
        }
        return sum % 11 == 0
    }

    static func to13(_ d: String) -> String {
        guard d.count == 10 else { return d }
        let base = "978" + d.prefix(9)
        let digits = base.compactMap { $0.wholeNumberValue }
        var sum = 0
        for i in 0..<12 { sum += digits[i] * (i % 2 == 0 ? 1 : 3) }
        return base + String((10 - sum % 10) % 10)
    }

    /// Returns a valid ISBN-13, or nil.
    static func normalize(_ s: String) -> String? {
        let d = clean(s)
        if isValid13(d) { return d }
        if isValid10(d) { return to13(d) }
        return nil
    }

    static func format(_ d: String) -> String {
        guard d.count == 13 else { return d }
        let a = d.prefix(3), b = d.dropFirst(3).prefix(9), c = d.suffix(1)
        return "\(a)-\(b)-\(c)"
    }

    /// Bookland barcodes start with 978/979.
    static func isBookBarcode(_ s: String) -> Bool {
        let d = clean(s)
        return (d.hasPrefix("978") || d.hasPrefix("979")) && isValid13(d)
    }
}
