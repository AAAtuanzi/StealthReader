import AppKit
import SwiftUI

extension ReaderTheme {
    var displayName: String {
        switch self {
        case .light: "白色"
        case .dark: "深灰"
        case .deepSlate: "深蓝灰"
        case .graphite: "石墨灰"
        case .indigo: "深靛灰"
        case .mist: "浅雾白"
        }
    }

    /// A native menu image showing both actual theme colors, not a tinted symbol.
    var menuPreview: NSImage {
        let size = NSSize(width: 76, height: 28)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: 152, height: 56, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return NSImage(size: size)
        }
        // An explicitly tagged Retina bitmap avoids the device-RGB cache changing dark swatches.
        context.scaleBy(x: 2, y: 2)
        let rect = CGRect(origin: .zero, size: size)
        context.setFillColor(backgroundColor.usingColorSpace(.sRGB)!.cgColor)
        context.addPath(CGPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5),
                              cornerWidth: 5, cornerHeight: 5, transform: nil))
        context.fillPath()
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: self == .indigo ? readingFont(at: 13) : NSFont.systemFont(ofSize: 13),
            .foregroundColor: textColor
        ]
        let label = "文字 Aa" as NSString
        let labelSize = label.size(withAttributes: attributes)
        label.draw(at: NSPoint(x: (size.width - labelSize.width) / 2,
                               y: (size.height - labelSize.height) / 2), withAttributes: attributes)
        NSGraphicsContext.restoreGraphicsState()
        guard let bitmap = context.makeImage() else { return NSImage(size: size) }
        let image = NSImage(cgImage: bitmap, size: size)
        image.isTemplate = false
        return image
    }
}

@MainActor
final class ReaderThemeMenu: NSObject {
    let menu = NSMenu(title: "阅读配色")
    private let onSelect: (ReaderTheme) -> Void

    init(selectedTheme: ReaderTheme, onSelect: @escaping (ReaderTheme) -> Void) {
        self.onSelect = onSelect
        super.init()
        for theme in ReaderTheme.allCases {
            let item = NSMenuItem(title: theme.displayName, action: #selector(selectTheme(_:)), keyEquivalent: "")
            item.target = self
            item.tag = theme.rawValue
            item.image = theme.menuPreview
            item.state = theme == selectedTheme ? .on : .off
            menu.addItem(item)
        }
    }

    @objc private func selectTheme(_ item: NSMenuItem) {
        guard let theme = ReaderTheme(rawValue: item.tag) else { return }
        for option in menu.items { option.state = option.tag == item.tag ? .on : .off }
        onSelect(theme)
    }
}

/// Native menus handle outside clicks, Escape and keyboard navigation themselves.
struct ThemeMenuButton: NSViewRepresentable {
    let selectedTheme: ReaderTheme
    let onSelect: (ReaderTheme) -> Void
    let onClose: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton()
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.image = NSImage(systemSymbolName: "circle.lefthalf.filled", accessibilityDescription: "选择阅读配色")
        button.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)
        button.target = context.coordinator
        button.action = #selector(Coordinator.showMenu(_:))
        button.toolTip = "选择阅读配色（预览底色和文字颜色）"
        button.setAccessibilityLabel("选择阅读配色")
        button.setAccessibilityIdentifier("reader.themePicker")
        button.contentTintColor = selectedTheme.textColor
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.parent = self
        button.contentTintColor = selectedTheme.textColor
    }

    @MainActor
    final class Coordinator: NSObject {
        var parent: ThemeMenuButton

        init(_ parent: ThemeMenuButton) { self.parent = parent }

        @objc func showMenu(_ button: NSButton) {
            let controller = WindowChromeController.shared
            let wasSuspended = controller.suspendAutoHide
            controller.suspendAutoHide = true
            defer {
                controller.suspendAutoHide = wasSuspended
                parent.onClose()
            }
            let picker = ReaderThemeMenu(selectedTheme: parent.selectedTheme, onSelect: parent.onSelect)
            let point = NSPoint(x: button.bounds.minX,
                                y: button.isFlipped ? button.bounds.maxY + 4 : button.bounds.minY - 4)
            // popUp is synchronous: keep the action target and hover lock alive until dismissal.
            withExtendedLifetime(picker) {
                _ = picker.menu.popUp(positioning: nil, at: point, in: button)
            }
        }
    }
}
