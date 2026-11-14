import CoreGraphics
import QuartzCore
import Testing
@testable import CoverFlowUI

struct CoverFlowUITests {
    @Test
    func projection() {
        for viewport in [CGSize(width: 1120, height: 583), CGSize(width: 720, height: 403)] {
            let m = CoverFlowLayout(
                viewport: viewport, captionFrame: CGRect(x: 0, y: 32, width: 0, height: 32))

            for position: Double in [-6, -1, -0.25, 0, 0.25, 1, 6] {
                let state = m.state(relativePosition: position)
                let matrix = m.transform(for: state)
                let projection = CoverFlowGeometry.projection(
                    matrix, height: m.coverHeight, viewportHeight: viewport.height)

                func originalPoint(x: Double, y: Double) -> CGPoint {
                    let w = x * matrix.m14 + y * matrix.m24 + matrix.m44
                    return CGPoint(
                        x: (x * matrix.m11 + y * matrix.m21 + matrix.m41) / w,
                        y: (x * matrix.m12 + y * matrix.m22 + matrix.m42) / w)
                }

                for y in [-m.coverHeight, 0, m.coverHeight] {
                    for x in [0, m.coverWidth] {
                        let point = originalPoint(x: x, y: y)
                        let port = CGPoint(x: x, y: m.coverHeight - y).applying(projection)
                        #expect(
                            abs(point.x - port.x) < 1e-8
                                && abs(viewport.height - point.y - port.y) < 1e-8)
                    }
                }
            }
        }
    }

    @Test
    func drawOrderUsesFractionalDistanceAndBreaksTiesByItemOrder() {
        let metrics = CoverFlowLayout(
            viewport: CGSize(width: 801, height: 451), coverWidth: 301, coverHeight: 150)
        let center = metrics.state(slot: metrics.centerSlot).x
        let states = [0.25, -0.75, 0.75, 0].map { offset in
            CoverFlowLayout.CoverPose(angle: 0, x: center + Double(offset), depth: 30)
        }
        let planes = CoverFlowGeometry(metrics: metrics, states: states).planes()

        #expect(planes.map(\.itemIndex) == [1, 2, 0, 3])
        #expect(planes.map(\.drawDistance) == [0.75, 0.75, 0.25, 0])
    }

    @Test
    func depthClipping() {
        let viewport = CGSize(width: 801, height: 451)
        let metrics = CoverFlowLayout(
            viewport: viewport, coverWidth: 300, coverHeight: 150, coverTop: 50)

        func planes(_ states: [CoverFlowLayout.CoverPose]) -> [CoverFlowPlane] {
            CoverFlowGeometry(metrics: metrics, states: states)
                .planes(aspectRatio: { _ in 1 })
        }

        let center = metrics.state(slot: metrics.centerSlot).x
        let inner = planes([
            .init(angle: 0, x: center + 0.75, depth: 30),
            .init(angle: 0, x: center + 0.5, depth: 60),
        ])

        let centerPoint = inner[1].faceSilhouette.boundingBoxOfPath
        let covered = CGPoint(x: centerPoint.midX, y: centerPoint.midY)

        #expect(
            inner[0].faceSilhouette.contains(covered) && inner[1].clip?.contains(covered) == false)

        let boundary = metrics.depthTestBounds.right
        let outer = planes([
            .init(angle: 0, x: boundary + 15, depth: 30),
            .init(angle: 0, x: boundary, depth: 60),
        ])

        #expect(
            outer.map(\.itemIndex) == [0, 1] && outer[0].usesUnconditionalDepth
                && outer[1].usesUnconditionalDepth && outer[1].clip == nil
                && outer[0].faceSilhouette.boundingBoxOfPath.intersects(
                    outer[1].faceSilhouette.boundingBoxOfPath)
        )

        let crossing = planes([
            .init(angle: 0, x: boundary + 15, depth: 10),
            .init(angle: 0, x: boundary, depth: 100),
            .init(angle: 0, x: boundary - 3, depth: 60),
        ])
        let overlap = crossing.map { $0.faceSilhouette.boundingBoxOfPath }.reduce(
            CGRect(origin: .zero, size: viewport)
        ) {
            $0.intersection($1)
        }

        #expect(!overlap.isEmpty)

        let sample = CGPoint(x: overlap.midX, y: overlap.midY)
        let source = CoverFlowPlane.DepthSurface(
            shape: crossing[0].silhouette, projection: crossing[0].projection)
        let target = CoverFlowPlane.DepthSurface(
            shape: crossing[2].silhouette, projection: crossing[2].projection)

        #expect(
            source.occlusion(of: target, in: CGRect(origin: .zero, size: viewport))?
                .contains(sample) == true && crossing[2].clip?.contains(sample) != false)
    }

    @Test(arguments: [false, true])
    func clicksPassThroughReflections(nearCoverDrawsLast: Bool) throws {
        let metrics = CoverFlowLayout(
            viewport: CGSize(width: 801, height: 451), coverWidth: 300, coverHeight: 150)
        let center = metrics.state(slot: metrics.centerSlot).x
        let near = CoverFlowLayout.CoverPose(
            angle: 0, x: center + (nearCoverDrawsLast ? 0 : 10), depth: 30)
        let far = CoverFlowLayout.CoverPose(
            angle: 0, x: center + (nearCoverDrawsLast ? 10 : 0), depth: 60)
        let geometry = CoverFlowGeometry(metrics: metrics, states: [near, far])
        let planes = geometry.planes()
        let nearPlane = try #require(planes.first { $0.itemIndex == 0 })
        let farPlane = try #require(planes.first { $0.itemIndex == 1 })

        let overlap = nearPlane.reflectionSilhouette.boundingBoxOfPath.intersection(
            farPlane.faceSilhouette.boundingBoxOfPath)
        let throughReflection = CGPoint(x: overlap.midX, y: overlap.midY)
        try #require(nearPlane.reflectionSilhouette.contains(throughReflection))
        try #require(farPlane.faceSilhouette.contains(throughReflection))
        #expect(geometry.coverIndex(at: throughReflection) == 1)

        let reflectionOnly = CGPoint(x: 150, y: 225).applying(nearPlane.projection)
        try #require(nearPlane.reflectionSilhouette.contains(reflectionOnly))
        try #require(!farPlane.faceSilhouette.contains(reflectionOnly))
        #expect(geometry.coverIndex(at: reflectionOnly) == nil)

        let faceOverlap = nearPlane.faceSilhouette.boundingBoxOfPath.intersection(
            farPlane.faceSilhouette.boundingBoxOfPath)
        let onBothFaces = CGPoint(x: faceOverlap.midX, y: faceOverlap.midY)
        #expect(geometry.coverIndex(at: onBothFaces) == 0)
    }

    @Test
    func cameraClipping() {
        let viewport = CGSize(width: 800, height: 480)
        let metrics = CoverFlowLayout(
            viewport: viewport, coverWidth: 600, coverHeight: 200, coverTop: 24)

        let center = metrics.state(slot: metrics.centerSlot).x
        let states: [CoverFlowLayout.CoverPose] = [
            .init(angle: 0, x: center, depth: -20),
            .init(angle: 60, x: center, depth: 0),
            .init(angle: 60, x: center, depth: 1_000),
            .init(angle: 0, x: center, depth: 1_500),
            .init(angle: 0, x: center, depth: 1_000.002),
        ]

        let geometry = CoverFlowGeometry(metrics: metrics, states: states)
        let planes = geometry.planes(aspectRatio: { _ in 1 })

        #expect(Set(planes.map(\.itemIndex)) == [1, 2])

        let near = planes.first { $0.itemIndex == 1 }!
        let far = planes.first { $0.itemIndex == 2 }!
        let nearMatrix = metrics.transform(for: states[1])
        let farMatrix = metrics.transform(for: states[2])

        #expect(
            abs(nearMatrix.m44 + nearMatrix.m14 * near.xRange.lowerBound - 0.9999989867210388)
                < 1e-12 && abs(farMatrix.m44 + farMatrix.m14 * far.xRange.upperBound - 20) < 1e-12
                && near.xRange.upperBound == 600 && far.xRange.lowerBound == 0)
    }

    @Test
    func rectangularCovers() {
        let viewport = CGSize(width: 801, height: 451)
        let metrics = CoverFlowLayout(
            viewport: viewport, coverWidth: 470.635, coverHeight: 265, coverTop: 24)

        let center = metrics.state(slot: metrics.centerSlot)
        let geometry = CoverFlowGeometry(metrics: metrics, states: [center])
        let expected: [(Double, CGSize)] = [
            (1, CGSize(width: 470.635, height: 265)),
            (0.5, CGSize(width: 235.3175, height: 265)),
            (2, CGSize(width: 470.635, height: 132.5)),
        ]
        let slot = CoverFlowGeometry.projection(
            metrics.transform(for: center), height: 265, viewportHeight: viewport.height)
        let slotSeam = CGPoint(x: 470.635 / 2, y: 265).applying(slot)

        for (ratio, size) in expected {
            let plane = geometry.planes(aspectRatio: { _ in ratio })[0]
            let seam = CGPoint(x: size.width / 2, y: size.height).applying(plane.projection)

            #expect(
                plane.size == size && abs(seam.x - slotSeam.x) < 1e-8
                    && abs(seam.y - slotSeam.y) < 1e-8)
        }
    }

    @Test
    func snowLeopardWidthRounding() {
        let wide = CGSize(width: 807, height: 583)
        let metrics = CoverFlowLayout(viewport: wide, captionTop: 501, captionBottom: 533)

        #expect(metrics.coverWidth == 470)
        #expect(metrics.overlap == 402)
    }

    @Test
    func widthTruncatesAfterDoublePrecisionCalculation() {
        let metrics = CoverFlowLayout(
            viewport: CGSize(width: 6333, height: 5380), captionTop: 4885, captionBottom: 4917)

        #expect(metrics.coverHeight == 3263)
        #expect(metrics.coverWidth == 3840)
    }

    @Test
    func projectedCenterCoverHeight() {
        let viewport = CGSize(width: 1000, height: 602)
        let caption = CGRect(x: 0, y: 40, width: 0, height: 32)
        var configuration = CoverFlowConfiguration.classic
        for angle in [50.0, 65.0] {
            configuration.fieldOfView = angle
            let metrics = CoverFlowLayout(
                viewport: viewport, captionFrame: caption, configuration: configuration)
            let center = metrics.state(slot: metrics.centerSlot)
            let projection = CoverFlowGeometry.projection(
                metrics.transform(for: center), height: metrics.coverHeight,
                viewportHeight: viewport.height)
            let top = CGPoint.zero.applying(projection)
            let bottom = CGPoint(x: 0, y: metrics.coverHeight).applying(projection)
            let height = configuration.projectedCenterCoverHeight(
                in: viewport, captionFrame: caption)

            #expect(abs(height - (bottom.y - top.y)) < 1e-8)
            #expect(configuration.projectedCenterCoverHeight(in: viewport) > height)
        }
    }

    @Test
    func snowLeopardCaptionClearanceGrowsWithPaneHeight() throws {
        // Two 16-point lines, plus one reserved line above the visible caption.
        let caption = CGRect(x: 0, y: 45, width: 0, height: 32)
        let reservedFrame = CGRect(x: 0, y: 45, width: 0, height: 48)
        let fixtures: [(CGFloat, CGFloat)] = [(300, 4.70), (500, 7.72), (800, 12.93)]

        for (paneHeight, expectedGap) in fixtures {
            let viewport = CGSize(width: 940, height: paneHeight)
            let metrics = CoverFlowLayout(viewport: viewport, captionFrame: reservedFrame)
            let plane = try #require(
                CoverFlowGeometry(metrics: metrics, count: 1, position: 0).planes().first)
            let gap = paneHeight - caption.maxY - plane.faceSilhouette.boundingBoxOfPath.maxY
            #expect(abs(gap - expectedGap) < 0.01)
        }
    }

    @Test
    func snowLeopardLibraryLayout() {
        let viewport = CGSize(width: 1120, height: 583)
        let caption = CGRect(x: 0, y: 32, width: 0, height: 32)
        let metrics = CoverFlowLayout(viewport: viewport, captionFrame: caption)

        #expect(metrics.coverHeight == 352)
        #expect(metrics.coverWidth == 676)
        #expect(metrics.overlap == 579)
        #expect(metrics.edgeInset == 88)
        #expect(metrics.outerSpread == 144)
        #expect(metrics.coverTop + metrics.coverHeight == 389)
    }

    @Test
    func snowLeopardProjectedCorners() {
        // Top, seam and reflection bottom, each from left to right.
        // iTunes 9.0.2 uses an integer half-width in its camera setup at 0x546ab0.
        let fixtures: [(Double, [[(Double, Double)]])] = [
            (
                1120,
                [
                    [
                        (37.501, 46.802), (384.342, 142.874), (37.501, 513.550), (384.342, 426.370),
                        (37.501, 980.297), (384.342, 709.866),
                    ],
                    [
                        (319.677, 39.432), (800.323, 39.432), (319.677, 520.238),
                        (800.323, 520.238),
                        (319.677, 1001.045), (800.323, 1001.045),
                    ],
                    [
                        (735.658, 142.874), (1082.499, 46.802), (735.658, 426.370),
                        (1082.499, 513.550),
                        (735.658, 709.866), (1082.499, 980.297),
                    ],
                ]
            ),
            (
                721,
                [
                    [
                        (-127.993, 47.016), (205.238, 142.929), (-127.993, 513.356),
                        (205.238, 426.320),
                        (-127.993, 979.696), (205.238, 709.710),
                    ],
                    [
                        (120.274, 39.432), (600.726, 39.432), (120.274, 520.238),
                        (600.726, 520.238),
                        (120.274, 1001.045), (600.726, 1001.045),
                    ],
                    [
                        (515.576, 142.795), (849.183, 46.652), (515.576, 426.441),
                        (849.183, 513.686),
                        (515.576, 710.087), (849.183, 980.719),
                    ],
                ]
            ),
        ]
        for (width, slots) in fixtures {
            let metrics = CoverFlowLayout(
                viewport: CGSize(width: width, height: 583),
                captionFrame: CGRect(x: 0, y: 32, width: 0, height: 32))
            let corners = [Double(0), metrics.coverHeight, 2 * metrics.coverHeight].flatMap {
                y in
                [CGPoint(x: 0, y: y), CGPoint(x: metrics.coverWidth, y: y)]
            }
            for (offset, expected) in slots.enumerated() {
                let state = metrics.state(slot: metrics.centerSlot + offset - 1)
                let projection = CoverFlowGeometry.projection(
                    metrics.transform(for: state), height: metrics.coverHeight,
                    viewportHeight: metrics.viewport.height)
                for (corner, reference) in zip(corners, expected) {
                    let projected = corner.applying(projection)
                    #expect(abs(projected.x - reference.0) < 0.001)
                    #expect(abs(projected.y - reference.1) < 0.001)
                }
            }
        }
    }

    @Test
    func narrowAndZeroSizePanes() {
        for width in [0.0, 0.5, 90, 120, 240] {
            let metrics = CoverFlowLayout(
                viewport: CGSize(width: width, height: 500), captionFrame: nil)
            let slots = (-10...10).map { metrics.state(slot: metrics.centerSlot + $0).x }
            #expect(zip(slots, slots.dropFirst()).allSatisfy { $1 - $0 >= 1 })
            #expect(metrics.intensity(at: slots[10]) == 1)
            if width == 0 {
                let geometry = CoverFlowGeometry(metrics: metrics, count: 13, position: 6)
                #expect(geometry.planes().isEmpty)
            }
        }
        let collapsed = CoverFlowLayout(viewport: CGSize(width: 120, height: 0), captionFrame: nil)
        #expect(CoverFlowGeometry(metrics: collapsed, count: 13, position: 6).planes().isEmpty)
    }

    @Test
    func instantAndStalledAnimationsReachTheirTarget() {
        let start = CoverFlowLayout.CoverPose(angle: 60, x: 20, depth: 60)
        let target = CoverFlowLayout.CoverPose(angle: 0, x: 120, depth: 30)
        for multiplier in [Double(0), .leastNonzeroMagnitude] {
            var state = start
            var easing = CoverFlowConfiguration.classic.clickAnimation
            easing.timeMultiplier = multiplier
            let moving = state.advance(toward: target, elapsed: 0.001, easing: easing)
            #expect(!moving && state == target)
        }
    }

    @Test
    func easingUsesDifferentRetentionNearTheTarget() {
        var easing = CoverFlowConfiguration.ExponentialEasing()
        easing.timeMultiplier = 8
        easing.angleRetention = 0.25
        easing.farPositionRetention = 0.5625
        easing.nearPositionRetention = 0.25
        easing.nearPositionThreshold = 6

        var state = CoverFlowLayout.CoverPose(angle: 32, x: 0, depth: 64)
        let target = CoverFlowLayout.CoverPose(angle: 0, x: 8, depth: 0)

        // A sixteenth of a second gives a half exponent, taking the square root of each retention.
        let movedFar = state.advance(toward: target, elapsed: 0.0625, easing: easing)
        #expect(movedFar)
        #expect(state == .init(angle: 16, x: 2, depth: 48))

        let movedNear = state.advance(toward: target, elapsed: 0.0625, easing: easing)
        #expect(movedNear)
        #expect(state == .init(angle: 8, x: 5, depth: 24))
    }

    @Test
    @MainActor
    func snowLeopardSelectionEasing() throws {
        let start = CoverFlowLayout.CoverPose(angle: 60, x: 20, depth: 60)
        let target = CoverFlowLayout.CoverPose(angle: 0, x: 120, depth: 30)
        // Reference frames from the 33 ms seed and smoothing at 0x5472b4.
        let fixtures: [(Double, CoverFlowLayout.CoverPose, Int)] = [
            (60, .init(angle: 5.640561, x: 80.162049, depth: 41.951385), 35),
            (120, .init(angle: 6.767541, x: 77.234773, depth: 42.829568), 63),
        ]

        for (rate, expected, settleFrame) in fixtures {
            let interaction = CoverFlowInteractionState()
            interaction.animateClick(from: [start], to: [target], animation: .init())
            for frame in 0..<settleFrame {
                interaction.advanceClick(at: 1 + Double(frame) / rate)
                let state = try #require(interaction.clickStates?.first)
                if frame == 5 {
                    #expect(abs(state.angle - expected.angle) < 0.0001)
                    #expect(abs(state.x - expected.x) < 0.0001)
                    #expect(abs(state.depth - expected.depth) < 0.0001)
                }
            }
            interaction.advanceClick(at: 1 + Double(settleFrame) / rate)
            #expect(interaction.clickStates == nil)
        }
    }

    @Test
    func scrollOffsetConversion() {
        let metrics = CoverFlowLayout(
            viewport: CGSize(width: 1120, height: 583.2578125), captionFrame: nil)
        let layout = CoverFlowScrollLayout(metrics: metrics, count: 13)
        let center = layout.offset(for: 6)
        let between = center + layout.step / 4

        #expect(layout.position(at: -layout.step) == 0)
        #expect(layout.position(at: center - 0.5) == 6)
        #expect(layout.position(at: center + 0.5) == 6)
        #expect(abs(layout.position(at: between) - 6.25) < 1e-8)
        #expect(layout.nearestIndex(at: between) == 6)
        #expect(layout.nearestIndex(at: center + 0.75 * layout.step) == 7)
        #expect(layout.position(at: layout.maximumOffset + layout.step) == 12)
    }

    @Test
    func keyboardPagingUsesOuterSlotsAndClampsAtEnds() {
        let outerSlots = CoverFlowConfiguration.classic.layout.outerSlots
        let forward = CoverFlowSelectionMove.page(forward: true, outerSlots: outerSlots)
        let backward = CoverFlowSelectionMove.page(forward: false, outerSlots: outerSlots)
        let custom = CoverFlowSelectionMove.page(forward: true, outerSlots: 2)

        #expect(forward.destination(from: 5, count: 21) == 16)
        #expect(forward.destination(from: 16, count: 21) == 20)
        #expect(backward.destination(from: 20, count: 21) == 9)
        #expect(backward.destination(from: 9, count: 21) == 0)
        #expect(custom.destination(from: 0, count: 21) == 5)
        #expect(forward.destination(from: nil, count: 0) == nil)
    }

    @Test
    func scrollSnapRespectsDirectionAndBounds() {
        let metrics = CoverFlowLayout(
            viewport: CGSize(width: 1120, height: 583), captionFrame: nil)
        let layout = CoverFlowScrollLayout(metrics: metrics, count: 13)
        let pitch = layout.step
        let target = CoverFlowSnapBehavior(layout: { layout }, offset: { 6.2 * pitch })

        #expect(target.destination(proposed: 6.3 * pitch, velocity: 20) == 7 * pitch)
        #expect(target.destination(proposed: 6.3 * pitch, velocity: -20) == 6 * pitch)
        #expect(target.destination(proposed: 6.8 * pitch, velocity: -20) == 6 * pitch)
        #expect(target.destination(proposed: 7.6 * pitch, velocity: 0) == 8 * pitch)
        #expect(target.destination(proposed: -pitch, velocity: -20) == 0)
        #expect(target.destination(proposed: 13 * pitch, velocity: 20) == layout.maximumOffset)
    }

    @Test
    func windowedGeometryMatchesExhaustiveGeometry() {
        let count = 100
        for viewport in [CGSize(width: 1120, height: 583), CGSize(width: 120, height: 500)] {
            let metrics = CoverFlowLayout(viewport: viewport, captionFrame: nil)
            for position: Double in [0, 0.25, 8.75, 49, 50.49, 90, 98.99, 99] {
                let window = CoverFlowGeometry(metrics: metrics, count: count, position: position)
                let exhaustive = CoverFlowGeometry(
                    metrics: metrics,
                    states: CoverFlowGeometry.states(
                        count: count, position: position, metrics: metrics))
                let actual = window.planes()
                let expected = exhaustive.planes()
                #expect(window.states.count <= 2 * (metrics.innerSlots + 1) + 1)
                #expect(actual.map(\.itemIndex) == expected.map(\.itemIndex))
                #expect(actual.map(\.projection) == expected.map(\.projection))
                #expect(actual.map(\.clip) == expected.map(\.clip))
            }
        }
    }
}
