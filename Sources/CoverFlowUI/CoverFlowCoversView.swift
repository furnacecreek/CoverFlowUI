import SwiftUI

struct CoverFlowCoversView<Item, ID: Hashable, Content: View>: View {
    let items: [Item]
    let id: KeyPath<Item, ID>
    let layout: CoverFlowScrollLayout
    let interaction: CoverFlowInteractionState
    let content: (Item) -> Content

    private var viewport: CGSize { self.layout.metrics.viewport }
    private var configuration: CoverFlowConfiguration { self.layout.metrics.configuration }

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

    private func cover(for plane: CoverFlowPlane) -> some View {
        VStack(spacing: plane.reflectionGap) {
            self.face(for: plane)
            self.reflection(for: plane)
        }
        .compositingGroup()
        .projectionEffect(plane.projection)
        .frame(width: self.viewport.width, height: self.viewport.height, alignment: .topLeading)
        .clipShape(self.clip(for: plane))
    }

    private func clip(for plane: CoverFlowPlane) -> Path {
        let camera = plane.cameraClip(in: self.viewport)
        switch (camera, plane.clip) {
        case let (camera?, depth?):
            return Path(camera.intersection(depth))
        case let (clip?, nil), let (nil, clip?):
            return Path(clip)
        case (nil, nil):
            return Path(CGRect(origin: .zero, size: self.viewport))
        }
    }

    @ViewBuilder
    private func face(for plane: CoverFlowPlane) -> some View {
        let content = self.coverContent(for: plane)
        if self.configuration.preservesContentAlpha {
            content.colorMultiply(Color(white: plane.intensity))
        } else {
            content.overlay(Color.black.opacity(1 - plane.intensity))
        }
    }

    @ViewBuilder
    private func reflection(for plane: CoverFlowPlane) -> some View {
        let reflection = self.configuration.reflection
        let near = plane.intensity * reflection.nearIntensity
        let far = plane.intensity * reflection.farIntensity
        let mirrored = self.coverContent(for: plane).scaleEffect(x: 1, y: -1)

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

    private func coverContent(for plane: CoverFlowPlane) -> some View {
        let background: Color = self.configuration.preservesContentAlpha ? .clear : .black
        return
            background
            .frame(width: plane.size.width, height: plane.size.height)
            .overlay(alignment: .top) {
                self.content(self.items[plane.itemIndex])
                    .frame(width: plane.size.width, height: plane.size.height)
            }
            .clipped()
    }
}
