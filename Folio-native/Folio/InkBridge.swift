import UIKit
import PencilKit
import FolioCore

extension UIColor {
    convenience init(argb: Double) {
        let bounded = argb.isFinite && (-2_147_483_648...4_294_967_295).contains(argb) ? argb : -14340028
        let bits = UInt32(truncatingIfNeeded: Int64(bounded))
        self.init(red: CGFloat((bits >> 16) & 255) / 255, green: CGFloat((bits >> 8) & 255) / 255,
                  blue: CGFloat(bits & 255) / 255, alpha: CGFloat(bits >> 24) / 255)
    }
    var argb: Double {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 1
        getRed(&r, green: &g, blue: &b, alpha: &a)
        func channel(_ value: CGFloat) -> UInt32 { value.isFinite ? UInt32((min(1, max(0, value)) * 255).rounded()) : 0 }
        let bits = channel(a) << 24 | channel(r) << 16 | channel(g) << 8 | channel(b)
        return Double(Int32(bitPattern: bits))
    }
}

enum InkBridge {
    static func drawing(for page: Page) -> PKDrawing {
        if let data = page.pencilData, let drawing = try? PKDrawing(data: data) { return drawing }
        let strokes = page.strokes.compactMap { value -> PKStroke? in
            let numbers = value.list("points").compactMap(\.number)
            guard numbers.count >= 3 else { return nil }
            let width = value.number("width", 3), marker = value.text("tool") == "highlighter"
            var controls: [PKStrokePoint] = []
            for offset in stride(from: 0, to: numbers.count - 2, by: 3) {
                let force = max(0.05, min(1.5, numbers[offset + 2]))
                let size = width * (marker ? 1 : (0.5 + force * 0.5))
                controls.append(PKStrokePoint(location: CGPoint(x: numbers[offset], y: numbers[offset + 1]),
                    timeOffset: Double(offset / 3) / 120, size: CGSize(width: size, height: size),
                    opacity: 1, force: force, azimuth: 0, altitude: .pi / 2))
            }
            if controls.count == 1 { controls.append(controls[0]) }
            let ink = PKInk(marker ? .marker : .pen, color: UIColor(argb: value.number("color", -14340028)))
            return PKStroke(ink: ink, path: PKStrokePath(controlPoints: controls, creationDate: Date()))
        }
        return PKDrawing(strokes: strokes)
    }

    static func save(_ drawing: PKDrawing, to page: inout Page) {
        page.pencilData = drawing.dataRepresentation()
        page.strokes = drawing.strokes.flatMap { stroke -> [[String: JSONValue]] in
            guard !stroke.path.isEmpty else { return [] }
            let ranges = stroke.mask == nil ? [CGFloat(0)...CGFloat(stroke.path.count - 1)] : stroke.maskedPathRanges
            return ranges.compactMap { range in
                var numbers: [JSONValue] = []
                var widths: [CGFloat] = []
                // Separate visible ranges keep partially erased ink erased in portable exports.
                for point in stroke.path.interpolatedPoints(in: range, by: .distance(1.5)) {
                    let location = point.location.applying(stroke.transform)
                    numbers.append(contentsOf: [.number(location.x), .number(location.y), .number(Double(point.force))])
                    widths.append(point.size.width)
                }
                let scale = hypot(stroke.transform.a, stroke.transform.b)
                let average = widths.isEmpty ? 3 : widths.reduce(0, +) / CGFloat(widths.count)
                guard !numbers.isEmpty else { return nil }
                return ["tool": .string(stroke.ink.inkType == .marker ? "highlighter" : "pen"),
                        "color": .number(stroke.ink.color.argb), "width": .number(Double(max(0.25, min(80, average * scale)))),
                        "points": .array(numbers)]
            }
        }
    }
}
