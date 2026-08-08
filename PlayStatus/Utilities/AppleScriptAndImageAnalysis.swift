import AppKit
import ObjectiveC.runtime

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
    var artworkTransitionIdentity: String {
        if let cachedIdentity = objc_getAssociatedObject(
            self,
            &ArtworkTransitionIdentityAssociation.key
        ) as? NSString {
            return cachedIdentity as String
        }

        let identity = makeArtworkTransitionIdentity()
        objc_setAssociatedObject(
            self,
            &ArtworkTransitionIdentityAssociation.key,
            identity as NSString,
            .OBJC_ASSOCIATION_COPY_NONATOMIC
        )
        return identity
    }

    func normalizedArtworkForDisplay(maxPixelSize: Int = 1200) -> NSImage {
        guard let cgImage = cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            let fallback = (copy() as? NSImage) ?? self
            if !(fallback.size.width.isFinite && fallback.size.height.isFinite &&
                 fallback.size.width > 0 && fallback.size.height > 0) {
                fallback.size = NSSize(width: 1, height: 1)
            }
            return fallback
        }

        let pixelWidth = max(cgImage.width, 1)
        let pixelHeight = max(cgImage.height, 1)
        let normalizedLogicalSize = NSSize(width: pixelWidth, height: pixelHeight)
        let hasValidLogicalSize =
            size.width.isFinite &&
            size.height.isFinite &&
            size.width > 0 &&
            size.height > 0
        let logicalMatchesPixels =
            hasValidLogicalSize &&
            abs(size.width - normalizedLogicalSize.width) < 0.5 &&
            abs(size.height - normalizedLogicalSize.height) < 0.5
        let largestPixelSide = max(pixelWidth, pixelHeight)
        let needsDownsample = largestPixelSide > maxPixelSize

        if !needsDownsample && logicalMatchesPixels {
            return self
        }

        let scale = min(1, CGFloat(maxPixelSize) / CGFloat(largestPixelSide))
        let outputWidth = max(1, Int((CGFloat(pixelWidth) * scale).rounded()))
        let outputHeight = max(1, Int((CGFloat(pixelHeight) * scale).rounded()))

        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: outputWidth,
            pixelsHigh: outputHeight,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: outputWidth * 4,
            bitsPerPixel: 32
        ) else {
            let fallback = NSImage(cgImage: cgImage, size: normalizedLogicalSize)
            fallback.size = normalizedLogicalSize
            return fallback
        }

        NSGraphicsContext.saveGraphicsState()
        if let context = NSGraphicsContext(bitmapImageRep: bitmap) {
            NSGraphicsContext.current = context
            context.imageInterpolation = .high
            context.cgContext.interpolationQuality = .high
            context.cgContext.draw(
                cgImage,
                in: CGRect(x: 0, y: 0, width: outputWidth, height: outputHeight)
            )
        }
        NSGraphicsContext.restoreGraphicsState()

        let normalized = NSImage(size: NSSize(width: outputWidth, height: outputHeight))
        normalized.addRepresentation(bitmap)
        normalized.size = NSSize(width: outputWidth, height: outputHeight)
        return normalized
    }

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
        let accent = dominantAccentColor(in: data, width: w, height: h)

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

    /// The colour the album actually reads as, used as the leading stop of the palette.
    ///
    /// This used to be a straight per-pixel argmax of `s * (0.55 + b * 0.45)` — the single
    /// most vibrant pixel on the cover, however few of its kind there were. On a pale blue
    /// sleeve with a small salmon tracklist that picks the salmon: a colour covering a few
    /// percent of the artwork became the colour of the whole window, and the surface came
    /// out warm brown for an album nobody would describe as warm.
    ///
    /// Vibrancy still decides between candidates, but coverage now decides which candidates
    /// are in the running. Pixels are binned by hue and scored as a family, so a large
    /// muted field can outrank a small saturated accent — while a genuinely vivid album
    /// still leads with its vivid colour, because it holds both.
    private func dominantAccentColor(in data: UnsafeMutablePointer<UInt8>, width: Int, height: Int) -> NSColor {
        let bucketCount = 12

        var counts = [Double](repeating: 0, count: bucketCount)
        var sumRed = [Double](repeating: 0, count: bucketCount)
        var sumGreen = [Double](repeating: 0, count: bucketCount)
        var sumBlue = [Double](repeating: 0, count: bucketCount)
        var sumSaturation = [Double](repeating: 0, count: bucketCount)
        var sumBrightness = [Double](repeating: 0, count: bucketCount)

        // Every visible pixel, chromatic or not — coverage has to be a share of the whole
        // cover, or a black-and-white sleeve with one coloured corner reports that corner
        // as 100% of the artwork.
        var visiblePixels: Double = 0
        var fallbackRed: Double = 0
        var fallbackGreen: Double = 0
        var fallbackBlue: Double = 0

        for y in 0..<height {
            for x in 0..<width {
                let idx = ((y * width) + x) * 4
                guard Double(data[idx + 3]) / 255.0 > 0.02 else { continue }

                let red = Double(data[idx]) / 255.0
                let green = Double(data[idx + 1]) / 255.0
                let blue = Double(data[idx + 2]) / 255.0

                visiblePixels += 1
                fallbackRed += red
                fallbackGreen += green
                fallbackBlue += blue

                let maxComponent = max(red, max(green, blue))
                let minComponent = min(red, min(green, blue))
                let delta = maxComponent - minComponent
                let saturation = maxComponent > 0 ? delta / maxComponent : 0

                // Near-grey and near-black pixels have no hue worth binning, and letting
                // them in would spread noise across every bucket.
                guard saturation >= 0.15, maxComponent >= 0.12, delta > 0 else { continue }

                var hue: Double
                if maxComponent == red {
                    hue = (green - blue) / delta
                } else if maxComponent == green {
                    hue = 2 + ((blue - red) / delta)
                } else {
                    hue = 4 + ((red - green) / delta)
                }
                hue = (hue / 6).truncatingRemainder(dividingBy: 1)
                if hue < 0 { hue += 1 }

                let bucket = min(bucketCount - 1, Int(hue * Double(bucketCount)))
                counts[bucket] += 1
                sumRed[bucket] += red
                sumGreen[bucket] += green
                sumBlue[bucket] += blue
                sumSaturation[bucket] += saturation
                sumBrightness[bucket] += maxComponent
            }
        }

        guard visiblePixels > 0 else { return NSColor(calibratedWhite: 0.5, alpha: 1) }

        var bestScore: Double = 0
        var bestColor: NSColor?

        for bucket in 0..<bucketCount {
            // Scored over a three-bucket window so a hue straddling a bin edge — reds split
            // across the 0/1 wrap especially — is not penalised for landing on the seam.
            let window = [
                (bucket + bucketCount - 1) % bucketCount,
                bucket,
                (bucket + 1) % bucketCount
            ]

            let windowCount = window.reduce(0.0) { $0 + counts[$1] }
            let coverage = windowCount / visiblePixels
            // Below this a bucket is speckle — a JPEG fringe or a few stray pixels.
            guard windowCount > 0, coverage >= 0.015 else { continue }

            let meanSaturation = window.reduce(0.0) { $0 + sumSaturation[$1] } / windowCount
            let meanBrightness = window.reduce(0.0) { $0 + sumBrightness[$1] } / windowCount
            let vibrancy = meanSaturation * (0.55 + (meanBrightness * 0.45))

            // Coverage is compressed rather than linear: a field twice the size counts for
            // clearly more, but not so much that a large dull mass always beats a vivid one.
            let score = vibrancy * pow(coverage, 0.75)
            guard score > bestScore else { continue }

            bestScore = score
            bestColor = NSColor(
                calibratedRed: CGFloat(window.reduce(0.0) { $0 + sumRed[$1] } / windowCount),
                green: CGFloat(window.reduce(0.0) { $0 + sumGreen[$1] } / windowCount),
                blue: CGFloat(window.reduce(0.0) { $0 + sumBlue[$1] } / windowCount),
                alpha: 1
            )
        }

        // No bucket cleared the floor: a monochrome cover. Its own average is the honest
        // answer, and `LiquidGlassBackground` has an achromatic path waiting for it.
        return bestColor ?? NSColor(
            calibratedRed: CGFloat(fallbackRed / visiblePixels),
            green: CGFloat(fallbackGreen / visiblePixels),
            blue: CGFloat(fallbackBlue / visiblePixels),
            alpha: 1
        )
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

private enum ArtworkTransitionIdentityAssociation {
    static var key: UInt8 = 0
}

private func artworkFingerprintHash<S: Sequence>(_ bytes: S) -> String where S.Element == UInt8 {
    var hash: UInt64 = 1469598103934665603
    for byte in bytes {
        hash ^= UInt64(byte)
        hash = hash &* 1099511628211
    }
    return String(hash, radix: 16)
}

private extension NSImage {
    func makeArtworkTransitionIdentity() -> String {
        if let cgImage = cgImage(forProposedRect: nil, context: nil, hints: nil) {
            let sampleSide = 12
            if let bitmap = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: sampleSide,
                pixelsHigh: sampleSide,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: sampleSide * 4,
                bitsPerPixel: 32
            ), let bytes = bitmap.bitmapData {
                NSGraphicsContext.saveGraphicsState()
                if let context = NSGraphicsContext(bitmapImageRep: bitmap) {
                    NSGraphicsContext.current = context
                    context.imageInterpolation = .high
                    context.cgContext.interpolationQuality = .high
                    context.cgContext.draw(
                        cgImage,
                        in: CGRect(x: 0, y: 0, width: sampleSide, height: sampleSide)
                    )
                }
                NSGraphicsContext.restoreGraphicsState()

                let byteCount = sampleSide * sampleSide * 4
                let hash = artworkFingerprintHash(
                    UnsafeBufferPointer(start: bytes, count: byteCount)
                )
                return "\(cgImage.width)x\(cgImage.height)|\(hash)"
            }

            return "\(cgImage.width)x\(cgImage.height)"
        }

        if let data = tiffRepresentation {
            return "tiff|\(data.count)|\(artworkFingerprintHash(data.prefix(4096)))"
        }

        let width = Int(size.width.rounded())
        let height = Int(size.height.rounded())
        return "size|\(width)x\(height)"
    }
}
