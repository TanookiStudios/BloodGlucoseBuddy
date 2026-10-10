import AppKit
import XCTest

/// Drives the real app in demo mode (BGB_DEMO=1: fabricated readings, throwaway settings, no Keychain,
/// no Dexcom, no Discord) and saves each screen as a test attachment. scripts/capture-screenshots-mac.sh
/// runs this and turns the attachments into docs/screenshots/mac/<name>.png.
final class ScreenshotTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(signedIn: Bool, mgdl: Int = 112, trend: String = "FortyFiveUp",
                        mode: String = "number", unit: String = "mgdl") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment = [
            "BGB_DEMO": "1", "BGB_DEMO_SIGNED_IN": signedIn ? "1" : "0",
            "BGB_DEMO_MGDL": "\(mgdl)", "BGB_DEMO_TREND": trend, "BGB_DEMO_MODE": mode, "BGB_DEMO_UNIT": unit,
        ]
        app.launch()
        return app
    }

    /// Fails the run when the screen isn't there: a half-captured set that looks fine is how stale screenshots ship.
    private func capture(_ element: XCUIElement, _ name: String) {
        XCTAssertTrue(element.waitForExistence(timeout: 15), "\(name): nothing on screen to capture")
        let shot = XCTAttachment(screenshot: element.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// The menu with its open submenu, cropped from the whole screen: neither element alone shows both.
    private func captureWithSubmenu(_ menu: XCUIElement, _ entry: XCUIElement, _ name: String) {
        let submenu = entry.menus.firstMatch
        let deadline = Date().addingTimeInterval(10)
        while submenu.frame.isEmpty && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.25)) }
        XCTAssertFalse(submenu.frame.isEmpty, "\(name): submenu never opened")
        let area = menu.frame.union(submenu.frame)
        let screen = XCUIScreen.main.screenshot().image
        guard let full = screen.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return XCTFail("\(name): no screen image") }
        let scale = CGFloat(full.width) / screen.size.width
        let crop = CGRect(x: area.minX * scale, y: area.minY * scale, width: area.width * scale, height: area.height * scale)
        guard let cut = full.cropping(to: crop),
              let ctx = CGContext(data: nil, width: cut.width, height: cut.height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return XCTFail("\(name): crop outside the screen") }
        // Keep only the two menus' own pixels, so nothing of the desktop behind them ends up in the picture.
        for f in [menu.frame, submenu.frame] {
            let r = CGRect(x: (f.minX - area.minX) * scale, y: (area.maxY - f.maxY) * scale, width: f.width * scale, height: f.height * scale)
            ctx.addPath(CGPath(roundedRect: r.insetBy(dx: scale, dy: scale), cornerWidth: 9 * scale, cornerHeight: 9 * scale, transform: nil))
        }
        ctx.clip()
        ctx.draw(cut, in: CGRect(x: 0, y: 0, width: cut.width, height: cut.height))
        guard let masked = ctx.makeImage() else { return XCTFail("\(name): couldn't mask") }
        let shot = XCTAttachment(image: NSImage(cgImage: masked, size: area.size))
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// The open menu that shows `item`. app.menus also holds closed menus with empty frames, which can't be captured.
    private func openMenu(_ app: XCUIApplication, showing item: String) -> XCUIElement {
        let deadline = Date().addingTimeInterval(10)
        repeat {
            if let m = app.menus.allElementsBoundByIndex.first(where: { !$0.frame.isEmpty && $0.menuItems[item].exists }) { return m }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        } while Date() < deadline
        XCTFail("no open menu showing \(item)")
        return app.menus.firstMatch
    }

    private func settingsWindow(_ app: XCUIApplication) -> XCUIElement {
        app.windows.matching(identifier: "settings").firstMatch.exists
            ? app.windows.matching(identifier: "settings").firstMatch
            : app.windows["Blood Glucose Buddy"]
    }

    func test1SignInFlow() {
        let app = launch(signedIn: false)
        defer { app.terminate() }
        let window = settingsWindow(app)
        capture(window, "01-sign-in")

        let user = window.textFields["username"]
        XCTAssertTrue(user.waitForExistence(timeout: 10))
        user.click()
        user.typeText("you@example.com")
        let password = window.secureTextFields["password"]
        password.click()
        password.typeText("not-a-real-password")
        capture(window, "02-sign-in-filled")

        window.buttons["signIn"].click()
        XCTAssertTrue(window.descendants(matching: .any)["signedInAs"].waitForExistence(timeout: 15), "sign-in never finished")
        capture(window, "03-settings-signed-in")

        let discord = window.descendants(matching: .any)["discordOn"]
        XCTAssertTrue(discord.waitForExistence(timeout: 5), "Discord switch missing from settings")
        discord.click()
        XCTAssertTrue(window.staticTexts["Discord: showing your status"].waitForExistence(timeout: 5), "Discord options never appeared")
        capture(window, "08-settings-discord")
    }

    func test2MenuBarAndMenu() {
        let app = launch(signedIn: true)
        defer { app.terminate() }
        let item = app.statusItems.firstMatch
        capture(item, "04-menu-bar")
        item.click()
        let menu = openMenu(app, showing: "Quit Blood Glucose Buddy")
        capture(menu, "05-menu")
        for (title, name) in [("Units", "06-menu-units"), ("Discord", "07-menu-discord")] {
            let entry = menu.menuItems[title]
            XCTAssertTrue(entry.waitForExistence(timeout: 5), "\(title) missing from the menu")
            entry.hover()
            captureWithSubmenu(menu, entry, name)
        }
        app.typeKey(.escape, modifierFlags: [])
    }

    func test4AboutMaddie() {
        let app = launch(signedIn: true)
        defer { app.terminate() }
        let item = app.statusItems.firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 15), "menu bar item never appeared")
        item.click()
        let about = openMenu(app, showing: "Quit Blood Glucose Buddy").menuItems["About Maddie…"]  // menu items ignore accessibility identifiers
        XCTAssertTrue(about.waitForExistence(timeout: 5), "About Maddie missing from the menu")
        about.click()
        capture(app.windows["About Maddie"], "12-about-maddie")
    }

    func test3MenuBarVariety() {
        for (mgdl, trend, unit, name) in [(64, "SingleDown", "mgdl", "09-menu-bar-low"),
                                          (245, "DoubleUp", "mgdl", "10-menu-bar-high"),
                                          (112, "Flat", "mmol", "11-menu-bar-mmol")] {
            let app = launch(signedIn: true, mgdl: mgdl, trend: trend, unit: unit)
            capture(app.statusItems.firstMatch, name)
            app.terminate()
        }
    }
}
