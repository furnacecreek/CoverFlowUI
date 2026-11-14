import Foundation
import QuartzCore

/// Pane geometry derived from the selected historical layout.
struct CoverFlowLayout {
    let configuration: CoverFlowConfiguration
    let viewport: CGSize

    let coverWidth: Double
    let coverHeight: Double
    let overlap: Int
    let edgeInset: Int
    let outerSpread: Int
    let centerX: Int
    let coverTop: Double

    var innerSlots: Int { max(1, self.configuration.layout.innerSlots) }

    var centerSlot: Int {
        self.innerSlots + max(0, self.configuration.layout.outerSlots)
    }

    var depthTestBounds: (left: Double, right: Double) {
        (self.state(slot: self.centerSlot - 1).x, self.state(slot: self.centerSlot + 1).x)
    }

    func drawDistance(at x: Double) -> Double {
        let centeredLeftEdge = self.centerX - Int(self.coverWidth) / 2
        return abs(x - Double(centeredLeftEdge))
    }

    /// The optional caption frame is measured up from the bottom of the pane.
    init(viewport: CGSize, captionFrame: CGRect?, configuration: CoverFlowConfiguration = .classic)
    {
        let height = Double(viewport.height)
        self.init(
            viewport: viewport,
            captionTop: height - Double(captionFrame?.maxY ?? 0),
            captionBottom: height - Double(captionFrame?.minY ?? 0),
            configuration: configuration)
    }

    init(
        viewport: CGSize, captionTop: Double, captionBottom: Double,
        configuration: CoverFlowConfiguration = .classic
    ) {
        let captionBand = Int(captionBottom) - Int(captionTop)
        let available = Int(captionTop) + captionBand / 3
        let height = max(1, available * 2 / 3)
        let width = Double(height) * Double(viewport.width) / max(1, Double(viewport.height))

        // iTunes 9.0.2 places the reflection seam using whole-point arithmetic.
        let seam = available - (available - height) / 2 - available / 10
        self.init(
            viewport: viewport, coverWidth: width.rounded(.towardZero),
            coverHeight: Double(height),
            coverTop: Double(seam - height), configuration: configuration)
    }

    init(
        viewport: CGSize, coverWidth: Double, coverHeight: Double, coverTop: Double = 0,
        configuration: CoverFlowConfiguration = .classic
    ) {
        self.configuration = configuration
        self.viewport = viewport

        self.coverWidth = coverWidth
        self.coverHeight = coverHeight
        self.coverTop = coverTop

        let layout = configuration.layout

        // Leave at least one point between consecutive slots, even in a narrow pane.
        let maximumInset = max(0, Int(coverWidth) - 1)
        let overlapDivisor = max(1, layout.overlapDivisor)
        let overlap =
            (coverWidth * layout.overlapNumerator).rounded(.towardZero)
            / Double(overlapDivisor)
        let inset = coverHeight * layout.edgeInsetFraction
        self.overlap = Int(min(Double(maximumInset), max(0, overlap)))
        self.edgeInset = Int(min(Double(maximumInset), max(0, inset)))
        self.outerSpread = self.overlap / max(1, layout.outerSpreadDivisor)
        self.centerX = Int(Double(viewport.width) * 0.5)
    }

    var scrollStep: Double {
        let center = self.transform(for: self.state(slot: self.centerSlot))
        let neighbor = self.transform(for: self.state(slot: self.centerSlot + 1))
        let x = self.coverWidth / 2, y = self.coverHeight / 2

        func project(_ matrix: CATransform3D) -> Double {
            (x * Double(matrix.m11) + y * Double(matrix.m21) + Double(matrix.m41))
                / (x * Double(matrix.m14) + y * Double(matrix.m24) + Double(matrix.m44))
        }

        return max(1, abs(project(neighbor) - project(center)))
    }

    func state(slot: Int) -> CoverPose {
        let relative = slot - self.centerSlot
        let distance = abs(relative)
        let direction = relative.signum()
        let angle = -Double(direction) * self.configuration.sideAngle

        let layout = self.configuration.layout
        let width = max(1, Int(self.coverWidth))
        let center = self.centerX - width / 2
        let stride = width - self.overlap
        let inner = self.innerSlots

        let offset =
            distance == 0
            ? 0
            : width - self.edgeInset
                + min(distance - 1, inner) * stride
                + max(0, distance - inner) * (stride + self.outerSpread)

        return CoverPose(
            angle: angle, x: Double(center + direction * offset),
            depth: distance == 0 ? layout.centerDepth : layout.sideDepth)
    }

    func state(relativePosition: Double) -> CoverPose {
        let slot = relativePosition + Double(self.centerSlot)
        let lower = Int(floor(slot))
        let fraction = slot - Double(lower)

        let a = self.state(slot: lower)
        let b = self.state(slot: lower + 1)

        return CoverPose(
            angle: a.angle + (b.angle - a.angle) * fraction,
            x: a.x + (b.x - a.x) * fraction,
            depth: a.depth + (b.depth - a.depth) * fraction)
    }

    /// Opacity follows horizontal distance between slots, whose spacing varies across the pane.
    /// Measure `x` before applying perspective.
    func intensity(at x: Double) -> Double {
        let layout = self.configuration.layout
        let inner = self.innerSlots
        let center = self.centerSlot
        let side = layout.sideIntensity

        let knots: [(Int, Double)] = [
            (center - inner - 1, 0), (center - inner, side / Double(inner)), (center - 1, side),
            (center, 1), (center + 1, side), (center + inner, side / Double(inner)),
            (center + inner + 1, 0),
        ]

        guard x > self.state(slot: center - inner - 1).x else { return 0 }

        for index in 0..<(knots.count - 1) {
            let a = knots[index], b = knots[index + 1]
            let ax = self.state(slot: a.0).x, bx = self.state(slot: b.0).x

            if x <= bx {
                guard bx != ax else { return b.1 }
                return max(0, min(1, a.1 + (b.1 - a.1) * ((x - ax) / (bx - ax))))
            }
        }

        return 0
    }

    private var focal: Double {
        1 / tan(min(179, max(1, self.configuration.fieldOfView)) * .pi / 360)
    }

    private static func validAspectRatio(_ ratio: Double) -> Double {
        ratio.isFinite && ratio > 0 ? ratio : 1
    }

    /// Size the face inside its slot while keeping its bottom at the reflection seam.
    func faceFrame(aspectRatio: Double = 1) -> CGRect {
        let ratio = Self.validAspectRatio(aspectRatio)
        let width = self.coverWidth * min(1, ratio)
        let height = self.coverHeight * min(1, 1 / ratio)
        return CGRect(x: (self.coverWidth - width) / 2, y: 0, width: width, height: height)
    }

    /// Re-express the original normalized vertices, Y rotation, camera translation,
    /// and 50° projection as one Core Animation projective transform. The original
    /// viewport normalizes x and y separately; a generic m34 rotation is not equivalent.
    func transform(for state: CoverPose, faceOrigin: Double = 0) -> CATransform3D {
        let width = max(1, Double(self.viewport.width))
        let height = max(1, Double(self.viewport.height))
        let radians = state.angle * .pi / 180
        let sine = sin(radians), cosine = cos(radians)
        let layout = self.configuration.layout

        let distance = 1 + layout.depthNormalization * state.depth / max(1, layout.depthRange)
        let focal = self.focal
        let pivot = Double(Int(self.coverWidth) / 2)
        let pivotX = 2 * (state.x + pivot) / width - 1
        let pivotToFace = 2 * (faceOrigin - pivot) / width
        let constantW = distance + sine * pivotToFace
        let constantX = pivotX + cosine * pivotToFace
        let constantY =
            1 - 2 * (self.coverTop + self.coverHeight) / height - layout.verticalCameraOffset

        var matrix = CATransform3DIdentity
        matrix.m11 = sine + focal * height / width * cosine
        matrix.m12 = height / width * sine
        matrix.m13 = 0
        matrix.m14 = 2 * sine / width

        matrix.m21 = 0
        matrix.m22 = focal
        matrix.m23 = 0
        matrix.m24 = 0

        matrix.m41 = width / 2 * constantW + focal * height / 2 * constantX
        matrix.m42 = height / 2 * constantW + focal * height / 2 * constantY

        // Reciprocal camera distance preserves ordering after the homogeneous divide.
        matrix.m43 = 1
        matrix.m44 = constantW

        return matrix
    }
}
