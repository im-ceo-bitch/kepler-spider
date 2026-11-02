# Spyder Native Collection — SwiftUI / iOS 17+

Independent **native Swift Package** for the Spyder Wallet / Spyder Network chat interface. No changes to the app repository are included.

## What is delivered

- **12 vector spider presets** traced from the five user-supplied references (nine thumbnail icons plus three higher-resolution treatments). Actual shapes are stored as polygon coordinates in `artworks.json` and drawn by `SwiftUI.Canvas` as native paths. No raster images, web requests, WebViews, third-party animation engines or SVG renderers are used at runtime.
- **480 deterministic particles per spider**. Particles move from all screen edges and scattered interior positions to the chosen silhouette, then smoothly yield to the fully formed vector.
- **Two independent layers**: customizable native Canvas/SwiftUI background *behind* a customizable native vector spider. Chat messages remain above both layers when inserted with `.background { ... }`.
- **12 neon accent colors**, optional glow and glow-strength control.
- **Six native background options**: Phantom Web, Pure Void, Cyber Grid, Deep Nebula, Neural Circuit, Signal Waves.
- **Animation switch** and *only when entering chat* switch; animation starts on chat entry by passing a new `entryToken`, never on each received message.
- **Accessibility**: respects iOS Reduce Motion; 30 fps while gathering (~2.25 s), no continuous TimelineView animation after completion; the preview/editor has no forced animation loop.
- **UserDefaults persistence** and a standalone in-app settings/demo view.

## Add to an Xcode project

1. Unzip `SpyderNativeCollection` next to your app's repository (or anywhere on your Mac).
2. In Xcode, use **File → Add Package Dependencies → Add Local...**, then select the folder containing `Package.swift`.
3. Add the `SpyderNativeCollection` product to your iOS app target. Target minimum: **iOS 17.0**.
4. Import `SpyderNativeCollection` wherever the chat background or customization view is needed.

### Integrate *behind* the existing messages

```swift
import SwiftUI
import SpyderNativeCollection

struct MyChatView: View {
    @ObservedObject var style: SpyderAppearanceStore
    let chatEntryNumber: Int // increment only on chat navigation

    var body: some View {
        MyExistingMessagesView()
            .background {
                SpyderChatBackground(
                    theme: style.theme,
                    entryToken: chatEntryNumber
                )
                .ignoresSafeArea()
            }
    }
}
```

For a preferences screen:

```swift
@StateObject private var style = SpyderAppearanceStore()
// Present SpyderAppearanceEditor(store: style)
// Or open SpyderCollectionDemoView() to examine the standalone component.
```

To **disable** particle assembly permanently: `style.theme.animationEnabled = false`.

To **enable only on chat entry**: `style.theme.animationOnChatEntryOnly = true`, then keep the `entryToken` unchanged for messages/keyboard/theme updates, and increment it when opening the chat screen. The component's initial appearance is also considered a chat entry. To replay manually from your own controls, increment the token.

To **store different themes per chat**, create a store for each chat with a distinct key:

```swift
let style = SpyderAppearanceStore(key: "spyder.chat.theme.\(chatID)")
```

Instantiate this on the main actor and retain it for the chat lifecycle. A shared store yields one theme for all chats.

### Source tree

```text
Package.swift
Sources/SpyderNativeCollection/
    SpyderModels.swift             // identifiers, themes, 12 colors, persistent store
    SpyderVectorArt.swift          // native vector Canvas / optional neon glow
    SpyderBackdrop.swift           // 6 independent backgrounds
    SpyderChatBackground.swift     // animation and two-layer composition
    SpyderAppearanceEditor.swift   // user settings, grid, palette and preview
    Resources/artworks.json        // 12 vector shapes + native particle targets
Tests/SpyderNativeCollectionTests/SpyderCollectionTests.swift
Examples/ChatScreenIntegration.swift
Previews/collection-12.png      // documentation ONLY, not bundled in app
Previews/01-*.png ... 12-*.png // documentation ONLY
Tools/build_artworks.py         // offline generator; needs user-provided images
Tools/validate_package.py       // cross-platform validation
NOTICE.md
```

## Runtime and implementation notes

- All symbols are replayed from polygon contours as `Path` commands; artwork can be resized without running a raster image renderer.
- `artworks.json` is an SPM resource, loaded once. The 12 preview PNGs are excluded from the app target and are used only to **see** the collection.
- Original imagery is *not* embedded in the application. No internet permission or additional packages are needed.
- The `SpyderChatBackground` view ignores touches. Display chat bubbles using your normal SwiftUI hierarchy in front of it.
- Front-layer painting has a single on-screen symbol by default. Change `relativeWidth`/`relativeHeight` in `SpyderChatBackground.swift` and `SpyderVectorArtworkView.swift` if a different scale is needed for your device sizes.
- Particle assembly uses deterministic native Canvas circles and approximately 2.25 seconds of animation, not sprite sheets or video.
- Preview images derive from the JSON geometry, but **are not screenshots of a built iOS app**.

## Validation status

`Tools/validate_package.py`, Swift syntax parsing and ZIP extraction/replay are performed in the generation environment. The environment does not include Xcode/iOS SDK, so an **iOS simulator/device compilation, runtime FPS measurement, and TestFlight build have not been performed**. Run the bundled XCTest suite in Xcode before release; integrate behind an existing message view and verify on iPhone 11 and iPhone 13 mini.

## Wallet integration revision

The integrated Wallet adds `SpyderSpiderLayer`, a transparent foreground-only renderer.
`SpyderChatBackground` remains the compatible standalone two-layer wrapper.
The foreground accepts `isActive`, `animateOnAppear`, size parameters and `onEntryHandled`.
The host retains entry consumption outside the renderer so Chat/Terminal remounts cannot
replay an entry-only animation. Scene inactivity, Reduce Motion and low power cancel assembly.
The standalone editor's duplicate theme-change/token replay was removed.

In the Wallet, use its existing persona/per-chat Appearance page, not the standalone
`SpyderAppearanceStore` or demo. Wallet models persist background and spider independently.
The 12 source artworks and native backdrop geometry are unchanged. `SHA256SUMS.txt`
was regenerated for this integration revision, retaining the original NOTICE.
