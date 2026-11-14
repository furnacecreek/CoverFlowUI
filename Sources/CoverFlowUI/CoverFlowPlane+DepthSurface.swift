import CoreGraphics
import SwiftUI

extension CoverFlowPlane {
    struct DepthSurface {
        let shape: CGPath
        let bounds: CGRect
        let slope: Double
        let intercept: Double

        init(shape: CGPath, projection: ProjectionTransform) {
            self.shape = shape
            self.bounds = shape.boundingBoxOfPath

            let m11 = Double(projection.m11), m13 = Double(projection.m13)
            let determinant = m11 * Double(projection.m33) - m13 * Double(projection.m31)
            self.slope = -m13 / determinant
            self.intercept = m11 / determinant
        }

        func occlusion(of other: Self, in viewport: CGRect) -> CGPath? {
            let overlap = viewport.intersection(self.bounds).intersection(other.bounds)
            guard !overlap.isEmpty else { return nil }

            let dx = self.slope - other.slope
            let offset = self.intercept - other.intercept

            let left = Double(overlap.minX)
            let right = Double(overlap.maxX)
            let a = left * dx + offset
            let b = right * dx + offset
            let epsilon = 1e-14
            guard max(a, b) > epsilon || (abs(a) <= epsilon && abs(b) <= epsilon) else {
                return nil
            }

            let region = self.shape.intersection(other.shape)
            if min(a, b) >= 0 || max(abs(a), abs(b)) <= epsilon { return region }

            let crossing = left + (right - left) * a / (a - b)
            let start = a < 0 ? crossing : left
            let end = a < 0 ? right : crossing
            let strip = CGRect(
                x: start, y: overlap.minY, width: end - start, height: overlap.height)

            return region.intersection(CGPath(rect: strip, transform: nil))
        }
    }
}
