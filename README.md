# CoverFlowUI

Cover Flow for SwiftUI on macOS. The default `CoverFlowConfiguration.classic` preset derives its cover spacing, overlap, and perspective from the original Cover Flow layout metrics in the iTunes 9.0.2 library view on Mac OS X Snow Leopard.

Requires macOS 15 or later and Xcode 16 or later (Swift 6).

## Usage

Add this folder as a local Swift package in Xcode and link the `CoverFlowUI` product.

```swift
import CoverFlowUI
import SwiftUI

struct AlbumBrowser: View {
    let albums: [Album]
    @State private var selection: Album.ID?

    var body: some View {
        CoverFlowView(items: albums, selection: $selection) { album in
            Text(album.title)
        }
        .frame(height: 400)
    }
}
```

The selection binding tracks the centered cover. Set it to an album’s ID to bring that cover into view. If your items don’t conform to `Identifiable`, pass an `id:` key path.

## Demo and tests

Open `CoverFlowDemo/CoverFlowDemo.xcodeproj` in Xcode, select the **CoverFlow Demo** scheme and **My Mac**, then press **⌘R**.

Run `swift test` from the repository root with full Xcode selected. If `xcode-select -p` points to the standalone Command Line Tools, use `DEVELOPER_DIR` to select Xcode for this command:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

[MIT License](LICENSE)
