import AppKit

/// Matches the lighter, antialiased text in the graphite reference screenshot.
final class ReaderTextView: NSTextView {
    var usesReferenceRendering = false {
        didSet {
            if oldValue != usesReferenceRendering { needsDisplay = true }
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard usesReferenceRendering, let context = NSGraphicsContext.current?.cgContext else {
            super.draw(dirtyRect)
            return
        }

        context.saveGState()
        defer { context.restoreGState() }
        // Keep antialiasing, but avoid the extra stroke weight of font smoothing.
        // Scope the setting to this text view; do not change system preferences.
        context.setShouldAntialias(true)
        context.setShouldSmoothFonts(false)
        super.draw(dirtyRect)
    }
}
