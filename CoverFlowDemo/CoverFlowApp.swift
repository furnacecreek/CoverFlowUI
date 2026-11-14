import SwiftUI

@main
struct CoverFlowApp: App {
    var body: some Scene {
        Window("Cover Flow", id: "gallery") {
            GalleryView()
                .frame(minWidth: 720, minHeight: 420)
                .containerBackground(Color.black, for: .window)
                .preferredColorScheme(.dark)
        }
        .defaultSize(width: 940, height: 460)
    }
}
