import Foundation

enum DexcomRegion: String, CaseIterable, Identifiable {
    case us, outsideUS, japan
    var id: Self { self }

    var label: String {
        switch self {
        case .us: return "United States"
        case .outsideUS: return "Outside the US"
        case .japan: return "Japan"
        }
    }

    var baseURL: URL {
        switch self {
        case .us: return URL(string: "https://share2.dexcom.com/ShareWebServices/Services/")!
        case .outsideUS: return URL(string: "https://shareous1.dexcom.com/ShareWebServices/Services/")!
        case .japan: return URL(string: "https://share.dexcom.jp/ShareWebServices/Services/")!
        }
    }

    /// Dexcom's account website. After sign-in it lands on /profile/<account ID>.
    var accountSiteURL: URL? {
        switch self {
        case .us: return URL(string: "https://uam1.dexcom.com/")
        case .outsideUS: return URL(string: "https://uam2.dexcom.com/")
        case .japan: return nil
        }
    }

    // Public Share application IDs, the same ones Dexcom's own apps send.
    var applicationID: String {
        self == .japan ? "d8665ade-9673-4e27-9ff6-92db4ce13d13" : "d89443d2-327c-4a6f-89e5-496bbb0317db"
    }
}

enum Trend: String {
    case none = "None", doubleUp = "DoubleUp", singleUp = "SingleUp", fortyFiveUp = "FortyFiveUp", flat = "Flat",
         fortyFiveDown = "FortyFiveDown", singleDown = "SingleDown", doubleDown = "DoubleDown",
         notComputable = "NotComputable", rateOutOfRange = "RateOutOfRange"

    // Older Share replies send the trend as a number, in this order.
    static let byNumber: [Trend] = [.none, .doubleUp, .singleUp, .fortyFiveUp, .flat,
                                    .fortyFiveDown, .singleDown, .doubleDown, .notComputable, .rateOutOfRange]

    var arrow: String {
        switch self {
        case .doubleUp: return "⇈"
        case .singleUp: return "↑"
        case .fortyFiveUp: return "↗"
        case .flat: return "→"
        case .fortyFiveDown: return "↘"
        case .singleDown: return "↓"
        case .doubleDown: return "⇊"
        default: return ""
        }
    }

    var word: String {
        switch self {
        case .doubleUp: return "Rising fast"
        case .singleUp: return "Rising"
        case .fortyFiveUp: return "Rising slowly"
        case .flat: return "Steady"
        case .fortyFiveDown: return "Falling slowly"
        case .singleDown: return "Falling"
        case .doubleDown: return "Falling fast"
        default: return ""
        }
    }

    /// Discord art asset key, uploaded to the "Blood Glucose" application.
    var asset: String? {
        switch self {
        case .doubleUp: return "double_up"
        case .singleUp: return "up"
        case .fortyFiveUp: return "up_45"
        case .flat: return "flat"
        case .fortyFiveDown: return "down_45"
        case .singleDown: return "down"
        case .doubleDown: return "double_down"
        default: return nil
        }
    }
}

struct Reading: Equatable {
    let mgdl: Int
    let trend: Trend
    let date: Date
}

enum DexcomError: LocalizedError, Equatable {
    case badCredentials, lockedOut, sessionExpired, server(String)

    var errorDescription: String? {
        switch self {
        case .badCredentials: return "Dexcom didn't accept that username and password."
        case .lockedOut: return "Dexcom has locked the account after too many tries. Wait a while, then sign in again."
        case .sessionExpired: return "Dexcom session expired."
        case .server(let message): return message
        }
    }
}

enum DexcomParser {
    /// The account ID from Dexcom's profile page address, and only from there:
    /// the sign-in pages carry other IDs (like the website's own client ID) that must not be mistaken for it.
    static func accountID(fromProfileURL url: URL?) -> String? {
        guard let url, let host = url.host, host == "dexcom.com" || host.hasSuffix(".dexcom.com"),
              url.path.hasPrefix("/profile/") else { return nil }
        return accountID(in: url.path)
    }

    /// Finds a Dexcom account ID anywhere in pasted text (a bare ID, one without hyphens, or a whole web address).
    static func accountID(in text: String) -> String? {
        let hex = "[0-9a-fA-F]"
        let dashed = "\(hex){8}-\(hex){4}-\(hex){4}-\(hex){4}-\(hex){12}"
        if let r = text.range(of: dashed, options: .regularExpression) { return text[r].lowercased() }
        guard let r = text.range(of: "(?<![0-9a-fA-F])\(hex){32}(?![0-9a-fA-F])", options: .regularExpression) else { return nil }
        let s = Array(text[r].lowercased())
        return [0..<8, 8..<12, 12..<16, 16..<20, 20..<32].map { String(s[$0]) }.joined(separator: "-")
    }

    static func reading(from data: Data) throws -> Reading? {
        guard let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw DexcomError.server("Unexpected reply from Dexcom.")
        }
        guard let row = rows.first else { return nil }
        guard let value = row["Value"] as? Int,
              let stamp = row["WT"] as? String,
              let date = date(fromDexcom: stamp) else {
            throw DexcomError.server("Unexpected reading format from Dexcom.")
        }
        let trend: Trend
        if let name = row["Trend"] as? String {
            trend = Trend(rawValue: name) ?? .none
        } else if let n = row["Trend"] as? Int, Trend.byNumber.indices.contains(n) {
            trend = Trend.byNumber[n]
        } else {
            trend = .none
        }
        return Reading(mgdl: value, trend: trend, date: date)
    }

    /// "Date(1691455258000-0400)": the number is UTC milliseconds; the offset is informational.
    static func date(fromDexcom s: String) -> Date? {
        guard let open = s.firstIndex(of: "(") else { return nil }
        let digits = s[s.index(after: open)...].prefix { $0.isNumber }
        guard let ms = Double(digits) else { return nil }
        return Date(timeIntervalSince1970: ms / 1000)
    }

    static func error(from data: Data, status: Int) -> DexcomError {
        let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let code = body?["Code"] as? String ?? ""
        if code.hasPrefix("Session") { return .sessionExpired }
        if code.contains("MaxAttempts") { return .lockedOut }
        if code.contains("PasswordInvalid") || code == "InvalidArgument" || code.contains("AccountNotFound") {
            return .badCredentials
        }
        return .server(body?["Message"] as? String ?? "Dexcom returned an error (HTTP \(status)).")
    }
}

actor DexcomClient {
    private static let nullID = "00000000-0000-0000-0000-000000000000"
    private var sessionID: String?
    private let http = URLSession(configuration: .ephemeral)

    func reset() { sessionID = nil }

    func latestReading(username: String, password: String, region: DexcomRegion) async throws -> Reading? {
        if sessionID == nil { sessionID = try await login(username, password, region) }
        do {
            return try await fetchLatest(region)
        } catch DexcomError.sessionExpired {
            sessionID = try await login(username, password, region)
            return try await fetchLatest(region)
        }
    }

    private func login(_ username: String, _ password: String, _ region: DexcomRegion) async throws -> String {
        let accountID: String
        if let id = DexcomParser.accountID(in: username) {
            accountID = id  // user pasted their Account ID (or the page address containing it)
        } else {
            accountID = try await postString("General/AuthenticatePublisherAccount", region: region, body: [
                "accountName": username, "password": password, "applicationId": region.applicationID,
            ])
        }
        let session = try await postString("General/LoginPublisherAccountById", region: region, body: [
            "accountId": accountID, "password": password, "applicationId": region.applicationID,
        ])
        guard session != Self.nullID else { throw DexcomError.badCredentials }
        return session
    }

    private func fetchLatest(_ region: DexcomRegion) async throws -> Reading? {
        guard let sessionID else { throw DexcomError.sessionExpired }
        let data = try await post("Publisher/ReadPublisherLatestGlucoseValues", region: region, query: [
            URLQueryItem(name: "sessionId", value: sessionID),
            URLQueryItem(name: "minutes", value: "1440"),
            URLQueryItem(name: "maxCount", value: "1"),
        ], body: [:])
        return try DexcomParser.reading(from: data)
    }

    private func postString(_ path: String, region: DexcomRegion, body: [String: String]) async throws -> String {
        let data = try await post(path, region: region, query: [], body: body)
        guard let s = try JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed) as? String else {
            throw DexcomError.server("Unexpected reply from Dexcom.")
        }
        return s
    }

    private func post(_ path: String, region: DexcomRegion, query: [URLQueryItem], body: [String: String]) async throws -> Data {
        var parts = URLComponents(url: URL(string: path, relativeTo: region.baseURL)!.absoluteURL,
                                  resolvingAgainstBaseURL: false)!
        if !query.isEmpty { parts.queryItems = query }
        var request = URLRequest(url: parts.url!, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await http.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw DexcomParser.error(from: data, status: status) }
        return data
    }
}
