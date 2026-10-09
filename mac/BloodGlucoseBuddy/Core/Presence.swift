import Foundation

enum DisplayMode: String, CaseIterable, Identifiable {
    case number, dot
    var id: Self { self }
    var label: String { self == .number ? "Number" : "Colored dot only" }
}

enum GlucoseUnit: String, CaseIterable, Identifiable {
    case mgdl, mmol
    var id: Self { self }
    var label: String { self == .mgdl ? "mg/dL" : "mmol/L" }
}

enum StatusVerb: String, CaseIterable, Identifiable {
    case watching, playing
    var id: Self { self }
    var label: String { self == .watching ? "Watching" : "Playing" }
    var activityType: Int { self == .watching ? 3 : 0 }
}

enum Band: Equatable {
    case low, inRange, high
    var word: String {
        switch self {
        case .low: return "Low"
        case .inRange: return "In range"
        case .high: return "High"
        }
    }
    var asset: String {
        switch self {
        case .low: return "v2_dot_red"
        case .inRange: return "v2_dot_green"
        case .high: return "v2_dot_yellow"
        }
    }
}

enum Presence {
    /// Older than this, show "No reading" rather than a number that isn't current.
    static let staleAfter: TimeInterval = 15 * 60

    static func format(_ mgdl: Int, _ unit: GlucoseUnit) -> String {
        if mgdl <= 39 { return "LOW" }   // Dexcom reports anything under 40 as 39
        if mgdl >= 401 { return "HIGH" } // and anything over 400 as 401
        switch unit {
        case .mgdl: return "\(mgdl) mg/dL"
        case .mmol: return String(format: "%.1f mmol/L", Double(mgdl) / 18.0182)
        }
    }

    static func band(_ mgdl: Int, low: Int, high: Int) -> Band {
        if mgdl < low { return .low }
        if mgdl > high { return .high }
        return .inRange
    }

    static func isFresh(_ reading: Reading?, now: Date) -> Bool {
        guard let reading else { return false }
        return now.timeIntervalSince(reading.date) <= staleAfter
    }

    static func activity(reading: Reading?, now: Date, mode: DisplayMode, unit: GlucoseUnit,
                         verb: StatusVerb, low: Int, high: Int) -> [String: Any] {
        var activity: [String: Any] = ["type": verb.activityType]
        guard let r = reading, isFresh(r, now: now) else {
            activity["details"] = "No reading"
            activity["assets"] = ["large_image": "v2_dot_gray", "large_text": "No recent reading"]
            return activity
        }
        let b = band(r.mgdl, low: low, high: high)
        switch mode {
        case .number:
            activity["details"] = "\(format(r.mgdl, unit)) \(r.trend.arrow)".trimmingCharacters(in: .whitespaces)
            if !r.trend.word.isEmpty { activity["state"] = r.trend.word }
            activity["assets"] = ["large_image": r.trend.asset ?? b.asset, "large_text": b.word]
        case .dot:
            activity["details"] = b.word
            activity["assets"] = ["large_image": b.asset, "large_text": b.word]
        }
        // Discord shows this as "mm:ss elapsed", i.e. how old the reading is.
        activity["timestamps"] = ["start": Int(r.date.timeIntervalSince1970 * 1000)]
        return activity
    }
}
