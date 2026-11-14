import CoreGraphics

/// Projection, layout, reflection, and click animation settings for a Cover Flow pane.
///
/// Start with ``classic`` and modify a copy to customize the appearance.
public struct CoverFlowConfiguration: Equatable, Sendable {
    public init() {}

    /// Controls cover spacing, overlap, depth, and camera clipping.
    public struct Layout: Equatable, Sendable {
        public init() {}

        public var innerSlots = 8
        public var outerSlots = 5

        public var centerDepth: Double = 30
        public var sideDepth: Double = 60
        public var depthRange: Double = 1000
        public var depthNormalization: Double = 19
        public var nearClip: Double = 0.9999989867210388
        public var farClip: Double = 20
        public var verticalCameraOffset: Double = 0.24

        public var overlapNumerator: Double = 6
        public var overlapDivisor = 7
        public var edgeInsetFraction: Double = 0.25
        public var outerSpreadDivisor = 4
        public var sideIntensity: Double = 0.8
    }

    /// Controls the strength of each cover’s reflection and the gap below it.
    public struct Reflection: Equatable, Sendable {
        public init() {}

        public var nearIntensity: Double = 0.4
        public var farIntensity: Double = 0.05
        public var gap: Double = 0
    }

    /// Controls how quickly covers rotate and move into place after a click.
    public struct ExponentialEasing: Equatable, Sendable {
        public init() {}

        /// Set to zero to center the target immediately.
        public var timeMultiplier: Double = 15
        public var angleRetention: Double = 0.4
        public var nearPositionRetention: Double = 0.4
        public var farPositionRetention: Double = 0.7
        public var nearPositionThreshold: Double = 5
        public var settleThreshold: Double = 0.5
    }

    public var layout = Layout()
    public var sideAngle: Double = 60
    public var fieldOfView: Double = 50
    public var reflection = Reflection()
    public var clickAnimation = ExponentialEasing()
    public var preservesContentAlpha = false

    public var cameraDepthRange: ClosedRange<Double> {
        let near = max(Double.ulpOfOne, self.layout.nearClip)
        return near...max(near, self.layout.farClip)
    }

    /// The default preset, with layout metrics derived from the iTunes 9.0.2 library view on Mac OS X Snow Leopard.
    public static let classic = Self()

    /// The height in points of the centered cover at the default aspect ratio, before viewport clipping.
    /// Pass the pane size and the caption frame used to lay out the covers.
    public func projectedCenterCoverHeight(in viewport: CGSize, captionFrame: CGRect? = nil)
        -> Double
    {
        let metrics = CoverFlowLayout(
            viewport: viewport, captionFrame: captionFrame, configuration: self)
        let center = metrics.state(slot: metrics.centerSlot)
        let matrix = metrics.transform(for: center)
        return metrics.coverHeight * Double(matrix.m22) / Double(matrix.m44)
    }
}
