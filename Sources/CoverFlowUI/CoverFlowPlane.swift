import CoreGraphics
import SwiftUI

struct CoverFlowPlane {
    let itemIndex: Int
    let projection: ProjectionTransform
    let usesUnconditionalDepth: Bool
    let intensity: Double
    let drawDistance: Double
    let size: CGSize
    let xRange: ClosedRange<Double>
    let reflectionGap: Double
    var clip: CGPath?

    private var leftX: Double { self.projectX(self.xRange.lowerBound) }
    private var rightX: Double { self.projectX(self.xRange.upperBound) }

    func cameraClip(in viewport: CGSize) -> CGPath? {
        if self.xRange == 0...self.size.width { return nil }

        let x = min(self.leftX, self.rightX)
        return CGPath(
            rect: CGRect(x: x, y: 0, width: abs(self.rightX - self.leftX), height: viewport.height),
            transform: nil)
    }

    private func projectX(_ x: Double) -> Double {
        (Double(self.projection.m11) * x + Double(self.projection.m31))
            / (Double(self.projection.m13) * x + Double(self.projection.m33))
    }

    var silhouette: CGPath {
        guard self.xRange.lowerBound < self.xRange.upperBound else { return CGMutablePath() }

        if self.reflectionGap == 0 {
            return self.quad(top: 0, bottom: 2 * self.size.height)
        }

        let shape = self.quad(top: 0, bottom: self.size.height)
        shape.addPath(self.reflectionSilhouette)
        return shape
    }

    var faceSilhouette: CGPath {
        self.quad(top: 0, bottom: self.size.height)
    }

    var reflectionSilhouette: CGPath {
        self.quad(
            top: self.size.height + self.reflectionGap,
            bottom: 2 * self.size.height + self.reflectionGap)
    }

    private func quad(top: Double, bottom: Double) -> CGMutablePath {
        let left = self.xRange.lowerBound
        let right = self.xRange.upperBound
        let corners = [
            CGPoint(x: left, y: top), CGPoint(x: right, y: top),
            CGPoint(x: right, y: bottom), CGPoint(x: left, y: bottom),
        ]

        let path = CGMutablePath()
        path.addLines(between: corners.map { $0.applying(self.projection) })
        path.closeSubpath()
        return path
    }
}
