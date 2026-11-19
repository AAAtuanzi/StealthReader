import AppKit
import CoreText

@main
struct ThemeMenuCheck {
    @MainActor
    static func main() throws {
        _ = NSApplication.shared
        // This standalone test uses its own executable's defaults, never the app's domain.
        UserDefaults.standard.setVolatileDomain(["lastFilePath": ""], forName: UserDefaults.argumentDomain)
        precondition(ReaderTheme.allCases.map(\.rawValue) == [0, 2, 3, 4, 5, 6], "Persisted IDs must stay stable")
        for (savedValue, expected) in [(0, ReaderTheme.light), (1, .light), (2, .dark), (3, .deepSlate), (4, .graphite), (5, .indigo), (6, .mist)] {
            UserDefaults.standard.set(savedValue, forKey: "readerTheme")
            let restored = ReaderModel()
            precondition(restored.theme == expected)
            precondition(UserDefaults.standard.integer(forKey: "readerTheme") == expected.rawValue)
        }
        var cycled: [ReaderTheme] = []
        var current = ReaderTheme.light
        for _ in 0..<ReaderTheme.allCases.count {
            cycled.append(current)
            current = current.next
        }
        precondition(cycled == ReaderTheme.allCases && current == .light)
        print("PASS: removed theme migrates to white; other saved IDs and six-theme cycling are preserved")
        let indigo = ReaderTheme.indigo
        func rgb(_ color: NSColor) -> [Int] {
            let c = color.usingColorSpace(.sRGB)!
            return [c.redComponent, c.greenComponent, c.blueComponent].map { Int(($0 * 255).rounded()) }
        }
        precondition(rgb(indigo.backgroundColor) == [29, 31, 46] && rgb(indigo.textColor) == [230, 232, 239])
        let mist = ReaderTheme.mist
        precondition(rgb(mist.backgroundColor) == [247, 248, 251] && rgb(mist.textColor) == [23, 26, 38])
        for size in [10.0, 18, 24, 48] {
            precondition(mist.readingFont(at: size) == ReaderTheme.light.readingFont(at: size))
        }
        precondition(mist.fontSizeKey == ReaderTheme.light.fontSizeKey)
        precondition(mist.savedFontSize() == ReaderTheme.light.savedFontSize())
        precondition(mist.usesReferenceRendering == ReaderTheme.light.usesReferenceRendering)
        print("PASS: mist screenshot colors; standard font, saved size and rendering unchanged")
        let sample = "旅游人物lock=value012"
        let font = indigo.readingFont(at: 24)
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: sample, attributes: [.font: font]))
        let runs = CTLineGetGlyphRuns(line) as! [CTRun]
        var checked = 0
        for run in runs {
            let range = CTRunGetStringRange(run)
            let actual = (CTRunGetAttributes(run) as NSDictionary)[kCTFontAttributeName] as! CTFont
            let name = CTFontCopyPostScriptName(actual) as String
            for index in range.location..<(range.location + range.length) {
                precondition(name == (index < 4 ? "PingFangSC-Regular" : "Menlo-Regular"), "Unexpected face at \(index): \(name)")
                checked += 1
            }
        }
        precondition(checked == sample.utf16.count)
        let widths = ["i", "W", "1", "0"].map { ($0 as NSString).size(withAttributes: [.font: font]).width }
        precondition(widths.allSatisfy { abs($0 - widths[0]) < 0.01 })
        print("PASS: screenshot sRGB values, resolved PingFang SC + Menlo glyphs, equal Latin and digit widths")
        let model = ReaderModel()
        UserDefaults.standard.removeObject(forKey: indigo.fontSizeKey)
        model.theme = .graphite
        let graphiteSize = model.fontSize
        model.theme = .indigo
        precondition(model.fontSize == 24)
        model.changeFontSize(by: -2)
        model.theme = .graphite
        precondition(model.fontSize == graphiteSize)
        model.theme = .indigo
        precondition(ReaderModel().fontSize == 22)
        model.theme = .light
        let standardSize = model.fontSize
        model.theme = .mist
        precondition(model.fontSize == standardSize && ReaderModel().theme == .mist)
        model.theme = .light
        var selectionCount = 0
        let picker = ReaderThemeMenu(selectedTheme: model.theme) { theme in
            selectionCount += 1
            model.theme = theme
        }
        precondition(selectionCount == 0 && model.theme == .light,
                     "Constructing the menu must not cycle the theme")
        precondition(picker.menu.items.count == ReaderTheme.allCases.count)
        precondition(picker.menu.items.filter { $0.state == .on }.count == 1)

        for (index, theme) in ReaderTheme.allCases.enumerated() {
            let item = picker.menu.items[index]
            precondition(item.title == theme.displayName)
            precondition(item.tag == theme.rawValue)
            precondition(item.image != nil && item.image?.isTemplate == false)
            let preview = item.image!
            let bitmap = renderInSRGB(preview)
            let expected = theme.backgroundColor.usingColorSpace(.sRGB)!
            var pixel = [Int](repeating: 0, count: bitmap.samplesPerPixel)
            bitmap.getPixel(&pixel, atX: bitmap.pixelsWide / 2, y: 3)
            // These are already sRGB bytes; colorAt may label them as device RGB on older AppKit.
            let expectedBytes = [expected.redComponent, expected.greenComponent, expected.blueComponent]
                .map { Int(($0 * 255).rounded()) }
            precondition(zip(pixel.prefix(3), expectedBytes).allSatisfy { abs(Int($0.0) - $0.1) <= 2 },
                         "Preview mismatch: \(theme), got \(pixel), expected \(expectedBytes)")
            picker.menu.performActionForItem(at: index)
            precondition(model.theme == theme, "Each item must select its own theme directly")
            precondition(UserDefaults.standard.integer(forKey: "readerTheme") == theme.rawValue)
            precondition(item.state == .on && picker.menu.items.filter { $0.state == .on }.count == 1)
            print("PASS: \(theme.displayName), true-color preview, direct selection, checkmark and persistence")
        }
        let reopened = ReaderThemeMenu(selectedTheme: model.theme) { _ in }
        precondition(reopened.menu.item(withTag: model.theme.rawValue)?.state == .on)
        precondition(selectionCount == ReaderTheme.allCases.count)

        let previewHeight = CGFloat(ReaderTheme.allCases.count * 34 + 16)
        let previewSheet = NSImage(size: NSSize(width: 230, height: previewHeight), flipped: false) { rect in
            NSColor.windowBackgroundColor.setFill()
            NSBezierPath(rect: rect).fill()
            for (index, theme) in ReaderTheme.allCases.enumerated() {
                let y = rect.height - CGFloat(index + 1) * 34 - 2
                theme.menuPreview.draw(in: NSRect(x: 12, y: y, width: 76, height: 28))
                (theme.displayName as NSString).draw(at: NSPoint(x: 100, y: y + 5),
                    withAttributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.labelColor])
            }
            return true
        }
        let bitmap = renderInSRGB(previewSheet)
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("StealthReader-theme-menu-preview.png")
        try bitmap.representation(using: .png, properties: [:])!.write(to: output)
        print("Preview sheet: \(output.path)")
        print("PASS: opening/reopening does not change selection")
    }

    @MainActor
    static func renderInSRGB(_ image: NSImage) -> NSBitmapImageRep {
        // Render in an explicit color space; TIFF's default cache can be untagged device RGB.
        let context = CGContext(data: nil, width: Int(image.size.width * 2), height: Int(image.size.height * 2),
                                bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.scaleBy(x: 2, y: 2)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        image.draw(in: NSRect(origin: .zero, size: image.size))
        NSGraphicsContext.restoreGraphicsState()
        return NSBitmapImageRep(cgImage: context.makeImage()!)
    }
}
