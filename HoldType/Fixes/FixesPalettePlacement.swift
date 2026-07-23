import CoreGraphics

enum FixesPaletteAnchor: Equatable {
    case accessibility(CGRect)
    case appKit(CGRect)
}

struct FixesPaletteScreenGeometry: Equatable {
    let frame: CGRect
    let visibleFrame: CGRect
    let isPrimary: Bool
}

enum FixesPaletteCoordinateConverter {
    static func appKitRect(
        from anchor: FixesPaletteAnchor,
        primaryScreenFrame: CGRect
    ) -> CGRect {
        switch anchor {
        case .appKit(let rect):
            return rect
        case .accessibility(let rect):
            return CGRect(
                x: rect.minX,
                y: primaryScreenFrame.maxY - rect.maxY,
                width: rect.width,
                height: rect.height
            )
        }
    }
}

enum FixesPalettePlacement {
    static let defaultGap: CGFloat = 8
    static let defaultScreenMargin: CGFloat = 8

    static func panelFrame(
        panelSize: CGSize,
        anchor: FixesPaletteAnchor,
        screens: [FixesPaletteScreenGeometry],
        gap: CGFloat = defaultGap,
        screenMargin: CGFloat = defaultScreenMargin
    ) -> CGRect {
        let usableScreens = screens.filter {
            $0.visibleFrame.width > 0 && $0.visibleFrame.height > 0
        }
        guard let primaryScreen = usableScreens.first(where: \.isPrimary)
                ?? usableScreens.first
        else {
            return CGRect(origin: .zero, size: panelSize)
        }

        let convertedAnchor = FixesPaletteCoordinateConverter.appKitRect(
            from: anchor,
            primaryScreenFrame: primaryScreen.frame
        )
        let targetScreen = screen(
            containing: convertedAnchor,
            candidates: usableScreens
        )
        let visibleFrame = targetScreen.visibleFrame
        let width = min(
            panelSize.width,
            max(1, visibleFrame.width - (screenMargin * 2))
        )
        let height = min(
            panelSize.height,
            max(1, visibleFrame.height - (screenMargin * 2))
        )
        let size = CGSize(width: width, height: height)

        let minimumX = visibleFrame.minX + screenMargin
        let maximumX = visibleFrame.maxX - screenMargin - size.width
        let centeredX = convertedAnchor.midX - (size.width / 2)
        let x = clamp(centeredX, minimum: minimumX, maximum: maximumX)

        let minimumY = visibleFrame.minY + screenMargin
        let maximumY = visibleFrame.maxY - screenMargin - size.height
        let belowY = convertedAnchor.minY - gap - size.height
        let aboveY = convertedAnchor.maxY + gap
        let y: CGFloat
        if belowY >= minimumY {
            y = min(belowY, maximumY)
        } else if aboveY <= maximumY {
            y = max(aboveY, minimumY)
        } else {
            y = clamp(belowY, minimum: minimumY, maximum: maximumY)
        }

        return CGRect(origin: CGPoint(x: x, y: y), size: size)
    }

    private static func screen(
        containing anchor: CGRect,
        candidates: [FixesPaletteScreenGeometry]
    ) -> FixesPaletteScreenGeometry {
        let bestIntersection = candidates.max { lhs, rhs in
            intersectionArea(lhs.visibleFrame, anchor)
                < intersectionArea(rhs.visibleFrame, anchor)
        }
        if let bestIntersection,
           intersectionArea(bestIntersection.visibleFrame, anchor) > 0 {
            return bestIntersection
        }

        let anchorPoint = CGPoint(x: anchor.midX, y: anchor.midY)
        return candidates.min { lhs, rhs in
            squaredDistance(from: anchorPoint, to: lhs.visibleFrame)
                < squaredDistance(from: anchorPoint, to: rhs.visibleFrame)
        } ?? candidates[0]
    }

    private static func intersectionArea(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        guard !intersection.isNull else {
            return 0
        }

        return intersection.width * intersection.height
    }

    private static func squaredDistance(from point: CGPoint, to rect: CGRect) -> CGFloat {
        let nearestX = clamp(point.x, minimum: rect.minX, maximum: rect.maxX)
        let nearestY = clamp(point.y, minimum: rect.minY, maximum: rect.maxY)
        let deltaX = point.x - nearestX
        let deltaY = point.y - nearestY
        return (deltaX * deltaX) + (deltaY * deltaY)
    }

    private static func clamp(
        _ value: CGFloat,
        minimum: CGFloat,
        maximum: CGFloat
    ) -> CGFloat {
        guard maximum >= minimum else {
            return minimum
        }

        return min(max(value, minimum), maximum)
    }
}
