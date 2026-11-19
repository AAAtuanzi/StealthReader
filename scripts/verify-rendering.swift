import AppKit

@main
struct RenderingCheck {
    static func main() throws {
        _ = NSApplication.shared
        guard CommandLine.arguments.count == 2 else {
            fatalError("Pass a temporary output directory")
        }
        let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        var rendered: [Data] = []
        for reference in [false, true] {
            let view = ReaderTextView(frame: NSRect(x: 0, y: 0, width: 1100, height: 70))
            view.isEditable = false
            view.isRichText = false
            view.font = NSFont(name: "PingFangSC-Regular", size: 20)!
            view.backgroundColor = NSColor(srgbRed: 25 / 255, green: 29 / 255, blue: 36 / 255, alpha: 1)
            view.textColor = NSColor(srgbRed: 232 / 255, green: 234 / 255, blue: 239 / 255, alpha: 1)
            view.string = "文字显示测试：阅读字体应当清晰自然，保持常规字重，不要过亮。任务、边界与内容。"
            view.usesReferenceRendering = reference
            let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
            view.cacheDisplay(in: view.bounds, to: bitmap)
            let name = reference ? "reference-rendering.png" : "original-rendering.png"
            let data = bitmap.representation(using: .png, properties: [:])!
            rendered.append(data)
            try data.write(to: directory.appendingPathComponent(name))
            print("\(name): \(bitmap.pixelsWide)x\(bitmap.pixelsHigh), font=\(view.font!.fontName)")

            if reference {
                view.usesReferenceRendering = false
                let resetBitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
                view.cacheDisplay(in: view.bounds, to: resetBitmap)
                let resetData = resetBitmap.representation(using: .png, properties: [:])!
                precondition(resetData == rendered[0], "Switching back must preserve the original rendering")
            }
        }
        precondition(rendered[0] != rendered[1], "Reference rendering must change the drawn strokes")
        print("PASS: reference rendering differs; switching back restores the original exactly")
    }
}
