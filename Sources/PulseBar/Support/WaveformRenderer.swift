import AppKit

enum WaveformRenderer {
    private enum SpectrumDistribution {
        case centerOutward
        case natural
    }

    private static func displayedLevels(
        _ levels: [CGFloat],
        count: Int,
        distribution: SpectrumDistribution
    ) -> [CGFloat] {
        guard count > 0 else { return [] }
        let history = levels.isEmpty ? [CGFloat(0)] : levels

        return (0..<count).map { index in
            let position = count == 1 ? 0.5 : CGFloat(index) / CGFloat(count - 1)
            let age: CGFloat
            switch distribution {
            case .centerOutward:
                age = abs(position - 0.5) * 2
            case .natural:
                age = 1 - position
            }
            return interpolatedLevel(in: history, age: age)
        }
    }

    @MainActor
    static func statusImage(
        levels: [CGFloat],
        lowFrequencyLevels: [CGFloat],
        highFrequencyLevels: [CGFloat],
        peakLevels: [CGFloat],
        preferences: WaveformPreferences
    ) -> NSImage {
        image(
            size: NSSize(width: preferences.statusItemWidth, height: 18),
            levels: levels,
            lowFrequencyLevels: lowFrequencyLevels,
            highFrequencyLevels: highFrequencyLevels,
            peakLevels: peakLevels,
            preferences: preferences
        )
    }

    @MainActor
    static func stylePreviewImage(size: NSSize, shape: WaveformShape) -> NSImage {
        let color = NSColor(srgbRed: 0.32, green: 0.52, blue: 0.96, alpha: 1)
        let density = sampleCount(for: shape, width: size.width)
        let values = displayedLevels(
            previewLevels(for: shape),
            count: density,
            distribution: .natural
        )

        return NSImage(size: size, flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.setAllowsAntialiasing(true)

            switch shape {
            case .fineSpectrum:
                drawLayeredFineSpectrum(
                    in: context,
                    rect: rect,
                    values: values,
                    color: color,
                    anchor: .upward
                )
            case .waveLines:
                drawWaveLines(
                    in: context,
                    rect: rect.insetBy(dx: 0, dy: rect.height * 0.12),
                    values: values,
                    color: color,
                    anchor: .centered,
                    layerSpacing: 0.14,
                    alphas: [0.18, 1, 0.46]
                )
            case .softSpectrum:
                drawSoftSpectrum(
                    in: context,
                    rect: rect,
                    values: values,
                    color: color,
                    anchor: .upward
                )
            case .mountains:
                drawMountains(
                    in: context,
                    rect: rect,
                    values: values,
                    color: color,
                    anchor: .upward
                )
            }
            return true
        }
    }

    private static func previewLevels(for shape: WaveformShape) -> [CGFloat] {
        switch shape {
        case .fineSpectrum:
            return [
                0.08, 0.16, 0.28, 0.42, 0.5, 0.44, 0.34, 0.3, 0.38,
                0.62, 0.9, 0.58, 0.46, 0.4, 0.24, 0.18, 0.3, 0.52,
                0.78, 0.66, 0.48, 0.4, 0.24, 0.18, 0.28, 0.46, 0.4,
                0.32, 0.2, 0.12
            ]
        case .waveLines:
            return [
                0.24, 0.34, 0.52, 0.74, 0.58, 0.4, 0.32, 0.46, 0.72,
                0.92, 0.68, 0.42, 0.28, 0.36, 0.6, 0.8, 0.62, 0.4,
                0.3, 0.44, 0.7, 0.56, 0.34, 0.24
            ]
        case .softSpectrum, .mountains:
            return [
                0.05, 0.08, 0.14, 0.26, 0.5, 0.82, 0.98, 0.84, 0.58,
                0.3, 0.14, 0.1, 0.16, 0.3, 0.54, 0.68, 0.56, 0.36,
                0.2, 0.12, 0.18, 0.34, 0.58, 0.72, 0.6, 0.38, 0.18, 0.08
            ]
        }
    }

    private static func interpolatedLevel(in history: [CGFloat], age: CGFloat) -> CGFloat {
        guard history.count > 1 else { return history[0] }
        let offset = min(1, max(0, age)) * CGFloat(history.count - 1)
        let newerIndex = history.count - 1 - Int(floor(offset))
        let olderIndex = max(0, newerIndex - 1)
        let fraction = offset - floor(offset)
        return history[newerIndex] * (1 - fraction) + history[olderIndex] * fraction
    }

    @MainActor
    private static func image(
        size: NSSize,
        levels: [CGFloat],
        lowFrequencyLevels: [CGFloat],
        highFrequencyLevels: [CGFloat],
        peakLevels: [CGFloat],
        preferences: WaveformPreferences
    ) -> NSImage {
        let shape = preferences.shape
        let color = preferences.colorMode == .system
            ? NSColor.controlAccentColor
            : preferences.customColor
        let density = preferences.orientation == .horizontal
            ? horizontalSampleCount(for: shape)
            : sampleCount(for: shape, width: size.width)
        let values = displayedLevels(
            levels,
            count: density,
            distribution: .centerOutward
        )
        let peaks = displayedLevels(
            peakLevels,
            count: density,
            distribution: .centerOutward
        )
        let mountainForeground = displayedLevels(
            lowFrequencyLevels,
            count: density,
            distribution: .centerOutward
        )
        let mountainBackground = displayedLevels(
            highFrequencyLevels,
            count: density,
            distribution: .centerOutward
        )
        let anchor = preferences.anchor
        let orientation = preferences.orientation
        let showsPeaks = preferences.peakHold && shape.isBarStyle

        let image = NSImage(size: size, flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.setAllowsAntialiasing(true)

            if orientation == .horizontal {
                context.saveGState()
                context.translateBy(x: rect.midX, y: rect.midY)
                context.rotate(by: .pi / 2)
                let rotatedRect = CGRect(
                    x: -rect.height / 2,
                    y: -rect.width / 2,
                    width: rect.height,
                    height: rect.width
                )
                drawWaveform(
                    in: context,
                    rect: rotatedRect,
                    values: values,
                    mountainForegroundValues: mountainForeground,
                    mountainBackgroundValues: mountainBackground,
                    peakValues: peaks,
                    shape: shape,
                    color: color,
                    anchor: anchor,
                    showsPeaks: showsPeaks
                )
                context.restoreGState()
            } else {
                drawWaveform(
                    in: context,
                    rect: rect,
                    values: values,
                    mountainForegroundValues: mountainForeground,
                    mountainBackgroundValues: mountainBackground,
                    peakValues: peaks,
                    shape: shape,
                    color: color,
                    anchor: anchor,
                    showsPeaks: showsPeaks
                )
            }
            return true
        }
        image.isTemplate = false
        return image
    }

    private static func drawWaveform(
        in context: CGContext,
        rect: CGRect,
        values: [CGFloat],
        mountainForegroundValues: [CGFloat],
        mountainBackgroundValues: [CGFloat],
        peakValues: [CGFloat],
        shape: WaveformShape,
        color: NSColor,
        anchor: WaveformAnchor,
        showsPeaks: Bool
    ) {
        if values.max() ?? 0 < 0.025 {
            drawIdleWaveform(
                in: context,
                rect: rect,
                count: values.count,
                shape: shape,
                color: color,
                anchor: anchor
            )
            if showsPeaks {
                drawPeakIndicators(
                    in: context,
                    rect: rect,
                    values: peakValues,
                    color: color,
                    anchor: anchor,
                    shape: shape
                )
            }
            return
        }

        switch shape {
        case .fineSpectrum:
            drawLayeredFineSpectrum(
                in: context,
                rect: rect,
                values: values,
                color: color,
                anchor: anchor
            )
            if showsPeaks {
                drawPeakIndicators(
                    in: context,
                    rect: rect,
                    values: peakValues,
                    color: color,
                    anchor: anchor,
                    shape: shape
                )
            }
        case .waveLines:
            drawWaveLines(in: context, rect: rect, values: values, color: color, anchor: anchor)
        case .softSpectrum:
            drawSoftSpectrum(in: context, rect: rect, values: values, color: color, anchor: anchor)
            if showsPeaks {
                drawPeakIndicators(
                    in: context,
                    rect: rect,
                    values: peakValues,
                    color: color,
                    anchor: anchor,
                    shape: shape
                )
            }
        case .mountains:
            drawMountains(
                in: context,
                rect: rect,
                values: mountainForegroundValues,
                backgroundValues: mountainBackgroundValues,
                color: color,
                anchor: anchor
            )
        }
    }

    private static func horizontalSampleCount(for shape: WaveformShape) -> Int {
        switch shape {
        case .fineSpectrum, .waveLines: return 9
        case .softSpectrum, .mountains: return 7
        }
    }

    private static func sampleCount(for shape: WaveformShape, width: CGFloat) -> Int {
        if width < 120 {
            switch shape {
            case .fineSpectrum, .waveLines: return max(15, Int(width / 2))
            case .softSpectrum: return max(12, Int(width / 2.5))
            case .mountains: return max(9, Int(width / 4.5))
            }
        }

        switch shape {
        case .fineSpectrum: return 61
        case .waveLines: return 45
        case .softSpectrum, .mountains: return 49
        }
    }

    private static func drawIdleWaveform(
        in context: CGContext,
        rect: CGRect,
        count: Int,
        shape: WaveformShape,
        color: NSColor,
        anchor: WaveformAnchor
    ) {
        switch shape {
        case .fineSpectrum, .softSpectrum:
            drawIdleDots(
                in: context,
                rect: rect,
                count: count,
                color: color,
                anchor: anchor
            )
        case .waveLines:
            drawWaveLines(
                in: context,
                rect: rect,
                values: Array(repeating: 0.08, count: 9),
                color: color.withAlphaComponent(color.alphaComponent * 0.72),
                anchor: anchor,
                layerSpacing: 0.035,
                alphas: [0.22, 0.72, 0.34]
            )
        case .mountains:
            drawMountains(
                in: context,
                rect: rect,
                values: Array(repeating: 0.08, count: 9),
                color: color.withAlphaComponent(color.alphaComponent * 0.72),
                anchor: anchor
            )
        }
    }

    private static func drawIdleDots(
        in context: CGContext,
        rect: CGRect,
        count: Int,
        color: NSColor,
        anchor: WaveformAnchor
    ) {
        guard count > 0 else { return }
        let diameter = min(1.5, rect.width / CGFloat(count) * 0.58)
        let spacing = count == 1
            ? 0
            : (rect.width - diameter * CGFloat(count)) / CGFloat(count - 1)
        let centerY: CGFloat
        switch anchor {
        case .upward: centerY = rect.minY + diameter / 2
        case .centered: centerY = rect.midY
        case .downward: centerY = rect.maxY - diameter / 2
        }
        context.setFillColor(color.withAlphaComponent(color.alphaComponent * 0.72).cgColor)

        for index in 0..<count {
            context.fillEllipse(
                in: CGRect(
                    x: rect.minX + CGFloat(index) * (diameter + spacing),
                    y: centerY - diameter / 2,
                    width: diameter,
                    height: diameter
                )
            )
        }
    }

    private static func drawPeakIndicators(
        in context: CGContext,
        rect: CGRect,
        values: [CGFloat],
        color: NSColor,
        anchor: WaveformAnchor,
        shape: WaveformShape
    ) {
        guard values.max() ?? 0 >= 0.025 else { return }
        let spacing: CGFloat = shape == .softSpectrum && rect.width < 120 ? 1.1 : (rect.width < 120 ? 1 : 3)
        let barWidth = max(
            shape == .softSpectrum ? 1.4 : 1,
            (rect.width - spacing * CGFloat(values.count - 1)) / CGFloat(values.count)
        )
        let diameter = min(2.2, max(1.4, barWidth * 1.2))

        for (index, value) in values.enumerated() {
            let height = min(1, value) * rect.height
            let bar = anchoredRect(
                x: rect.minX + CGFloat(index) * (barWidth + spacing),
                width: barWidth,
                height: height,
                in: rect,
                anchor: anchor
            )
            let centerY: CGFloat
            switch anchor {
            case .upward, .centered:
                centerY = min(rect.maxY - diameter / 2, bar.maxY + 0.7 + diameter / 2)
            case .downward:
                centerY = max(rect.minY + diameter / 2, bar.minY - 0.7 - diameter / 2)
            }
            let dotX = min(
                rect.maxX - diameter,
                max(rect.minX, bar.midX - diameter / 2)
            )
            let dot = CGRect(
                x: dotX,
                y: centerY - diameter / 2,
                width: diameter,
                height: diameter
            )
            context.setFillColor(color.withAlphaComponent(color.alphaComponent * 0.92).cgColor)
            context.fillEllipse(in: dot)
        }
    }

    private static func drawFineSpectrum(
        in context: CGContext,
        rect: CGRect,
        values: [CGFloat],
        color: NSColor,
        anchor: WaveformAnchor
    ) {
        let spacing: CGFloat = rect.width < 120 ? 1 : 3
        let width = max(1, (rect.width - spacing * CGFloat(values.count - 1)) / CGFloat(values.count))

        for (index, value) in values.enumerated() {
            let height = max(1, min(1, value) * rect.height)
            let bar = anchoredRect(
                x: rect.minX + CGFloat(index) * (width + spacing),
                width: width,
                height: height,
                in: rect,
                anchor: anchor
            )
            context.setFillColor(
                color.withAlphaComponent(color.alphaComponent * 0.88).cgColor
            )
            context.fill(CGRect(x: bar.minX, y: bar.minY, width: bar.width, height: bar.height))
        }
    }

    private static func drawLayeredFineSpectrum(
        in context: CGContext,
        rect: CGRect,
        values: [CGFloat],
        color: NSColor,
        anchor: WaveformAnchor
    ) {
        let rearShift = max(2, values.count / 5)
        let middleShift = max(1, values.count / 10)
        let rear = values.indices.map {
            values[($0 + rearShift) % values.count] * 0.72
        }
        let middle = values.indices.map {
            values[($0 + middleShift) % values.count] * 0.86
        }
        drawFineSpectrum(
            in: context,
            rect: rect,
            values: rear,
            color: color.withAlphaComponent(color.alphaComponent * 0.22),
            anchor: anchor
        )
        drawFineSpectrum(
            in: context,
            rect: rect,
            values: middle,
            color: color.withAlphaComponent(color.alphaComponent * 0.42),
            anchor: anchor
        )
        drawFineSpectrum(
            in: context,
            rect: rect,
            values: values,
            color: color,
            anchor: anchor
        )
    }

    private static func drawWaveLines(
        in context: CGContext,
        rect: CGRect,
        values: [CGFloat],
        color: NSColor,
        anchor: WaveformAnchor,
        layerSpacing: CGFloat = 0.08,
        alphas: [CGFloat] = [0.34, 0.9, 0.5]
    ) {
        let average = values.reduce(0, +) / CGFloat(values.count)

        let offsets = [-max(1, values.count / 10), 0, max(1, values.count / 10)]
        for layer in offsets.indices {
            let shifted = values.indices.map { index in
                values[min(values.count - 1, max(0, index + offsets[layer]))]
            }
            let points = shifted.enumerated().map { index, value in
                CGPoint(
                    x: xPosition(index: index, count: shifted.count, rect: rect),
                    y: lineY(
                        value: value,
                        average: average,
                        layer: layer,
                        rect: rect,
                        anchor: anchor,
                        layerSpacing: layerSpacing
                    )
                )
            }
            let path = smoothPath(points)
            context.addPath(path)
            context.setStrokeColor(
                color.withAlphaComponent(color.alphaComponent * alphas[layer]).cgColor
            )
            context.setLineWidth(rect.width < 120 ? 0.9 : 1.25)
            context.setLineCap(.round)
            context.strokePath()
        }
    }

    private static func drawSoftSpectrum(
        in context: CGContext,
        rect: CGRect,
        values: [CGFloat],
        color: NSColor,
        anchor: WaveformAnchor
    ) {
        let spacing: CGFloat = rect.width < 120 ? 1.1 : 3
        let width = max(1.4, (rect.width - spacing * CGFloat(values.count - 1)) / CGFloat(values.count))

        context.saveGState()
        context.setShadow(
            offset: .zero,
            blur: rect.width < 120 ? 1.5 : 5,
            color: color.withAlphaComponent(color.alphaComponent * 0.42).cgColor
        )
        for (index, value) in values.enumerated() {
            let height = max(1.5, min(1, value) * rect.height)
            let bar = anchoredRect(
                x: rect.minX + CGFloat(index) * (width + spacing),
                width: width,
                height: height,
                in: rect,
                anchor: anchor
            )
            let path = CGPath(
                roundedRect: bar,
                cornerWidth: width / 2,
                cornerHeight: width / 2,
                transform: nil
            )
            context.addPath(path)
            context.setFillColor(
                color.withAlphaComponent(color.alphaComponent * 0.76).cgColor
            )
            context.fillPath()
        }
        context.restoreGState()
    }

    private static func drawMountains(
        in context: CGContext,
        rect: CGRect,
        values: [CGFloat],
        backgroundValues: [CGFloat]? = nil,
        color: NSColor,
        anchor: WaveformAnchor,
        shiftDivisor: Int = 7,
        frontScale: CGFloat = 0.72,
        alphas: [CGFloat] = [0.22, 0.58]
    ) {
        let background: [CGFloat]
        if let backgroundValues, backgroundValues.count == values.count {
            background = backgroundValues
        } else {
            let shift = max(1, values.count / shiftDivisor)
            background = values.indices.map { index in
                values[max(0, index - shift)]
            }
        }
        let layers = [background, values.map { min(1, $0 * frontScale) }]

        for layer in layers.indices {
            let path = mountainPath(values: layers[layer], rect: rect, anchor: anchor)
            context.addPath(path)
            context.setFillColor(
                color.withAlphaComponent(color.alphaComponent * alphas[layer]).cgColor
            )
            context.fillPath()
        }
    }

    private static func anchoredRect(
        x: CGFloat,
        width: CGFloat,
        height: CGFloat,
        in rect: CGRect,
        anchor: WaveformAnchor
    ) -> CGRect {
        let y: CGFloat
        switch anchor {
        case .upward: y = rect.minY
        case .centered: y = rect.midY - height / 2
        case .downward: y = rect.maxY - height
        }
        return CGRect(x: x, y: y, width: width, height: height)
    }

    private static func lineY(
        value: CGFloat,
        average: CGFloat,
        layer: Int,
        rect: CGRect,
        anchor: WaveformAnchor,
        layerSpacing: CGFloat
    ) -> CGFloat {
        let layerOffset = CGFloat(layer - 1) * rect.height * layerSpacing
        switch anchor {
        case .upward:
            return rect.minY + value * rect.height * 0.86 + layerOffset
        case .centered:
            return rect.midY + (value - average) * rect.height * 0.9 + layerOffset
        case .downward:
            return rect.maxY - value * rect.height * 0.86 + layerOffset
        }
    }

    private static func mountainPath(
        values: [CGFloat],
        rect: CGRect,
        anchor: WaveformAnchor
    ) -> CGPath {
        let path = CGMutablePath()
        guard !values.isEmpty else { return path }
        var boundedValues = values
        boundedValues[0] = 0
        boundedValues[boundedValues.count - 1] = 0

        if anchor == .centered {
            let upper = boundedValues.enumerated().map { index, value in
                CGPoint(
                    x: xPosition(index: index, count: boundedValues.count, rect: rect),
                    y: rect.midY + value * rect.height * 0.46
                )
            }
            let lower = boundedValues.enumerated().reversed().map { index, value in
                CGPoint(
                    x: xPosition(index: index, count: boundedValues.count, rect: rect),
                    y: rect.midY - value * rect.height * 0.46
                )
            }
            path.move(to: upper[0])
            path.addLines(between: Array(upper.dropFirst()))
            path.addLines(between: lower)
            path.closeSubpath()
            return path
        }

        let baseline = anchor == .upward ? rect.minY : rect.maxY
        let points = boundedValues.enumerated().map { index, value in
            CGPoint(
                x: xPosition(index: index, count: boundedValues.count, rect: rect),
                y: anchor == .upward
                    ? rect.minY + value * rect.height
                    : rect.maxY - value * rect.height
            )
        }
        path.move(to: CGPoint(x: rect.minX, y: baseline))
        path.addLines(between: points)
        path.addLine(to: CGPoint(x: rect.maxX, y: baseline))
        path.closeSubpath()
        return path
    }

    private static func xPosition(index: Int, count: Int, rect: CGRect) -> CGFloat {
        count == 1
            ? rect.midX
            : rect.minX + CGFloat(index) / CGFloat(count - 1) * rect.width
    }

    private static func smoothPath(_ points: [CGPoint]) -> CGPath {
        let path = CGMutablePath()
        guard let first = points.first else { return path }
        path.move(to: first)

        for index in 0..<(points.count - 1) {
            let previous = index > 0 ? points[index - 1] : points[index]
            let current = points[index]
            let next = points[index + 1]
            let following = index + 2 < points.count ? points[index + 2] : next
            path.addCurve(
                to: next,
                control1: CGPoint(
                    x: current.x + (next.x - previous.x) / 6,
                    y: current.y + (next.y - previous.y) / 6
                ),
                control2: CGPoint(
                    x: next.x - (following.x - current.x) / 6,
                    y: next.y - (following.y - current.y) / 6
                )
            )
        }
        return path
    }
}
