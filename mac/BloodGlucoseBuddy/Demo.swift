import Foundation

/// Screenshot mode, switched on by the UI-test harness with one environment variable: BGB_DEMO=1.
/// Everything the app would store or send is redirected: its own throwaway settings, an in-memory
/// password, fabricated readings, no Dexcom, no Discord and no login item. Nothing reaches real data.
enum Demo {
    static let isOn = ProcessInfo.processInfo.environment["BGB_DEMO"] == "1"
    private static let env = ProcessInfo.processInfo.environment

    static let defaults: UserDefaults = {
        let name = "com.tanookistudios.bloodglucosebuddy.demo"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)  // a fresh start on every launch
        if env["BGB_DEMO_SIGNED_IN"] == "1" { d.set("you@example.com", forKey: "username") }
        if let mode = env["BGB_DEMO_MODE"] { d.set(mode, forKey: "mode") }
        if let unit = env["BGB_DEMO_UNIT"] { d.set(unit, forKey: "unit") }
        return d
    }()

    static var password: String? = env["BGB_DEMO_SIGNED_IN"] == "1" ? "demo" : nil
    static var openAtLogin = true

    /// A made-up reading, two minutes old.
    static func reading() -> Reading {
        Reading(mgdl: Int(env["BGB_DEMO_MGDL"] ?? "") ?? 112,
                trend: Trend(rawValue: env["BGB_DEMO_TREND"] ?? "") ?? .fortyFiveUp,
                date: Date().addingTimeInterval(-120))
    }
}
