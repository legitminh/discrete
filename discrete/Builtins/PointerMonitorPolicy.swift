import CoreGraphics

/// All coordinates are WindowServer coordinates (top-left origin, y down).
enum PointerMonitorPolicy {
    static func destination(pointer: CGPoint, window: CGRect, displays: [CGRect]) -> CGPoint? {
        guard displays.count > 1, displays.contains(where: { $0.contains(pointer) }),
              let target = displays.max(by: { overlap($0, window) < overlap($1, window) }),
              overlap(target, window) > 0, !target.contains(pointer) else { return nil }
        return CGPoint(x: target.midX, y: target.midY)
    }

    private static func overlap(_ display: CGRect, _ window: CGRect) -> CGFloat {
        let intersection = display.intersection(window)
        return intersection.isNull ? 0 : intersection.width * intersection.height
    }
}
