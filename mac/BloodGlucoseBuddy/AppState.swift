import Foundation
import ServiceManagement
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    /// The "Blood Glucose" application on Discord's developer site. Not a secret.
    static let discordClientID = "1558184055437004933"

    private let defaults = UserDefaults.standard
    private let dexcom = DexcomClient()
    private let discord = DiscordIPC(clientID: AppState.discordClientID)
    private let discordQueue = DispatchQueue(label: "com.tanookistudios.bloodglucosebuddy.discord")

    @Published var mode: DisplayMode { didSet { defaults.set(mode.rawValue, forKey: "mode"); refreshDiscord() } }
    @Published var unit: GlucoseUnit { didSet { defaults.set(unit.rawValue, forKey: "unit"); refreshDiscord() } }
    @Published var verb: StatusVerb { didSet { defaults.set(verb.rawValue, forKey: "verb"); refreshDiscord() } }
    @Published var lowThreshold: Int { didSet { defaults.set(lowThreshold, forKey: "low"); refreshDiscord() } }
    @Published var highThreshold: Int { didSet { defaults.set(highThreshold, forKey: "high"); refreshDiscord() } }

    @Published private(set) var username: String
    @Published private(set) var region: DexcomRegion
    @Published private(set) var isSignedIn: Bool
    @Published private(set) var reading: Reading?
    @Published private(set) var dexcomProblem: String?
    @Published private(set) var discordConnected = false
    @Published private(set) var discordProblem: String?
    @Published private(set) var now = Date()

    private var lastFetch: Date?
    /// Set after a wrong password or lockout so we stop retrying and don't get the Dexcom account locked.
    private var authBlocked = false

    init() {
        mode = DisplayMode(rawValue: defaults.string(forKey: "mode") ?? "") ?? .number
        unit = GlucoseUnit(rawValue: defaults.string(forKey: "unit") ?? "") ?? .mgdl
        verb = StatusVerb(rawValue: defaults.string(forKey: "verb") ?? "") ?? .watching
        lowThreshold = defaults.object(forKey: "low") as? Int ?? 70
        highThreshold = defaults.object(forKey: "high") as? Int ?? 180
        let savedUser = defaults.string(forKey: "username") ?? ""
        username = savedUser
        region = DexcomRegion(rawValue: defaults.string(forKey: "region") ?? "") ?? .us
        isSignedIn = !savedUser.isEmpty && Keychain.password(for: savedUser) != nil

        Task { [weak self] in
            while let self, !Task.isCancelled {
                await self.tick()
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    // MARK: Text for the menu

    var menuBarTitle: String? {
        guard isSignedIn, let r = reading, Presence.isFresh(r, now: now) else { return nil }
        let value = Presence.format(r.mgdl, unit)
            .replacingOccurrences(of: " mg/dL", with: "")
            .replacingOccurrences(of: " mmol/L", with: "")
        return "\(value) \(r.trend.arrow)".trimmingCharacters(in: .whitespaces)
    }

    var readingLine: String {
        guard let r = reading else { return "Waiting for first reading…" }
        guard Presence.isFresh(r, now: now) else { return "No recent reading" }
        return "\(Presence.format(r.mgdl, unit)) \(r.trend.arrow) \(r.trend.word)"
    }

    var ageLine: String? {
        guard let r = reading else { return nil }
        let minutes = Int(now.timeIntervalSince(r.date) / 60)
        return minutes < 1 ? "Reading from just now" : "Reading from \(minutes) min ago"
    }

    var discordLine: String {
        if discordConnected { return isSignedIn ? "Discord: showing your status" : "Discord: connected" }
        return discordProblem ?? "Discord: connecting…"
    }

    var openAtLogin: Bool { SMAppService.mainApp.status == .enabled }

    func setOpenAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            dexcomProblem = "Couldn't change Open at Login: \(error.localizedDescription)"
        }
        objectWillChange.send()
    }

    // MARK: Account

    /// Returns an error message, or nil on success.
    func signIn(username: String, password: String, region: DexcomRegion) async -> String? {
        let user = username.trimmingCharacters(in: .whitespacesAndNewlines)
        await dexcom.reset()
        do {
            let r = try await dexcom.latestReading(username: user, password: password, region: region)
            guard Keychain.save(password, for: user) else { return "Couldn't save the password to your Keychain." }
            if !self.username.isEmpty && self.username != user { Keychain.delete(self.username) }
            self.username = user
            self.region = region
            defaults.set(user, forKey: "username")
            defaults.set(region.rawValue, forKey: "region")
            isSignedIn = true
            authBlocked = false
            lastFetch = Date()
            reading = r
            dexcomProblem = r == nil ? "Signed in, but Dexcom has no readings from the last 24 hours. Is Share turned on?" : nil
            if !defaults.bool(forKey: "loginItemSetUp") {
                defaults.set(true, forKey: "loginItemSetUp")
                setOpenAtLogin(true)
            }
            await pushToDiscord()
            return nil
        } catch {
            await dexcom.reset()
            return error.localizedDescription
        }
    }

    func signOut() {
        Keychain.delete(username)
        username = ""
        defaults.removeObject(forKey: "username")
        isSignedIn = false
        reading = nil
        dexcomProblem = nil
        Task {
            await dexcom.reset()
            await pushToDiscord()
        }
    }

    // MARK: Loop

    private func tick() async {
        now = Date()
        if isSignedIn && !authBlocked && shouldFetch { await fetch() }
        await pushToDiscord()
    }

    private var shouldFetch: Bool {
        guard let last = lastFetch else { return true }
        let sinceFetch = now.timeIntervalSince(last)
        if sinceFetch >= 300 { return true }
        // A new reading lands every 5 minutes; once ours is that old, check each minute so we catch it quickly.
        if let r = reading, now.timeIntervalSince(r.date) > 310, sinceFetch >= 60 { return true }
        return false
    }

    private func fetch() async {
        lastFetch = Date()
        guard let password = Keychain.password(for: username) else {
            isSignedIn = false
            return
        }
        do {
            if let r = try await dexcom.latestReading(username: username, password: password, region: region) {
                reading = r
                dexcomProblem = nil
            } else {
                dexcomProblem = "Dexcom has no readings from the last 24 hours."
            }
        } catch let e as DexcomError where e == .badCredentials || e == .lockedOut {
            authBlocked = true
            dexcomProblem = (e.errorDescription ?? "") + " Open Settings to sign in again."
        } catch {
            dexcomProblem = "Couldn't reach Dexcom. Will keep trying. (\(error.localizedDescription))"
        }
    }

    private func refreshDiscord() {
        Task { await pushToDiscord() }
    }

    /// Sends the current status every tick, so a restarted Discord picks it up again within 30 seconds.
    private func pushToDiscord() async {
        let activity: [String: Any]? = isSignedIn
            ? Presence.activity(reading: reading, now: Date(), mode: mode, unit: unit, verb: verb,
                                low: lowThreshold, high: highThreshold)
            : nil
        let discord = self.discord
        let error: Error? = await withCheckedContinuation { done in
            discordQueue.async {
                do {
                    try discord.setActivity(activity)
                    done.resume(returning: nil)
                } catch {
                    done.resume(returning: error)
                }
            }
        }
        discordConnected = error == nil
        discordProblem = error.map { "Discord: " + (($0 as? LocalizedError)?.errorDescription ?? $0.localizedDescription) }
    }
}
