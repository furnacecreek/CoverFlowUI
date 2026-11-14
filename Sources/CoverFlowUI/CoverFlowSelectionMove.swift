enum CoverFlowSelectionMove {
    case absolute(Int)
    case relative(Int)
    case page(forward: Bool, outerSlots: Int)

    func destination(from index: Int?, count: Int) -> Int? {
        guard let index, count > 0 else { return nil }
        let last = count - 1
        let offset: Int

        switch self {
        case .absolute(let destination):
            return min(max(0, destination), last)
        case .relative(let step):
            offset = step
        case .page(let forward, let outerSlots):
            let step = 1 + 2 * min(max(0, outerSlots), last / 2)
            offset = forward ? step : -step
        }

        return index + min(max(-index, offset), last - index)
    }
}
