import CoreGraphics
import QuartzCore
import SwiftUI

struct CoverFlowGeometry {
    let metrics: CoverFlowLayout
    let states: [CoverFlowLayout.CoverPose]
    let firstIndex: Int

    init(metrics: CoverFlowLayout, states: [CoverFlowLayout.CoverPose], firstIndex: Int = 0) {
        self.metrics = metrics
        self.states = states
        self.firstIndex = firstIndex
    }

    init(metrics: CoverFlowLayout, count: Int, position: Double) {
        // Outside these slots the fade is zero. Interpolated positions can bring
        // the next slot into view before the scroll position reaches a whole item.
        let radius = Double(metrics.innerSlots) + 1
        let first = Int(max(0, min(Double(count), floor(position - radius))))
        let end = Int(max(Double(first), min(Double(count), ceil(position + radius))))
        self.init(
            metrics: metrics,
            states: (first..<end).map { metrics.state(relativePosition: Double($0) - position) },
            firstIndex: first
        )
    }

    static func states(count: Int, position: Double, metrics: CoverFlowLayout)
        -> [CoverFlowLayout.CoverPose]
    {
        (0..<count).map { metrics.state(relativePosition: Double($0) - position) }
    }

    func planes(aspectRatio: (Int) -> Double = { _ in 1 }) -> [CoverFlowPlane] {
        self.planes(aspectRatio: aspectRatio, depthShape: \.silhouette)
    }

    private func planes(
        aspectRatio: (Int) -> Double, depthShape: KeyPath<CoverFlowPlane, CGPath>
    ) -> [CoverFlowPlane] {
        guard self.metrics.viewport.width > 0, self.metrics.viewport.height > 0 else { return [] }

        var planes = self.states.enumerated().compactMap { offset, state in
            self.plane(for: state, at: self.firstIndex + offset, aspectRatio: aspectRatio)
        }

        planes.sort { lhs, rhs in
            if lhs.drawDistance == rhs.drawDistance {
                return lhs.itemIndex < rhs.itemIndex
            }
            return lhs.drawDistance > rhs.drawDistance
        }

        if !self.metrics.configuration.preservesContentAlpha {
            self.applyDepthClipping(to: &planes, shape: depthShape)
        }

        return planes
    }

    private func applyDepthClipping(
        to planes: inout [CoverFlowPlane], shape: KeyPath<CoverFlowPlane, CGPath>
    ) {
        let viewport = CGRect(origin: .zero, size: self.metrics.viewport)
        let fills = planes.map {
            CoverFlowPlane.DepthSurface(shape: $0[keyPath: shape], projection: $0.projection)
        }

        func visibility(of target: CoverFlowPlane.DepthSurface, at index: Int) -> CGPath? {
            var uncovered: CGPath?
            var visible: CGPath?

            for previous in (0..<index).reversed() {
                let writesUnconditionally = planes[previous].usesUnconditionalDepth
                let surface = fills[previous]
                guard target.bounds.intersects(surface.bounds) else { continue }

                if let cut = surface.occlusion(of: target, in: viewport) {
                    let covered = uncovered.map { cut.intersection($0) } ?? cut
                    if !covered.isEmpty {
                        let remaining = (visible ?? target.shape).subtracting(covered)
                        if remaining.isEmpty { return remaining }
                        visible = remaining
                    }
                }

                if writesUnconditionally {
                    let remaining = (uncovered ?? target.shape).subtracting(surface.shape)
                    if remaining.isEmpty { return visible }
                    uncovered = remaining
                }
            }

            return visible
        }

        for index in planes.indices where !planes[index].usesUnconditionalDepth {
            planes[index].clip = visibility(of: fills[index], at: index)
        }
    }

    func coverIndex(at point: CGPoint, aspectRatio: (Int) -> Double = { _ in 1 }) -> Int? {
        guard CGRect(origin: .zero, size: self.metrics.viewport).contains(point) else { return nil }

        let planes = self.planes(aspectRatio: aspectRatio, depthShape: \.faceSilhouette)
        for plane in planes.reversed() {
            guard plane.clip?.contains(point) != false else { continue }
            if plane.faceSilhouette.contains(point) {
                return plane.itemIndex
            }
        }

        return nil
    }

    private func plane(
        for state: CoverFlowLayout.CoverPose, at index: Int, aspectRatio: (Int) -> Double
    ) -> CoverFlowPlane? {
        let intensity = self.metrics.intensity(at: state.x)
        guard intensity > 0 else { return nil }

        let frame = self.metrics.faceFrame(aspectRatio: aspectRatio(index))
        let size = frame.size
        guard size.width > 0, size.height > 0 else { return nil }

        let matrix = self.metrics.transform(for: state, faceOrigin: frame.minX)
        let projection = Self.projection(
            matrix, height: size.height, viewportHeight: self.metrics.viewport.height)
        let cameraDepth = self.metrics.configuration.cameraDepthRange
        guard
            let fillRange = Self.clipToCamera(width: size.width, matrix: matrix, depth: cameraDepth)
        else {
            return nil
        }

        // At and beyond the first side slots iTunes uses GL_ALWAYS.
        let depthBounds = self.metrics.depthTestBounds
        return CoverFlowPlane(
            itemIndex: index,
            projection: projection,
            usesUnconditionalDepth: state.x <= depthBounds.left || state.x >= depthBounds.right,
            intensity: intensity,
            drawDistance: self.metrics.drawDistance(at: state.x),
            size: size,
            xRange: fillRange,
            reflectionGap: max(0, self.metrics.configuration.reflection.gap)
        )
    }

    private static func clipToCamera(
        width: Double, matrix: CATransform3D,
        depth: ClosedRange<Double>
    ) -> ClosedRange<Double>? {
        // The y rotation makes camera-space w vary only across x.
        let start = Double(matrix.m44)
        let slope = Double(matrix.m14)
        let end = start + slope * width
        let near = depth.lowerBound
        let far = depth.upperBound
        guard max(start, end) >= near && min(start, end) <= far else { return nil }
        if min(start, end) >= near && max(start, end) <= far { return 0...width }

        let nearX = (near - start) / slope
        let farX = (far - start) / slope
        let left = max(0, min(nearX, farX))
        let right = min(width, max(nearX, farX))

        return left < right ? left...right : nil
    }

    /// Convert the recovered bottom-up projection to SwiftUI's top-down coordinates.
    static func projection(_ m: CATransform3D, height: Double, viewportHeight: Double)
        -> ProjectionTransform
    {
        var p = ProjectionTransform()
        p.m11 = m.m11
        p.m12 = viewportHeight * Double(m.m14) - Double(m.m12)
        p.m13 = m.m14
        p.m21 = -m.m21
        p.m22 = Double(m.m22) - viewportHeight * Double(m.m24)
        p.m23 = -m.m24
        p.m31 = Double(m.m41) + height * Double(m.m21)
        let w = Double(m.m44) + height * Double(m.m24)
        p.m32 = viewportHeight * w - (Double(m.m42) + height * Double(m.m22))
        p.m33 = w

        return p
    }
}
