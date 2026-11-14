import SwiftUI

enum CoverFlowContent<Item, Content: View> {
    case immediate((Item) -> Content)
    case asynchronous(@MainActor (Item, CoverFlowPlane, CoverFlowLayout) -> AnyView)
}

struct CoverFlowCoversView<Item, ID: Hashable, Content: View>: View {
    let items: [Item]
    let id: KeyPath<Item, ID>
    let layout: CoverFlowScrollLayout
    let interaction: CoverFlowInteractionState
    let content: CoverFlowContent<Item, Content>

    private var viewport: CGSize { self.layout.metrics.viewport }

    var body: some View {
        let offset = self.interaction.offset
        let geometry = self.interaction.geometry(in: self.layout)
        let planes = geometry.planes().map { plane in
            (itemID: self.items[plane.itemIndex][keyPath: self.id], plane: plane)
        }

        ZStack(alignment: .topLeading) {
            ForEach(planes, id: \.itemID) { entry in
                self.cover(for: entry.plane)
            }
        }
        .frame(width: self.viewport.width, height: self.viewport.height, alignment: .topLeading)
        .clipped()
        .offset(x: self.layout.clampedOffset(offset) - offset)
        .background {
            // Keep the cover views mounted while SwiftUI schedules animation frames.
            if self.interaction.clickStates != nil {
                TimelineView(.animation) { context in
                    Color.clear.onChange(of: context.date, initial: true) {
                        self.interaction.advanceClick(at: ProcessInfo.processInfo.systemUptime)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func cover(for plane: CoverFlowPlane) -> some View {
        let item = self.items[plane.itemIndex]
        switch self.content {
        case .immediate(let content):
            CoverFlowCover(plane: plane, layout: self.layout.metrics) { content(item) }
        case .asynchronous(let cover):
            cover(item, plane, self.layout.metrics)
        }
    }
}

struct CoverFlowAsyncCover<Item, Value, Content: View>: View {
    let item: Item
    let plane: CoverFlowPlane
    let layout: CoverFlowLayout
    let load: @MainActor (Item) async -> Value?
    let content: (Item, Value?) -> Content

    @State private var value: Value?

    var body: some View {
        CoverFlowCover(plane: self.plane, layout: self.layout) {
            self.content(self.item, self.value)
        }
        .task {
            let value = await self.load(self.item)
            guard !Task.isCancelled else { return }
            self.value = value
        }
    }
}

private struct CoverFlowCover<Content: View>: View {
    let plane: CoverFlowPlane
    let layout: CoverFlowLayout
    let content: () -> Content

    private var viewport: CGSize { self.layout.viewport }
    private var configuration: CoverFlowConfiguration { self.layout.configuration }

    var body: some View {
        VStack(spacing: self.plane.reflectionGap) {
            self.face
            self.reflection
        }
        .compositingGroup()
        .projectionEffect(self.plane.projection)
        .frame(width: self.viewport.width, height: self.viewport.height, alignment: .topLeading)
        .clipShape(self.clip)
    }

    private var clip: Path {
        let camera = self.plane.cameraClip(in: self.viewport)
        switch (camera, self.plane.clip) {
        case let (camera?, depth?):
            return Path(camera.intersection(depth))
        case let (clip?, nil), let (nil, clip?):
            return Path(clip)
        case (nil, nil):
            return Path(CGRect(origin: .zero, size: self.viewport))
        }
    }

    @ViewBuilder
    private var face: some View {
        if self.configuration.preservesContentAlpha {
            self.coverContent.colorMultiply(Color(white: self.plane.intensity))
        } else {
            self.coverContent.overlay(Color.black.opacity(1 - self.plane.intensity))
        }
    }

    @ViewBuilder
    private var reflection: some View {
        let reflection = self.configuration.reflection
        let near = self.plane.intensity * reflection.nearIntensity
        let far = self.plane.intensity * reflection.farIntensity
        let mirrored = self.coverContent.scaleEffect(x: 1, y: -1)

        if self.configuration.preservesContentAlpha {
            mirrored.mask {
                LinearGradient(
                    colors: [.white.opacity(near), .white.opacity(far)],
                    startPoint: .top, endPoint: .bottom)
            }
        } else {
            mirrored.overlay {
                LinearGradient(
                    colors: [.black.opacity(1 - near), .black.opacity(1 - far)],
                    startPoint: .top, endPoint: .bottom)
            }
        }
    }

    private var coverContent: some View {
        let background: Color = self.configuration.preservesContentAlpha ? .clear : .black
        return
            background
            .frame(width: self.plane.size.width, height: self.plane.size.height)
            .overlay(alignment: .top) {
                self.content()
                    .frame(width: self.plane.size.width, height: self.plane.size.height)
            }
            .clipped()
    }
}
