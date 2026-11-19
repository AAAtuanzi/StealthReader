import AppKit
import SwiftUI

/// NSTextView handles novel-sized documents much more efficiently than one giant SwiftUI Text.
struct LongTextView: NSViewRepresentable {
    let text: String
    let revision: Int
    let fontSize: Double
    let theme: ReaderTheme
    let chromeIsHidden: Bool
    let restoreLocation: Int?
    let onPositionChange: (Int) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = true
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let textView = ReaderTextView(frame: .zero)
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.usesFindPanel = true
        textView.usesFindBar = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.containerSize = NSSize(
            width: 0,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.string = text
        context.coordinator.loadedRevision = revision
        scrollView.documentView = textView
        context.coordinator.attach(
            textView: textView,
            scrollView: scrollView,
            onPositionChange: onPositionChange
        )
        configure(scrollView, textView: textView, coordinator: context.coordinator)
        if revision > 0 {
            context.coordinator.prepareForDocumentChange()
            context.coordinator.restorePosition(restoreLocation ?? 0)
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }

        context.coordinator.onPositionChange = onPositionChange
        var locationToRestore: Int?
        if context.coordinator.loadedRevision != revision {
            context.coordinator.prepareForDocumentChange()
            textView.string = text
            context.coordinator.loadedRevision = revision
            context.coordinator.lastTheme = nil
            context.coordinator.lastFontSize = -1
            locationToRestore = restoreLocation ?? 0
        }
        configure(scrollView, textView: textView, coordinator: context.coordinator)
        if let locationToRestore {
            context.coordinator.restorePosition(locationToRestore)
        }
    }

    private func configure(
        _ scrollView: NSScrollView,
        textView: NSTextView,
        coordinator: Coordinator
    ) {
        let background = theme.backgroundColor
        let foreground = theme.textColor

        let themeChanged = coordinator.lastTheme != theme
        if themeChanged {
            scrollView.backgroundColor = background
            textView.backgroundColor = background
            textView.textColor = foreground
            (textView as? ReaderTextView)?.usesReferenceRendering = theme.usesReferenceRendering
            coordinator.lastTheme = theme
        }

        if coordinator.lastFontSize != fontSize || themeChanged {
            textView.font = theme.readingFont(at: fontSize)

            let paragraph = NSMutableParagraphStyle()
            // The reference has approximately 33 pt between lines at a 20 pt font.
            paragraph.lineSpacing = fontSize * (theme.usesReferenceRendering ? 0.25 : 0.45)
            textView.defaultParagraphStyle = paragraph
            if let storage = textView.textStorage, storage.length > 0 {
                storage.addAttribute(.paragraphStyle, value: paragraph,
                                     range: NSRange(location: 0, length: storage.length))
            }
            coordinator.lastFontSize = fontSize
        }

        if coordinator.lastChromeIsHidden != chromeIsHidden {
            scrollView.hasVerticalScroller = !chromeIsHidden
            textView.textContainerInset = NSSize(
                width: 0,
                height: chromeIsHidden ? 4 : 64
            )
            coordinator.lastChromeIsHidden = chromeIsHidden
        }
    }

    final class Coordinator {
        var loadedRevision = -1
        var lastFontSize = -1.0
        var lastTheme: ReaderTheme?
        var lastChromeIsHidden: Bool?
        var onPositionChange: ((Int) -> Void)?

        private weak var textView: NSTextView?
        private var searchObserver: NSObjectProtocol?
        private var scrollObserver: NSObjectProtocol?
        private var pendingPositionSave: DispatchWorkItem?
        private var isRestoringPosition = false

        func attach(
            textView: NSTextView,
            scrollView: NSScrollView,
            onPositionChange: @escaping (Int) -> Void
        ) {
            self.textView = textView
            self.onPositionChange = onPositionChange

            scrollView.contentView.postsBoundsChangedNotifications = true
            scrollObserver = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: scrollView.contentView,
                queue: .main
            ) { [weak self] _ in
                self?.schedulePositionSave()
            }

            searchObserver = NotificationCenter.default.addObserver(
                forName: .stealthReaderShowSearch,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.showSearch()
            }
        }

        func prepareForDocumentChange() {
            pendingPositionSave?.cancel()
            isRestoringPosition = true
        }

        func restorePosition(_ requestedLocation: Int) {
            guard let textView else { return }
            let maximum = max(0, (textView.string as NSString).length - 1)
            let location = min(max(0, requestedLocation), maximum)

            DispatchQueue.main.async { [weak self, weak textView] in
                guard let self, let textView else { return }
                textView.scrollRangeToVisible(NSRange(location: location, length: 0))
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                    self?.isRestoringPosition = false
                }
            }
        }

        private func showSearch() {
            guard let textView else { return }
            textView.window?.makeFirstResponder(textView)
            let sender = NSMenuItem()
            sender.tag = NSTextFinder.Action.showFindInterface.rawValue
            textView.performTextFinderAction(sender)
        }

        private func schedulePositionSave() {
            guard !isRestoringPosition, let textView else { return }
            pendingPositionSave?.cancel()

            let work = DispatchWorkItem { [weak self, weak textView] in
                guard let self, let textView, !self.isRestoringPosition else { return }
                let visibleTop = NSPoint(
                    x: textView.visibleRect.minX + 1,
                    y: textView.visibleRect.minY + 1
                )
                self.onPositionChange?(textView.characterIndexForInsertion(at: visibleTop))
            }
            pendingPositionSave = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
        }

        deinit {
            pendingPositionSave?.cancel()
            if let searchObserver {
                NotificationCenter.default.removeObserver(searchObserver)
            }
            if let scrollObserver {
                NotificationCenter.default.removeObserver(scrollObserver)
            }
        }
    }
}

extension Notification.Name {
    static let stealthReaderShowSearch = Notification.Name("StealthReader.showSearch")
}
