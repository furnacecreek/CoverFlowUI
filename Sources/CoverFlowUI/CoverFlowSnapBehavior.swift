import SwiftUI

struct CoverFlowSnapBehavior: ScrollTargetBehavior {
    let layout: () -> CoverFlowScrollLayout
    var shouldSnap: () -> Bool = { true }
    let offset: () -> Double

    func updateTarget(_ target: inout ScrollTarget, context: TargetContext) {
        // A resize or preset switch already supplies the exact offset. SwiftUI
        // can consult the previous behavior while applying that request.
        guard self.shouldSnap() else { return }

        target.rect.origin.x = self.destination(
            proposed: target.rect.minX, velocity: context.velocity.dx)
    }

    func destination(proposed: Double, velocity: Double) -> Double {
        let scrollLayout = self.layout()
        let step = scrollLayout.step
        let current = scrollLayout.clampedOffset(self.offset())
        var destination = (proposed / step).rounded() * step

        // Keep a moving release going in its original direction.
        if velocity > 0 && destination <= current {
            destination = (floor(current / step) + 1) * step
        } else if velocity < 0 && destination >= current {
            destination = (ceil(current / step) - 1) * step
        }

        return scrollLayout.clampedOffset(destination)
    }
}
