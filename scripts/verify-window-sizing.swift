import AppKit
import SwiftUI

private struct CheckRoot: View {
    @ObservedObject var model: ReaderModel

    var body: some View {
        ContentView().environmentObject(model)
            .frame(minWidth: model.minimumWindowSize.width,
                   minHeight: model.minimumWindowSize.height)
    }
}

@main
struct WindowSizingCheck {
    @MainActor
    static func main() throws {
        _ = NSApplication.shared
        // Keep this check independent of the user's book and saved preferences.
        UserDefaults.standard.setVolatileDomain([
            "readerTheme": ReaderTheme.graphite.rawValue,
            "graphiteFontSize": 20.0,
            "lastFilePath": ""
        ], forName: UserDefaults.argumentDomain)

        for theme in ReaderTheme.allCases {
            for size in [10.0, 18, 20, 24, 32, 48] {
                let font = theme.readingFont(at: size)
                let minimum = ReaderWindowMetrics.minimumSize(font: font)
                let storage = NSTextStorage(string: "一二三四五六七八九十", attributes: [.font: font])
                let manager = NSLayoutManager()
                let container = NSTextContainer(containerSize: NSSize(width: minimum.width, height: 1000))
                container.lineFragmentPadding = 0
                manager.addTextContainer(container)
                storage.addLayoutManager(manager)
                manager.ensureLayout(for: container)
                var firstLine = NSRange()
                _ = manager.lineFragmentRect(forGlyphAt: 0, effectiveRange: &firstLine)
                let characters = manager.characterRange(forGlyphRange: firstLine, actualGlyphRange: nil)
                precondition(characters.length == 6, "Expected six characters for \(theme) at \(size), got \(characters.length)")
                precondition(minimum.height == 44)
                print("PASS \(theme) \(Int(size)) pt: width \(Int(minimum.width)), six characters per line")
            }
        }

        let model = ReaderModel()
        model.text = "一二三四五六七八九十\n窗口可以缩小到六个汉字的宽度。"
        let minimum = model.minimumWindowSize
        let host = NSHostingView(rootView: CheckRoot(model: model))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 300),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        settle(host)
        window.setContentSize(NSSize(width: minimum.width, height: 180))
        settle(host)
        precondition(abs(host.bounds.width - minimum.width) < 1, "Controls must not widen the window: \(host.bounds)")
        precondition(abs(window.contentMinSize.width - minimum.width) < 1)
        try snapshot(host, name: "StealthReader-six-characters-controls.png")

        guard let tracking = find(TrackingNSView.self, in: host) else { fatalError("Missing hover tracking") }
        let menu = NSMenu()
        // The compact palette submenu must not disappear when the pointer leaves the reader.
        NotificationCenter.default.post(name: NSMenu.didBeginTrackingNotification, object: menu)
        NotificationCenter.default.post(name: NSMenu.didBeginTrackingNotification, object: menu)
        settle(host)
        tracking.onExit?()
        settle(host)
        precondition(window.styleMask.contains(.titled), "An open menu must freeze chrome visibility")
        NotificationCenter.default.post(name: NSMenu.didEndTrackingNotification, object: menu)
        settle(host)
        tracking.onExit?()
        settle(host)
        precondition(window.styleMask.contains(.titled), "Closing a submenu must not unlock the parent menu")
        NotificationCenter.default.post(name: NSMenu.didEndTrackingNotification, object: menu)
        settle(host)
        tracking.onExit?()
        settle(host)
        window.setContentSize(minimum)
        settle(host)
        precondition(window.styleMask.contains(.resizable), "Hidden window must remain resizable")
        precondition(!window.styleMask.contains(.titled), "Hidden window must have no title bar")
        precondition(abs(window.frame.width - minimum.width) < 1)
        precondition(abs(host.bounds.height - minimum.height) < 1)
        try snapshot(host, name: "StealthReader-six-characters-hidden.png")

        tracking.onMove?(CGPoint(x: 10, y: minimum.height - 2), minimum)
        settle(host)
        try snapshot(host, name: "StealthReader-six-characters-one-line-controls.png")
        tracking.onExit?()
        settle(host)

        // Changing the font must update the constraints on an already-attached window.
        let larger = ReaderWindowMetrics.minimumSize(font: ReaderTheme.graphite.readingFont(at: 32))
        model.fontSize = 32
        settle(host)
        precondition(window.contentMinSize.width == larger.width)
        precondition(window.frame.width >= larger.width)
        WindowChromeController.shared.setHidden(false)
        precondition(window.contentMinSize.width == larger.width)
        WindowChromeController.shared.setHidden(true)
        precondition(window.contentMinSize.width == larger.width)
        model.fontSize = 10
        settle(host)
        window.setContentSize(model.minimumWindowSize)
        settle(host)
        precondition(abs(host.bounds.width - 61) < 1, "Smallest font must allow a 61 pt window")
        model.isLoading = true
        settle(host)
        precondition(abs(host.bounds.width - 61) < 1, "Loading indicator must not widen the window")
        print("PASS: hosted controls, one-line hidden window, updated font limits, and both chrome modes")
    }

    @MainActor
    static func settle(_ view: NSView) {
        for _ in 0..<4 {
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
            view.layoutSubtreeIfNeeded()
        }
    }

    @MainActor
    static func find<T: NSView>(_ type: T.Type, in view: NSView) -> T? {
        if let result = view as? T { return result }
        return view.subviews.lazy.compactMap { find(type, in: $0) }.first
    }

    @MainActor
    static func snapshot(_ view: NSView, name: String) throws {
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try bitmap.representation(using: .png, properties: [:])!.write(to: path)
        print("Snapshot: \(path.path)")
    }
}
