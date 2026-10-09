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
    }

    func test2MenuBarAndMenu() {
        let app = launch(signedIn: true)
        defer { app.terminate() }
        let item = app.statusItems.firstMatch
        capture(item, "04-menu-bar")
        item.click()
        let menu = app.menus.firstMatch
        capture(menu, "05-menu")
        for (title, name) in [("Show on Discord", "06-menu-show-on-discord"), ("Units", "07-menu-units"), ("Status Word", "08-menu-status-word")] {
            let entry = menu.menuItems[title]
            XCTAssertTrue(entry.waitForExistence(timeout: 5), "\(title) missing from the menu")
            entry.hover()
            let submenu = entry.menus.firstMatch
            capture(submenu.exists ? submenu : app.menus.element(boundBy: 1), name)
        }
        app.typeKey(.escape, modifierFlags: [])
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
