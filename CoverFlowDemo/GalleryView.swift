import CoverFlowUI
import SwiftUI

struct GalleryView: View {
    @State private var selection: String? = "Cover 7"
    @FocusState private var isCoverFlowFocused: Bool

    private let items = (1...13).map {
        Cover(
            id: "Cover \($0)",
            color: Color(hue: Double($0 - 1) / 13, saturation: 0.65, brightness: 0.85))
    }

    var body: some View {
        CoverFlowView(items: self.items, selection: self.$selection) { cover in
            Rectangle().fill(cover.color.gradient)
        }
        .caption { cover in
            Text(cover.id)
                .font(.headline)
                .foregroundStyle(.white)
        }
        .typeToSelect { $0.id }
        .focused(self.$isCoverFlowFocused)
        .defaultFocus(self.$isCoverFlowFocused, true)
        .padding(.top, 56)
        .background(.black)
    }

    private struct Cover: Identifiable {
        let id: String
        let color: Color
    }
}
