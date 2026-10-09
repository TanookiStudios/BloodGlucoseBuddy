import XCTest

final class CoreTests: XCTestCase {
    func testParsesShareReading() throws {
        let json = #"[{"WT":"Date(1691455258000)","ST":"Date(1691455258000)","DT":"Date(1691455258000-0400)","Value":123,"Trend":"FortyFiveUp"}]"#
        let r = try XCTUnwrap(DexcomParser.reading(from: Data(json.utf8)))
        XCTAssertEqual(r.mgdl, 123)
        XCTAssertEqual(r.trend, .fortyFiveUp)
        XCTAssertEqual(r.date.timeIntervalSince1970, 1691455258, accuracy: 0.001)
    }

    func testParsesNumericTrend() throws {
        let json = #"[{"WT":"Date(1691455258000)","Value":99,"Trend":4}]"#
        XCTAssertEqual(try DexcomParser.reading(from: Data(json.utf8))?.trend, .flat)
    }

    func testEmptyReplyMeansNoReading() throws {
        XCTAssertNil(try DexcomParser.reading(from: Data("[]".utf8)))
    }

    func testErrorCodes() {
        func code(_ c: String) -> DexcomError {
            DexcomParser.error(from: Data(#"{"Code":"\#(c)","Message":"x"}"#.utf8), status: 500)
        }
        XCTAssertEqual(code("AccountPasswordInvalid"), .badCredentials)
        XCTAssertEqual(code("SSO_AuthenticateMaxAttemptsExceeded"), .lockedOut)
        XCTAssertEqual(code("SessionIdNotFound"), .sessionExpired)
        XCTAssertEqual(code("SomethingElse"), .server("x"))
    }

    func testFindsAccountIDInPastedText() {
        let id = "12345678-90ab-cdef-1234-567890abcdef"
        XCTAssertEqual(DexcomParser.accountID(in: id), id)
        XCTAssertEqual(DexcomParser.accountID(in: "1234567890ABCDEF1234567890abcdef"), id)
        XCTAssertEqual(DexcomParser.accountID(in: "https://uam1.dexcom.com/account/\(id)/profile"), id)
        XCTAssertNil(DexcomParser.accountID(in: "maddie@example.com"))
        XCTAssertNil(DexcomParser.accountID(in: "+15551234567"))
    }

    func testAccountIDOnlyFromProfilePage() {
        let profile = URL(string: "https://myaccount.dexcom.com/profile/12345678-90ab-cdef-1234-567890abcdef")
        XCTAssertEqual(DexcomParser.accountID(fromProfileURL: profile), "12345678-90ab-cdef-1234-567890abcdef")
        // The sign-in page carries the website's own client ID; that must not be taken as the account ID.
        let signIn = URL(string: "https://signup.dexcom.com/connect/authorize?client_id=0b72c581-2e98-4644-989c-52c76e34842b&redirect_uri=https://myaccount.dexcom.com/profile")
        XCTAssertNil(DexcomParser.accountID(fromProfileURL: signIn))
        XCTAssertNil(DexcomParser.accountID(fromProfileURL: URL(string: "https://evil-dexcom.com/profile/12345678-90ab-cdef-1234-567890abcdef")))
    }

    func testDiscordFrame() {
        let frame = DiscordIPC.frame(opcode: 1, payload: Data("{}".utf8))
        XCTAssertEqual([UInt8](frame), [1, 0, 0, 0, 2, 0, 0, 0, 123, 125])
    }

    func testNumberModeActivity() {
        let now = Date()
        let r = Reading(mgdl: 123, trend: .fortyFiveUp, date: now.addingTimeInterval(-120))
        let a = Presence.activity(reading: r, now: now, mode: .number, unit: .mgdl, verb: .watching, low: 70, high: 180)
        XCTAssertEqual(a["type"] as? Int, 3)
        XCTAssertEqual(a["details"] as? String, "123 mg/dL ↗")
        XCTAssertEqual(a["state"] as? String, "Rising slowly")
        XCTAssertEqual((a["assets"] as? [String: String])?["large_image"], "v2_up_45")
    }

    func testDotModeNeverShowsTheNumber() {
        let now = Date()
        let r = Reading(mgdl: 250, trend: .singleUp, date: now)
        let a = Presence.activity(reading: r, now: now, mode: .dot, unit: .mgdl, verb: .playing, low: 70, high: 180)
        XCTAssertEqual(a["type"] as? Int, 0)
        XCTAssertEqual(a["details"] as? String, "High")
        XCTAssertEqual((a["assets"] as? [String: String])?["large_image"], "v2_dot_yellow")
        XCTAssertFalse(String(describing: a).contains("250"))
        XCTAssertNil(a["state"])
    }

    func testStaleReadingShowsNoReading() {
        let now = Date()
        let r = Reading(mgdl: 110, trend: .flat, date: now.addingTimeInterval(-16 * 60))
        let a = Presence.activity(reading: r, now: now, mode: .number, unit: .mgdl, verb: .watching, low: 70, high: 180)
        XCTAssertEqual(a["details"] as? String, "No reading")
        XCTAssertNil(a["timestamps"])
    }

    func testFormatting() {
        XCTAssertEqual(Presence.format(180, .mmol), "10.0 mmol/L")
        XCTAssertEqual(Presence.format(39, .mgdl), "LOW")
        XCTAssertEqual(Presence.format(401, .mmol), "HIGH")
        XCTAssertEqual(Presence.band(69, low: 70, high: 180), .low)
        XCTAssertEqual(Presence.band(181, low: 70, high: 180), .high)
    }
}
