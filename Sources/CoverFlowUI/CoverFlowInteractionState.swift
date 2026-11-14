import Foundation
import Observation

@MainActor
@Observable
final class CoverFlowInteractionState {
    var offset: Double = 0
    var clickStates: [CoverFlowLayout.CoverPose]? { self.clickAnimation?.states }

    @ObservationIgnored
    var scrollLayout: CoverFlowScrollLayout?

    @ObservationIgnored
    var pendingOffset: Double?
    @ObservationIgnored
    var dragOrigin: Double?
    @ObservationIgnored
    var reportedSelectionIndex: Int?
    @ObservationIgnored
    var lastCoverClick: (index: Int, timestamp: TimeInterval)?
    @ObservationIgnored
    var typeSelection: (prefix: String, timestamp: TimeInterval)?

    private var clickAnimation: ClickAnimation?

    private struct ClickAnimation {
        var states: [CoverFlowLayout.CoverPose]
        let targets: [CoverFlowLayout.CoverPose]
        let easing: CoverFlowConfiguration.ExponentialEasing

        // iTunes 9.0.2 starts the easing with a 33 ms frame estimate.
        var elapsed: Double = 0.033
        var timestamp: TimeInterval?
    }

    func clearInputHistory() {
        self.lastCoverClick = nil
        self.typeSelection = nil
    }

    func cancelClick() {
        guard self.clickAnimation != nil else { return }
        self.clickAnimation = nil
    }

    func animateClick(
        from states: [CoverFlowLayout.CoverPose], to targets: [CoverFlowLayout.CoverPose],
        animation: CoverFlowConfiguration.ExponentialEasing
    ) {
        guard states != targets else {
            self.cancelClick()
            return
        }
        self.clickAnimation = ClickAnimation(states: states, targets: targets, easing: animation)
    }

    func advanceClick(at timestamp: TimeInterval) {
        guard var animation = self.clickAnimation else { return }
        if let previous = animation.timestamp {
            guard timestamp > previous else { return }
            animation.elapsed = (7 * animation.elapsed + (timestamp - previous)) / 8
        }
        animation.timestamp = timestamp

        var moving = false
        for index in animation.states.indices {
            if animation.states[index].advance(
                toward: animation.targets[index],
                elapsed: animation.elapsed,
                easing: animation.easing
            ) {
                moving = true
            }
        }

        self.clickAnimation = moving ? animation : nil
    }

    func geometry(in layout: CoverFlowScrollLayout) -> CoverFlowGeometry {
        if let states = self.clickStates, states.count == layout.count {
            return CoverFlowGeometry(metrics: layout.metrics, states: states)
        }
        return CoverFlowGeometry(
            metrics: layout.metrics, count: layout.count, position: layout.position(at: self.offset)
        )
    }
}
