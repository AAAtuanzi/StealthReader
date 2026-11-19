import AppKit

enum ReaderWindowMetrics {
    static let minimumHeight: CGFloat = 44

    static func minimumSize(font: NSFont) -> NSSize {
        // Match the actual CJK glyph width, with one point for layout rounding.
        let width = ("汉字阅读测试" as NSString).size(withAttributes: [.font: font]).width
        return NSSize(width: ceil(width) + 1, height: minimumHeight)
    }
}
