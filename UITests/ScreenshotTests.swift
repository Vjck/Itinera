import XCTest

/// Walks through the main screens with demo data, saves a screenshot of each
/// and runs Apple's accessibility audit (clipped text, contrast, small touch targets).
final class ScreenshotTests: XCTestCase {
    private var app: XCUIApplication!
    private var auditLines: [String] = []

    override func setUpWithError() throws {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments = ["-uiTestDemo", "-AppleLanguages", "(it)", "-AppleLocale", "it_IT"]
        addUIInterruptionMonitor(withDescription: "Permessi di sistema") { alert in
            for label in ["Consenti mentre usi l’app", "Consenti mentre usi l'app", "Allow While Using App", "OK"] {
                let button = alert.buttons[label]
                if button.exists {
                    button.tap()
                    return true
                }
            }
            return false
        }
        app.launch()
    }

    func testMainScreens() throws {
        let trip = app.staticTexts["Praga"].firstMatch
        XCTAssertTrue(trip.waitForExistence(timeout: 30), "L'elenco dei viaggi non mostra il viaggio demo")
        capture("01-Elenco-viaggi")

        trip.tap()
        let panes = app.segmentedControls.firstMatch
        XCTAssertTrue(panes.waitForExistence(timeout: 10), "La schermata del viaggio non si è aperta")
        capture("02-Giorni")
        sheet("03-Nuova-tappa")

        panes.buttons["Mappa"].tap()
        sleep(5) // map tiles
        capture("04-Mappa", audit: false)

        panes.buttons["Luoghi"].tap()
        capture("05-Luoghi")

        panes.buttons["Spese"].tap()
        capture("06-Spese")
        sheet("07-Nuova-spesa")

        panes.buttons["Cambio"].tap()
        sleep(2) // exchange rate download
        capture("08-Cambio")

        let report = XCTAttachment(string: auditLines.joined(separator: "\n"))
        report.name = "audit"
        report.lifetime = .keepAlways
        add(report)
    }

    /// Opens the "+" sheet of the current section, captures it and closes it.
    private func sheet(_ name: String) {
        let add = app.buttons["add"].firstMatch
        guard add.waitForExistence(timeout: 5) else {
            XCTFail("Pulsante + non trovato per \(name)")
            return
        }
        add.tap()
        let cancel = app.buttons["Annulla"].firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 5), "Il foglio \(name) non si è aperto")
        capture(name)
        if cancel.exists { cancel.tap() }
        sleep(1)
    }

    private func capture(_ name: String, audit: Bool = true) {
        sleep(1) // let animations settle
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
        guard audit else { return }
        do {
            try app.performAccessibilityAudit(for: [.textClipped, .contrast, .hitRegion]) { issue in
                self.auditLines.append("\(name) | \(Self.label(issue.auditType)) | \(issue.compactDescription) | \(issue.detailedDescription)")
                return true // recorded in the report, does not fail the test
            }
        } catch {
            auditLines.append("\(name) | errore | Audit non eseguito | \(error.localizedDescription)")
        }
    }

    private static func label(_ type: XCUIAccessibilityAuditType) -> String {
        if type == .textClipped { return "testo tagliato" }
        if type == .contrast { return "contrasto" }
        if type == .hitRegion { return "area di tocco piccola" }
        return "altro"
    }
}
