import AppKit
import SwiftUI

@MainActor
final class WindowChromeController {
    static let shared = WindowChromeController()

    weak var window: NSWindow?
    var suspendAutoHide = false
    private var isHidden = false
    private var minimumContentSize = NSSize(width: 61, height: ReaderWindowMetrics.minimumHeight)

    private init() {}

    func attach(_ window: NSWindow, minimumContentSize: NSSize) {
        if self.window !== window {
            self.window = window
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .visible
            window.isMovableByWindowBackground = false
            isHidden = !window.styleMask.contains(.titled)
        }
        self.minimumContentSize = minimumContentSize
        applyMinimumSize(to: window)
    }

    private func applyMinimumSize(to window: NSWindow) {
        if window.contentMinSize != minimumContentSize {
            window.contentMinSize = minimumContentSize
        }
        let minimumFrame = window.frameRect(forContentRect:
            NSRect(origin: .zero, size: minimumContentSize)).size
        var frame = window.frame
        let newHeight = max(frame.height, minimumFrame.height)
        frame.origin.y -= newHeight - frame.height
        frame.size = NSSize(width: max(frame.width, minimumFrame.width), height: newHeight)
        if frame != window.frame { window.setFrame(frame, display: true) }
    }

    func setHidden(_ hidden: Bool) {
        guard hidden != isHidden, let window else { return }
        isHidden = hidden

        let frame = window.frame
        if hidden {
            // Keep resize hit-testing even while all visible chrome is gone.
            window.styleMask = [.borderless, .resizable]
            window.hasShadow = false
            window.isMovable = false
        } else {
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .visible
            window.hasShadow = true
            window.isMovable = true
        }
        window.setFrame(frame, display: true)
        // A style-mask change can reset AppKit's constraints; keep both modes in sync.
        applyMinimumSize(to: window)
    }
}

struct WindowReader: NSViewRepresentable {
    let onResolve: @MainActor (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { [weak view] in
            if let window = view?.window { onResolve(window) }
        }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async { [weak view] in
            if let window = view?.window { onResolve(window) }
        }
    }
}

struct MouseTrackingView: NSViewRepresentable {
    let onMove: @MainActor (CGPoint, CGSize) -> Void
    let onExit: @MainActor () -> Void

    func makeNSView(context: Context) -> TrackingNSView {
        let view = TrackingNSView()
        view.onMove = onMove
        view.onExit = onExit
        return view
    }

    func updateNSView(_ view: TrackingNSView, context: Context) {
        view.onMove = onMove
        view.onExit = onExit
    }
}

final class TrackingNSView: NSView {
    var onMove: (@MainActor (CGPoint, CGSize) -> Void)?
    var onExit: (@MainActor () -> Void)?
    private var trackingAreaReference: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaReference { removeTrackingArea(trackingAreaReference) }

        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingAreaReference = area
    }

    override func mouseEntered(with event: NSEvent) {
        reportPosition(event)
    }

    override func mouseMoved(with event: NSEvent) {
        reportPosition(event)
    }

    override func mouseExited(with event: NSEvent) {
        Task { @MainActor in onExit?() }
    }

    private func reportPosition(_ event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let size = bounds.size
        Task { @MainActor in onMove?(point, size) }
    }
}
