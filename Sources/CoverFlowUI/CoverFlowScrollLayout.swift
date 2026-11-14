struct CoverFlowScrollLayout {
    let metrics: CoverFlowLayout
    let count: Int
    let step: Double

    init(metrics: CoverFlowLayout, count: Int) {
        self.metrics = metrics
        self.count = count
        self.step = metrics.scrollStep
    }

    var maximumOffset: Double { self.offset(for: max(0, self.count - 1)) }
    var contentWidth: Double { Double(self.metrics.viewport.width) + self.maximumOffset }

    func offset(for index: Int) -> Double {
        Double(index) * self.step
    }

    func clampedOffset(_ offset: Double) -> Double {
        min(max(0, offset), self.maximumOffset)
    }

    func nearestIndex(at offset: Double) -> Int {
        Int((self.clampedOffset(offset) / self.step).rounded())
    }

    func position(at offset: Double) -> Double {
        let offset = self.clampedOffset(offset)
        let position = offset / self.step
        let nearest = position.rounded()

        // ScrollView can round its resting offset to a backing pixel.
        return abs(offset - nearest * self.step) < 0.75 ? nearest : position
    }
}
