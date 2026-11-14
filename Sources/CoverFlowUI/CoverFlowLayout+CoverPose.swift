import Foundation

extension CoverFlowLayout {
    struct CoverPose: Equatable {
        var angle: Double
        var x: Double  // Left edge in the original unprojected coordinate system.
        var depth: Double

        mutating func advance(
            toward target: CoverPose, elapsed: Double,
            easing: CoverFlowConfiguration.ExponentialEasing = .init()
        ) -> Bool {
            if easing.timeMultiplier == 0 {
                self = target
                return false
            }
            guard elapsed > 0 else { return self != target }

            let previous = self
            let time = elapsed * easing.timeMultiplier
            let angleWeight = pow(easing.angleRetention, time)
            let positionBase =
                abs(self.x - target.x) <= easing.nearPositionThreshold
                ? easing.nearPositionRetention : easing.farPositionRetention
            let positionWeight = pow(positionBase, time)

            self.angle = angleWeight * self.angle + (1 - angleWeight) * target.angle
            self.x = positionWeight * self.x + (1 - positionWeight) * target.x
            self.depth = positionWeight * self.depth + (1 - positionWeight) * target.depth

            // The original checks angle and x, then snaps all three values.
            if self == previous
                || (abs(self.angle - target.angle) <= easing.settleThreshold
                    && abs(self.x - target.x) <= easing.settleThreshold)
            {
                self = target
                return false
            }

            return true
        }
    }
}
