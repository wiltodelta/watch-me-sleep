import Vision

/// Computes the Eye Aspect Ratio (EAR) from Vision eye-landmark points.
///
/// EAR is the mean of the two vertical eyelid distances divided by the horizontal
/// eye width. Based on typical values, open eyes sit around 0.25-0.35 and closed
/// eyes around 0.10-0.20. Vision returns different point counts depending on the
/// model revision and device, so each contour layout maps the classic six EAR
/// points (p1..p6) before applying the same formula.
public enum EyeAspectRatio {
    /// EAR for a Vision eye region. Returns 0 for degenerate geometry.
    public static func ratio(for region: VNFaceLandmarkRegion2D) -> Double {
        ratio(points: region.normalizedPoints)
    }

    /// EAR for raw normalized eye-contour points. Pure and unit-testable.
    public static func ratio(points: [CGPoint]) -> Double {
        switch points.count {
        case 6, 8:
            // 6- and 8-point contours share the same index layout.
            return contourRatio(points, top: (1, 2), bottom: (5, 4), corners: (0, 3))
        case 12:
            // 12-point detailed contour: pick the indices matching the classic six points.
            return contourRatio(points, top: (2, 4), bottom: (10, 8), corners: (0, 6))
        default:
            return geometricRatio(points: points)
        }
    }

    /// EAR from explicit contour indices. `top`/`bottom` are the (outer, inner)
    /// eyelid points; `corners` is the (outer, inner) eye corner pair.
    private static func contourRatio(
        _ points: [CGPoint],
        top: (Int, Int),
        bottom: (Int, Int),
        corners: (Int, Int)
    ) -> Double {
        let verticalDist1 = distance(points[top.0], points[bottom.0])
        let verticalDist2 = distance(points[top.1], points[bottom.1])
        let horizontalDist = distance(points[corners.0], points[corners.1])
        return ear(vertical1: verticalDist1, vertical2: verticalDist2, horizontal: horizontalDist)
    }

    /// Fallback for non-standard point counts: derive corners and eyelids geometrically.
    private static func geometricRatio(points: [CGPoint]) -> Double {
        guard points.count >= 6 else { return 0.0 }

        // Horizontal extremes are the eye corners.
        let outerCorner = points.min(by: { $0.x < $1.x }) ?? points[0]
        let innerCorner = points.max(by: { $0.x < $1.x }) ?? points[0]

        // Split around the center to estimate top/bottom eyelids on each side.
        let centerX = (outerCorner.x + innerCorner.x) / 2.0
        let leftHalf = points.filter { $0.x < centerX }
        let rightHalf = points.filter { $0.x >= centerX }

        let leftTop = leftHalf.max(by: { $0.y < $1.y }) ?? outerCorner
        let leftBottom = leftHalf.min(by: { $0.y < $1.y }) ?? outerCorner
        let rightTop = rightHalf.max(by: { $0.y < $1.y }) ?? innerCorner
        let rightBottom = rightHalf.min(by: { $0.y < $1.y }) ?? innerCorner

        let verticalDist1 = distance(leftTop, leftBottom)
        let verticalDist2 = distance(rightTop, rightBottom)
        let horizontalDist = distance(outerCorner, innerCorner)
        return ear(vertical1: verticalDist1, vertical2: verticalDist2, horizontal: horizontalDist)
    }

    /// The EAR formula: mean of the two vertical eyelid spans over the eye width.
    /// Returns 0 for a degenerate (zero-width) eye.
    private static func ear(vertical1: CGFloat, vertical2: CGFloat, horizontal: CGFloat) -> Double {
        guard horizontal > 0 else { return 0.0 }
        return Double((vertical1 + vertical2) / (2.0 * horizontal))
    }

    private static func distance(_ pointA: CGPoint, _ pointB: CGPoint) -> CGFloat {
        let dx = pointA.x - pointB.x
        let dy = pointA.y - pointB.y
        return (dx * dx + dy * dy).squareRoot()
    }
}
