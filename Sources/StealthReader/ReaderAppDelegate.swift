import AppKit

@MainActor
final class ReaderAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        hideApplicationNameAfterUpdate()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        hideApplicationNameAfterUpdate()
    }

    private func hideApplicationNameAfterUpdate() {
        // SwiftUI installs its menu during launch/activation; apply after that update.
        DispatchQueue.main.async {
            Self.hideApplicationName(in: NSApp.mainMenu)
        }
    }

    static func hideApplicationName(in mainMenu: NSMenu?) {
        // Identify the app menu by its standard Quit action, never by index or locale.
        guard let item = mainMenu?.items.first(where: { topLevel in
            topLevel.submenu?.items.contains(where: {
                $0.action == #selector(NSApplication.terminate(_:))
            }) == true
        }) else { return }

        // Keep the application-menu slot: hiding it makes macOS relabel File as
        // the app menu. Only make its label blank, keeping all commands intact.
        let blank = "\u{200B}"
        item.title = blank
        item.attributedTitle = NSAttributedString(string: blank)
        item.submenu?.title = blank
    }
}
