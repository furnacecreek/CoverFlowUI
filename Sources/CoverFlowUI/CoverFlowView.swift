import AppKit
import SwiftUI

/// A macOS Cover Flow pane with perspective, reflections, and native scrolling.
///
/// Selection holds an item's unique ID or tag and follows that item across reordering.
/// Missing selections use the first item; empty collections use nil.
/// Supply a bounded frame for the pane.
@MainActor
public struct CoverFlowView<Item, ID: Hashable, Content: View>: View {
    let items: [Item]
    let id: KeyPath<Item, ID>
    @Binding var selection: ID?

    var configuration: CoverFlowConfiguration
    private let captionFrame: CGRect?
    private var caption: CaptionOptions?
    private var activationAction: ((Item) -> Void)?
    private var searchKey: ((Item) -> String)?
    let content: (Item) -> Content

    @State private var scrollPosition = ScrollPosition()
    @State private var interaction = CoverFlowInteractionState()
    @State private var captionHeight: Double = 0

    /// Creates a pane whose covers are supplied by a SwiftUI view builder.
    ///
    /// - Parameters:
    ///   - items: The items in display order.
    ///   - id: A key path to a unique, stable ID or tag for each item.
    ///   - selection: The centered item's ID; changes work in both directions.
    ///   - configuration: Projection and animation settings. Defaults to the classic preset.
    ///   - captionFrame: Bounds for a caption drawn by the parent, measured up from the bottom
    ///     of the pane. Use ``caption(bottomPadding:_:)`` to have the pane measure its own caption.
    ///   - content: The image or custom view to display for each item.
    public init(
        items: [Item],
        id: KeyPath<Item, ID>,
        selection: Binding<ID?>,
        configuration: CoverFlowConfiguration = .classic,
        captionFrame: CGRect? = nil,
        @ViewBuilder content: @escaping (Item) -> Content
    ) {
        self.items = items
        self.id = id
        self._selection = selection
        self.configuration = configuration
        self.captionFrame = captionFrame
        self.content = content
    }

    /// Draws and measures a bottom-aligned caption for the selected item.
    ///
    /// The caption defaults to a 45-point bottom inset. Cover layout reserves an extra
    /// 16-point line above the caption, so the projected gap varies with the pane height.
    /// The builder runs only when the collection has an item. The measured caption takes precedence
    /// over any `captionFrame` supplied to the initializer.
    public func caption<Caption: View>(
        bottomPadding: Double = 45,
        @ViewBuilder _ content: @escaping (Item) -> Caption
    ) -> Self {
        var view = self
        view.caption = CaptionOptions(bottomPadding: bottomPadding) { AnyView(content($0)) }
        return view
    }

    /// Handles Return on the selected cover and a second click on the same selected cover.
    public func onItemTapped(_ action: @escaping (Item) -> Void) -> Self {
        var view = self
        view.activationAction = action
        return view
    }

    /// Selects the first item whose search string starts with the typed text when the pane has focus.
    /// The closure supplies one search string per item.
    public func typeToSelect(_ searchKey: @escaping (Item) -> String) -> Self {
        var view = self
        view.searchKey = searchKey
        return view
    }

    public var body: some View {
        GeometryReader { geometry in
            let captionFrame = self.resolvedCaptionFrame
            let metrics = CoverFlowLayout(
                viewport: geometry.size,
                captionFrame: captionFrame,
                configuration: self.configuration
            )
            let layout = CoverFlowScrollLayout(metrics: metrics, count: self.items.count)
            let inputs = LayoutInputs(
                viewport: geometry.size,
                ids: self.items.map { $0[keyPath: self.id] },
                configuration: self.configuration,
                captionFrame: captionFrame
            )

            self.scrollView(in: layout, inputs: inputs)
                .overlay(alignment: .bottom) {
                    self.measuredCaption
                }
        }
        .focusable(!self.items.isEmpty)
        .focusEffectDisabled()
        .onKeyPress(.leftArrow) { self.moveSelection(.relative(-1)) }
        .onKeyPress(.rightArrow) { self.moveSelection(.relative(1)) }
        .onKeyPress(.home) { self.moveSelection(.absolute(0)) }
        .onKeyPress(.end) { self.moveSelection(.absolute(self.items.count - 1)) }
        .onKeyPress(.pageUp) { self.pageSelection(forward: false) }
        .onKeyPress(.pageDown) { self.pageSelection(forward: true) }
        .onKeyPress(.return, action: self.activateSelection)
        .onKeyPress(
            characters: .alphanumerics.union(.punctuationCharacters).union(.whitespaces),
            phases: .down,
            action: self.handleTyping
        )
    }

    @ViewBuilder
    private var measuredCaption: some View {
        if let caption = self.caption {
            VStack(spacing: 0) {
                if let index = self.selectedIndex {
                    caption.content(self.items[index])
                }
            }
            .onGeometryChange(for: Double.self, of: { Double($0.size.height) }) { height in
                self.captionHeight = height
            }
            .padding(.bottom, caption.bottomPadding)
        }
    }

    private var resolvedCaptionFrame: CGRect? {
        guard let caption = self.caption else { return self.captionFrame }
        guard self.captionHeight > 0 else { return nil }
        // iTunes extends the caption's bounds upward by one line before sizing the covers.
        return CGRect(x: 0, y: caption.bottomPadding, width: 0, height: self.captionHeight + 16)
    }

    private struct CaptionOptions {
        let bottomPadding: Double
        let content: (Item) -> AnyView
    }
}

extension CoverFlowView where Item: Identifiable, ID == Item.ID {
    /// Creates a pane using each item's Identifiable ID for selection.
    public init(
        items: [Item],
        selection: Binding<ID?>,
        configuration: CoverFlowConfiguration = .classic,
        captionFrame: CGRect? = nil,
        @ViewBuilder content: @escaping (Item) -> Content
    ) {
        self.init(
            items: items, id: \.id, selection: selection, configuration: configuration,
            captionFrame: captionFrame, content: content
        )
    }
}

// MARK: - Scroll and selection

private extension CoverFlowView {
    func scrollView(in layout: CoverFlowScrollLayout, inputs: LayoutInputs) -> some View {
        ScrollView(.horizontal) {
            // The scroll view supplies native motion. The overlay draws the covers in the viewport.
            Color.clear
                .frame(width: layout.contentWidth, height: layout.metrics.viewport.height)
        }
        .scrollIndicators(.never)
        .scrollBounceBehavior(self.items.isEmpty ? .basedOnSize : .always, axes: .horizontal)
        .coverFlowScrollEdges()
        .scrollPosition(self.$scrollPosition)
        .scrollTargetBehavior(
            CoverFlowSnapBehavior(
                layout: { self.interaction.scrollLayout ?? layout },
                shouldSnap: { self.interaction.pendingOffset == nil },
                offset: { self.interaction.offset }
            )
        )
        .onScrollGeometryChange(for: ScrollSample.self, of: ScrollSample.init) { _, sample in
            self.scrollGeometryChanged(sample, in: layout)
        }
        .onScrollPhaseChange { _, phase in
            self.scrollPhaseChanged(to: phase)
        }
        .onChange(of: inputs, initial: true) { previous, current in
            self.layoutChanged(in: layout, itemsChanged: previous.ids != current.ids)
        }
        .onChange(of: self.selection) { _, requested in
            self.selectionChanged(to: requested, in: layout)
        }
        .overlay {
            CoverFlowCoversView(
                items: self.items,
                id: self.id,
                layout: layout,
                interaction: self.interaction,
                content: self.content
            )
            .allowsHitTesting(false)
        }
        .onDisappear {
            self.interaction.cancelClick()
            self.interaction.clearInputHistory()
        }
        .clipped()
        .contentShape(Rectangle())
        .gesture(self.browseGesture(in: layout))
        .allowsHitTesting(!self.items.isEmpty)
    }

    func scrollGeometryChanged(_ sample: ScrollSample, in layout: CoverFlowScrollLayout) {
        guard let activeLayout = self.interaction.scrollLayout,
            sample.matches(activeLayout),
            activeLayout.contentWidth == layout.contentWidth,
            activeLayout.count == layout.count,
            self.interaction.dragOrigin == nil
        else { return }

        if let pending = self.interaction.pendingOffset {
            // A new caption height can resize the scroll content after a scroll request.
            // Retry if the updated geometry hasn't reached the requested offset.
            if abs(sample.offset - pending) <= 1 {
                self.interaction.pendingOffset = nil
            } else {
                self.scrollPosition.scrollTo(x: pending)
            }
            return
        }

        guard self.interaction.clickStates == nil else { return }
        self.interaction.offset = sample.offset
        self.updateSelection(at: sample.offset, in: layout)
    }

    func scrollPhaseChanged(to phase: ScrollPhase) {
        if (phase == .interacting || phase == .tracking), self.interaction.dragOrigin == nil {
            self.interaction.pendingOffset = nil
            self.interaction.cancelClick()
        }
    }

    func layoutChanged(in layout: CoverFlowScrollLayout, itemsChanged: Bool) {
        self.interaction.cancelClick()
        if itemsChanged {
            self.interaction.clearInputHistory()
        }
        self.interaction.scrollLayout = layout
        self.synchronizeSelectionAndScroll(to: self.selectedIndex, in: layout)
    }

    func selectionChanged(to requested: ID?, in layout: CoverFlowScrollLayout) {
        if let click = self.interaction.lastCoverClick,
            !self.items.indices.contains(click.index)
                || requested != self.items[click.index][keyPath: self.id]
        {
            self.interaction.lastCoverClick = nil
        }

        guard let index = self.selectedIndex else {
            self.reportSelection(at: nil)
            return
        }
        guard
            index != self.interaction.reportedSelectionIndex
                || requested != self.items[index][keyPath: self.id]
        else {
            return
        }

        self.animateSelection(to: index, in: layout)
    }

    var selectedIndex: Int? {
        self.items.firstIndex { $0[keyPath: self.id] == self.selection } ?? self.items.indices.first
    }

    func reportSelection(at index: Int?) {
        self.interaction.reportedSelectionIndex = index
        let itemID = index.map { self.items[$0][keyPath: self.id] }
        if self.selection != itemID { self.selection = itemID }
    }

    func updateSelection(at offset: Double, in layout: CoverFlowScrollLayout) {
        let index = layout.nearestIndex(at: offset)
        if index != self.interaction.reportedSelectionIndex {
            self.interaction.lastCoverClick = nil
        }
        self.reportSelection(at: self.items.isEmpty ? nil : index)
    }

    func animateSelection(to index: Int, in layout: CoverFlowScrollLayout) {
        let metrics = layout.metrics
        let easing = metrics.configuration.clickAnimation
        if easing.timeMultiplier > 0, metrics.viewport.width > 0, metrics.viewport.height > 0 {
            let states =
                self.interaction.clickStates
                ?? CoverFlowGeometry.states(
                    count: layout.count, position: layout.position(at: self.interaction.offset),
                    metrics: metrics)
            let targets = CoverFlowGeometry.states(
                count: layout.count, position: Double(index), metrics: metrics)
            self.interaction.animateClick(from: states, to: targets, animation: easing)
        } else {
            self.interaction.cancelClick()
        }

        self.synchronizeSelectionAndScroll(to: index, in: layout)
    }

    func synchronizeSelectionAndScroll(to index: Int?, in layout: CoverFlowScrollLayout) {
        let target = layout.offset(for: index ?? 0)
        if self.interaction.offset != target || self.interaction.dragOrigin != nil {
            self.interaction.pendingOffset = target
        }
        self.interaction.dragOrigin = nil
        self.interaction.offset = target
        self.reportSelection(at: index)
        self.scrollPosition.scrollTo(x: target)
    }

    struct LayoutInputs: Equatable {
        let viewport: CGSize
        let ids: [ID]
        let configuration: CoverFlowConfiguration
        let captionFrame: CGRect?
    }

    struct ScrollSample: Equatable {
        let offset: Double
        let viewport: CGSize
        let contentWidth: Double

        init(_ geometry: ScrollGeometry) {
            self.offset = geometry.contentOffset.x
            self.viewport = geometry.containerSize
            self.contentWidth = geometry.contentSize.width
        }

        func matches(_ layout: CoverFlowScrollLayout) -> Bool {
            abs(self.viewport.width - layout.metrics.viewport.width) < 1
                && abs(self.viewport.height - layout.metrics.viewport.height) < 1
                && abs(self.contentWidth - layout.contentWidth) < 1
        }
    }
}

// MARK: - Mouse gestures

extension CoverFlowView {
    private func browseGesture(in layout: CoverFlowScrollLayout) -> some Gesture {
        let click = SpatialTapGesture().onEnded { tap in
            self.selectCover(at: tap.location, in: layout)
        }

        return DragGesture(minimumDistance: 3)
            .onChanged { drag in
                self.dragChanged(drag, in: layout)
            }
            .onEnded { drag in
                self.dragEnded(drag, in: layout)
            }
            .exclusively(before: click)
    }

    private func dragChanged(_ drag: DragGesture.Value, in layout: CoverFlowScrollLayout) {
        let origin = self.interaction.dragOrigin ?? layout.clampedOffset(self.interaction.offset)
        self.interaction.dragOrigin = origin
        self.interaction.lastCoverClick = nil
        self.interaction.pendingOffset = nil
        self.interaction.cancelClick()

        // Preview the drag without queuing a native scroll request for every event.
        self.interaction.offset = layout.clampedOffset(origin - drag.translation.width)
        self.updateSelection(at: self.interaction.offset, in: layout)
    }

    private func dragEnded(_ drag: DragGesture.Value, in layout: CoverFlowScrollLayout) {
        guard let origin = self.interaction.dragOrigin else { return }
        self.interaction.offset = layout.clampedOffset(origin - drag.translation.width)
        self.animateSelection(to: layout.nearestIndex(at: self.interaction.offset), in: layout)
    }

    private func selectCover(at location: CGPoint, in layout: CoverFlowScrollLayout) {
        self.interaction.typeSelection = nil
        let offset = self.interaction.offset
        let point = CGPoint(x: location.x + offset - layout.clampedOffset(offset), y: location.y)
        let geometry = self.interaction.geometry(in: layout)

        self.handleCoverClick(
            at: point, in: geometry, timestamp: ProcessInfo.processInfo.systemUptime,
            interaction: self.interaction
        ) { index in
            self.animateSelection(to: index, in: layout)
        }
    }

    func handleCoverClick(
        at point: CGPoint, in geometry: CoverFlowGeometry, timestamp: TimeInterval,
        interaction: CoverFlowInteractionState, select: (Int) -> Void
    ) {
        guard let index = geometry.coverIndex(at: point) else {
            interaction.lastCoverClick = nil
            return
        }

        let systemInterval = NSEvent.doubleClickInterval
        let interval = systemInterval > 0 ? systemInterval : 0.5
        if let activate = self.activationAction, let previous = interaction.lastCoverClick,
            previous.index == index, self.selectedIndex == index,
            timestamp - previous.timestamp <= interval
        {
            interaction.lastCoverClick = nil
            activate(self.items[index])
        } else {
            interaction.lastCoverClick = (index, timestamp)
            select(index)
        }
    }
}

// MARK: - Keyboard navigation

private extension CoverFlowView {
    func pageSelection(forward: Bool) -> KeyPress.Result {
        self.moveSelection(
            .page(forward: forward, outerSlots: self.configuration.layout.outerSlots))
    }

    func moveSelection(_ move: CoverFlowSelectionMove) -> KeyPress.Result {
        let index = self.selectedIndex
        guard let destination = move.destination(from: index, count: self.items.count) else {
            return .ignored
        }
        self.interaction.clearInputHistory()
        if destination != index {
            self.selection = self.items[destination][keyPath: self.id]
        }
        return .handled
    }

    func activateSelection() -> KeyPress.Result {
        guard let activationAction = self.activationAction, let index = self.selectedIndex else {
            return .ignored
        }
        activationAction(self.items[index])
        return .handled
    }

    func handleTyping(_ press: KeyPress) -> KeyPress.Result {
        guard press.modifiers.intersection([.command, .control]).isEmpty else { return .ignored }
        return self.selectByTyping(
            press.characters, timestamp: ProcessInfo.processInfo.systemUptime)
    }

    func selectByTyping(_ text: String, timestamp: TimeInterval) -> KeyPress.Result {
        guard let searchKey = self.searchKey, !self.items.isEmpty, !text.isEmpty else {
            return .ignored
        }
        let delay = NSEvent.keyRepeatDelay
        let interval = delay > 0 ? min(2, 2 * delay) : 1
        let prefix: String
        if let previous = self.interaction.typeSelection, timestamp - previous.timestamp <= interval
        {
            prefix = previous.prefix + text
        } else {
            guard !text.allSatisfy(\.isWhitespace) else { return .ignored }
            prefix = text
        }
        let match = self.items.firstIndex {
            searchKey($0).range(
                of: prefix, options: [.anchored, .caseInsensitive, .diacriticInsensitive],
                locale: .current) != nil
        }
        if let match { _ = self.moveSelection(.absolute(match)) }
        self.interaction.typeSelection = (prefix, timestamp)
        return .handled
    }
}

private extension View {
    @ViewBuilder
    func coverFlowScrollEdges() -> some View {
        #if compiler(>=6.2)
            if #available(macOS 26, *) {
                self.scrollEdgeEffectHidden()
            } else {
                self
            }
        #else
            self
        #endif
    }
}
