import AppKit

@discardableResult
func runAppleScript(_ source: String) -> String? {
    var errorDict: NSDictionary?
    let script = NSAppleScript(source: source)
    let output = script?.executeAndReturnError(&errorDict)
    if errorDict != nil { return nil }
    return output?.stringValue
}

func runAppleScriptDescriptor(_ source: String) -> NSAppleEventDescriptor? {
    var errorDict: NSDictionary?
    let script = NSAppleScript(source: source)
    let output = script?.executeAndReturnError(&errorDict)
    if errorDict != nil { return nil }
    return output
}

extension NSAppleEventDescriptor {
    var rawData: Data? {
        let payload = self.data
        if !payload.isEmpty { return payload }
        if let coerced = self.coerce(toDescriptorType: typeData) { return coerced.data }
        return nil
    }
}

// MARK: - Average color for tint

extension NSImage {
    func averageColor() -> NSColor? {
        let w = 32, h = 32
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: w,
            pixelsHigh: h,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: w * 4,
            bitsPerPixel: 32
        ) else { return nil }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.imageInterpolation = .high

        draw(in: NSRect(x: 0, y: 0, width: w, height: h),
             from: .zero,
             operation: .copy,
             fraction: 1.0)

        NSGraphicsContext.restoreGraphicsState()

        guard let data = rep.bitmapData else { return nil }
        var r: Double = 0, g: Double = 0, b: Double = 0, a: Double = 0

        for i in stride(from: 0, to: w * h * 4, by: 4) {
            let rr = Double(data[i]) / 255.0
            let gg = Double(data[i + 1]) / 255.0
            let bb = Double(data[i + 2]) / 255.0
            let aa = Double(data[i + 3]) / 255.0

            r += rr * aa
            g += gg * aa
            b += bb * aa
            a += aa
        }

        guard a > 0 else { return nil }
        r /= a; g /= a; b /= a

        let lift: Double = 0.12
        r = min(1, r + lift)
        g = min(1, g + lift)
        b = min(1, b + lift)

        return NSColor(calibratedRed: CGFloat(r), green: CGFloat(g), blue: CGFloat(b), alpha: 1.0)
    }

    func artworkPalette() -> [NSColor]? {
        let w = 40
        let h = 40
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: w,
            pixelsHigh: h,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: w * 4,
            bitsPerPixel: 32
        ) else { return nil }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.imageInterpolation = .high
        draw(in: NSRect(x: 0, y: 0, width: w, height: h), from: .zero, operation: .copy, fraction: 1.0)
        NSGraphicsContext.restoreGraphicsState()

        guard let data = rep.bitmapData else { return nil }

        func averageColor(xRange: ClosedRange<Int>, yRange: ClosedRange<Int>) -> NSColor {
            var r: Double = 0
            var g: Double = 0
            var b: Double = 0
            var a: Double = 0

            for y in yRange {
                for x in xRange {
                    let safeX = min(max(x, 0), w - 1)
                    let safeY = min(max(y, 0), h - 1)
                    let idx = (safeY * w + safeX) * 4
                    let alpha = Double(data[idx + 3]) / 255.0
                    guard alpha > 0 else { continue }
                    r += (Double(data[idx]) / 255.0) * alpha
                    g += (Double(data[idx + 1]) / 255.0) * alpha
                    b += (Double(data[idx + 2]) / 255.0) * alpha
                    a += alpha
                }
            }

            guard a > 0 else {
                return NSColor(calibratedWhite: 0.5, alpha: 1)
            }

            return NSColor(
                calibratedRed: CGFloat(r / a),
                green: CGFloat(g / a),
                blue: CGFloat(b / a),
                alpha: 1
            )
        }

        let topLeft = averageColor(xRange: 0...19, yRange: 0...19)
        let topRight = averageColor(xRange: 20...39, yRange: 0...19)
        let bottomLeft = averageColor(xRange: 0...19, yRange: 20...39)
        let bottomRight = averageColor(xRange: 20...39, yRange: 20...39)
        let center = averageColor(xRange: 12...27, yRange: 12...27)
        let cross = blend(topRight, bottomLeft, ratio: 0.5)
        let accent = mostVibrantColor(in: data, width: w, height: h)

        return [
            lift(accent, sat: 1.45, bright: 1.10),
            lift(center, sat: 1.18, bright: 1.10),
            lift(topLeft, sat: 1.34, bright: 1.06),
            lift(topRight, sat: 1.28, bright: 1.06),
            lift(cross, sat: 1.20, bright: 1.04),
            lift(bottomLeft, sat: 1.22, bright: 1.02),
            lift(bottomRight, sat: 1.18, bright: 1.00)
        ]
    }

    private func mostVibrantColor(in data: UnsafeMutablePointer<UInt8>, width: Int, height: Int) -> NSColor {
        var best = NSColor(calibratedWhite: 0.5, alpha: 1)
        var bestScore: CGFloat = -1

        for y in stride(from: 0, to: height, by: 2) {
            for x in stride(from: 0, to: width, by: 2) {
                let idx = (y * width + x) * 4
                let alpha = CGFloat(data[idx + 3]) / 255.0
                guard alpha > 0.02 else { continue }

                let color = NSColor(
                    calibratedRed: CGFloat(data[idx]) / 255.0,
                    green: CGFloat(data[idx + 1]) / 255.0,
                    blue: CGFloat(data[idx + 2]) / 255.0,
                    alpha: 1
                )

                let rgb = color.usingColorSpace(.deviceRGB) ?? color
                var h: CGFloat = 0
                var s: CGFloat = 0
                var b: CGFloat = 0
                var a: CGFloat = 0
                rgb.getHue(&h, saturation: &s, brightness: &b, alpha: &a)

                // Prefer colors that are both saturated and bright enough to tint the card.
                let score = s * (0.55 + (b * 0.45))
                if score > bestScore {
                    bestScore = score
                    best = color
                }
            }
        }

        return best
    }

    private func blend(_ lhs: NSColor, _ rhs: NSColor, ratio: CGFloat) -> NSColor {
        let p = min(max(ratio, 0), 1)
        let lr = lhs.usingColorSpace(.deviceRGB) ?? lhs
        let rr = rhs.usingColorSpace(.deviceRGB) ?? rhs
        return NSColor(
            calibratedRed: lr.redComponent * (1 - p) + rr.redComponent * p,
            green: lr.greenComponent * (1 - p) + rr.greenComponent * p,
            blue: lr.blueComponent * (1 - p) + rr.blueComponent * p,
            alpha: 1.0
        )
    }

    private func lift(_ color: NSColor, sat: CGFloat, bright: CGFloat) -> NSColor {
        let rgb = color.usingColorSpace(.deviceRGB) ?? color
        var h: CGFloat = 0
        var s: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        rgb.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return NSColor(
            calibratedHue: h,
            saturation: min(max(s * sat, 0), 1),
            brightness: min(max(b * bright, 0), 1),
            alpha: 1
        )
    }
}
