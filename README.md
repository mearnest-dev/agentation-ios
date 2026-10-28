# agentation-ios

Visual annotation tool for iOS apps running in the Simulator. Inspired by [Agentation](https://www.agentation.com/) for React and [agentation-vanilla](https://github.com/mearnest-dev/agentation-vanilla) for plain JS. This is the native iOS version.

Tap a view, write a note, copy structured markdown. Your AI coding agent gets the view's identifier, type, frame, text and a screenshot, so it can find the code you mean.

> **Status:** 0.1, early. It hasn't been tried on many apps yet. Please open an issue when it describes a view badly.

One Swift package. Zero dependencies. Debug builds only.

## Quick Start

### 1. Add the package

In Xcode: **File → Add Package Dependencies…** and enter:

```
https://github.com/mearnest-dev/agentation-ios
```

Or in `Package.swift`:

```swift
.package(url: "https://github.com/mearnest-dev/agentation-ios", from: "0.1.0")
```

Link the `Agentation` library to your app target.

### 2. Start it

**SwiftUI**

```swift
import SwiftUI
import Agentation

@main
struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .agentation()
        }
    }
}
```

**UIKit**

```swift
import Agentation

func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
    // ...your window setup...
    Agentation.start()
}
```

A floating button appears in the bottom-right corner. Tap it to open the toolbar.

The toolbar only runs in `DEBUG` builds. In release builds `start()` and all the modifiers do nothing, so you don't need `#if DEBUG` around them. By default it also only runs in the Simulator; pass `allowOnDevice: true` to use it on a physical device.

## Features

- **Inspect mode**: tap any view to see its type, identifier, frame, text, font and colors. Copy the details, or turn them into an annotation.
- **Annotate mode**: tap a view to drop a numbered marker with a note
- **Area select**: drag to annotate a region, even empty space
- **Intent tags**: tag annotations as bug, style, feature, or content
- **Screenshots**: each annotation saves a cropped PNG with the selection outlined. In the Simulator, that file lives on your Mac, so the agent can open it directly.
- **Copy as markdown**: copies to the Simulator pasteboard, which syncs to your Mac clipboard. Paste into Claude Code, Cursor, or any AI tool.
- **MCP sync**: sends annotations to the existing [`agentation-mcp`](https://www.npmjs.com/package/agentation-mcp) server, so agents can read them without copy/paste
- **Agent round trip**: when your agent resolves or dismisses an annotation through MCP, it disappears from the toolbar
- **Per-screen persistence**: annotations survive relaunches, grouped by screen
- **Isolated overlay**: draws in its own `UIWindow`, so it never changes your view hierarchy or layout
- **UIKit and SwiftUI**: works with either, or both in the same app

## How it finds your code

On the web, Agentation hands the agent a CSS selector to `grep` for. On iOS, the best grep targets are:

| What it captures | Example | Where it comes from |
|---|---|---|
| Accessibility identifier | `checkout.payButton` | `.accessibilityIdentifier(...)` / `accessibilityIdentifier` |
| Agentation tag | `PaymentSummaryCard` | `.agentationTag(...)` / `view.agentationTag` (optional, see below) |
| Source location | `MyApp/PaymentSummary.swift:42` | `.agentationSource()` (optional, see below) |
| View controller chain | `UINavigationController > CheckoutViewController` | responder chain |
| View path | `UITableView > PaymentCell[2] > UIStackView > UILabel` | view hierarchy |
| SwiftUI root view | `UIHostingController<CheckoutView>` | hosting controller's generic type |
| Visible text | `"Pay $42.00"` | label, button and text field contents |
| Accessibility label | `"Pay"` | accessibility tree |

**Tip:** the more views have an `accessibilityIdentifier`, the more precise the output. Identifiers also help your UI tests.

### Optional helpers

SwiftUI views don't keep their type names at runtime, so the package adds two modifiers. Both do nothing in release builds.

```swift
PaymentSummary(order: order)
    .agentationTag("PaymentSummaryCard")   // a name the agent can grep for
    .agentationSource()                    // records this file and line automatically
```

`.agentationSource()` uses `#fileID` and `#line` default arguments, so you don't type the path yourself.

For UIKit views, set the tag as a property:

```swift
headerView.agentationTag = "ProfileHeader"
```

## Output

### Inspect output

```
type: Button
identifier: checkout.payButton
tag: PaymentSummaryCard
source: MyApp/PaymentSummary.swift:42
screen: CheckoutView
path: UITabBarController > UINavigationController > UIHostingController<CheckoutView> > PaymentSummaryCard > Button "Pay $42.00"
frame: x=16 y=712 w=361 h=50 (pt, window)
text: "Pay $42.00"
nearby: "Total", "$42.00"
```

UIKit views also get a `style:` line, e.g. `font=SFUI-Semibold 17pt; foreground=#FFFFFF; background=#0A84FF; cornerRadius=12`.

### Annotation output

```markdown
# iOS feedback: MyApp (com.example.myapp)
Device: iPhone 16 Pro Simulator, iOS 26.0, 393×852pt @3x, light mode, Dynamic Type L

## [style] Annotation 1
**Screen:** `CheckoutView`
**Element:** `Button`
**Identifier:** `checkout.payButton`
**Tag:** `PaymentSummaryCard`
**Source:** `MyApp/PaymentSummary.swift:42`
**Path:** `UITabBarController > UINavigationController > UIHostingController<CheckoutView> > PaymentSummaryCard > Button "Pay $42.00"`
**View controllers:** `UITabBarController > UINavigationController > UIHostingController<CheckoutView>`
**Frame:** `x=16 y=712 w=361 h=50`
**Text:** "Pay $42.00"
**Nearby text:** "Total", "$42.00"
**Screenshot:** `/Users/you/Library/Developer/CoreSimulator/Devices/…/tmp/agentation/annotation-3f2a9c1d.png`
**Note:** corners should be 12, match the cards above

## [bug] Annotation 2
**Screen:** `CheckoutView`
**Area:** `x=0 y=120 w=393 h=180`
**Inside:** `ShippingOptions`
**Path:** `UITabBarController > UINavigationController > UIHostingController<CheckoutView> > ShippingOptions > area`
**Text in area:** "Shipping", "Standard (3–5 days)"
**Screenshot:** `/Users/you/Library/Developer/CoreSimulator/Devices/…/tmp/agentation/annotation-9b1e04aa.png`
**Note:** this section overlaps the header when Dynamic Type is XXL
```

## Connect to your agent (MCP)

agentation-ios speaks the same HTTP API as the web toolbar. The Simulator shares your Mac's network, so `localhost` reaches a server running on the Mac.

1. Register the server with your agent:

   ```bash
   claude mcp add agentation -- npx -y agentation-mcp server
   ```

2. Point the toolbar at it:

   ```swift
   .agentation(endpoint: "http://localhost:4747")
   // or
   Agentation.start(endpoint: "http://localhost:4747")
   ```

3. Allow local networking in your app's `Info.plist`:

   ```xml
   <key>NSAppTransportSecurity</key>
   <dict>
       <key>NSAllowsLocalNetworking</key>
       <true/>
   </dict>
   ```

4. Add a test annotation and ask your agent to call `agentation_get_all_pending`.

Annotations are sent with a URL of the form `ios-sim://<bundle id>/<screen>`, so the app gets its own session next to any web sessions. The web schema has no fields for some iOS details (screen, view class, identifier, tag, screenshot path, intent tag), so those go in the annotation's `attributes`. Intent tags map to the server's intents: `bug` → `fix`, the rest → `change`.

The agent can acknowledge, reply to, and resolve them like any other Agentation annotation. While the toolbar is open, it checks the server every few seconds and removes annotations the agent resolved or dismissed. The dot in the toolbar shows sync status: green when connected, red when the server can't be reached.

On a physical device, `localhost` is the phone itself. Run the server with `--host 0.0.0.0` and use your Mac's LAN address instead.

## Configuration

```swift
Agentation.start(
    endpoint: "http://localhost:4747",     // MCP server; nil = local copy only
    appName: "MyApp",                      // shown in copied output
    captureScreenshots: true,
    toolbarPosition: .bottomTrailing,      // starting corner; drag to move
    enableKeyCommands: true,
    allowOnDevice: false,
    onAnnotationAdd: { annotation in },    // structured callback
    onCopy: { markdown in }
)
```

Everything is optional. The SwiftUI `.agentation(...)` modifier takes the same arguments.

Other calls: `Agentation.show()` opens the toolbar, `Agentation.copyAll()` copies everything, `Agentation.annotations` returns what's saved, and `Agentation.stop()` removes the toolbar.

### Annotation type

Matches the [Agentation annotation schema](https://agentation.com/schema) where the fields make sense, with iOS additions:

```swift
public struct Annotation: Codable, Identifiable {
    public let id: String
    public var comment: String
    public var intent: Intent?               // .bug, .style, .feature, .content
    public var timestamp: TimeInterval       // seconds since 1970
    public var screen: String                // top view controller / SwiftUI root view
    public var element: String               // "Button", "Text", "Area"
    public var elementPath: String           // condensed view path
    public var viewClass: String?            // "UIButton" (UIKit selections)
    public var viewControllers: [String]     // owning view controllers, outermost first
    public var accessibilityIdentifier: String?
    public var accessibilityLabel: String?
    public var agentationTag: String?
    public var sourceLocation: String?       // "MyApp/CheckoutView.swift:42"
    public var text: String?
    public var nearbyText: [String]          // nearby text, or text inside an area
    public var containedTags: [String]       // tags inside an area
    public var style: String?                // font, colors, corner radius (UIKit)
    public var boundingBox: Rect?            // window points
    public var x: Double                     // marker, % of window width
    public var y: Double                     // marker, pt from top of window
    public var isArea: Bool
    public var screenshotPath: String?
    public var url: String                   // ios-sim://<bundle id>/<screen>
    public var serverId: String?             // set after syncing to agentation-mcp
}
```

## Controls

| Action | How |
|---|---|
| Open or close the toolbar | Tap the floating button, or shake (**Device → Shake** / ⌃⌘Z in the Simulator) |
| Inspect mode | Scope button, or `I` |
| Annotate mode | Speech-bubble button, or `A`. Tap a view, or drag to select an area |
| Edit or delete an annotation | Tap its numbered marker |
| Copy all as markdown | Copy button, or `C` |
| Clear annotations | Trash button (this screen or all screens) |
| Leave mode / close | `Esc`, or tap the active button again |
| Move the toolbar | Drag it |

Keyboard shortcuts work on a hardware keyboard (your Mac keyboard in the Simulator) while the toolbar is open. They stop while one of your app's text fields has focus. For the Mac clipboard to receive copies, keep **Edit → Automatically Sync Pasteboard** turned on in the Simulator.

While a mode is active, taps go to the overlay instead of your app. Turn the mode off to use the app normally. The toolbar never blocks touches outside its own bounds.

## How it works

- **Overlay window.** A `UIWindow` above your app's windows draws the toolbar, highlights and markers. It passes touches through unless a mode is active. This is the iOS version of agentation-vanilla's Shadow DOM isolation.
- **Hit testing.** A tap is resolved by finding the front-most visible view under it in your app's window, including non-interactive views like labels. Inside SwiftUI hosting views, the accessibility tree is used to narrow it down, because SwiftUI draws many views without a matching `UIView`.
- **Tags.** `.agentationTag` and `.agentationSource` place an invisible view behind the modified view, so a tap point can be matched to the innermost tag around it.
- **Context capture.** The package walks up the view hierarchy and responder chain to build the path, screen name and view controller chain. It reads text, fonts, colors and layer properties from the views it finds.
- **Screenshots.** The selected area plus some margin is rendered with `UIGraphicsImageRenderer` and saved to the app's `tmp/agentation/` folder. In the Simulator, that folder is a normal path on your Mac.
- **Persistence.** Annotations are stored as JSON in `Application Support/Agentation/annotations.json`, grouped by screen, and expire after 7 days.
- **Sync.** With an `endpoint`, annotations are sent to `agentation-mcp` with `URLSession` using the same session and annotation routes as the web toolbar. Failed sends are retried while the toolbar is open.
- **Shake.** `UIWindow.motionEnded` is swizzled once to detect shakes. This happens when Agentation starts, so never in release builds.

## Limitations

- **Simulator first.** It works on a device, but the MCP endpoint and screenshot paths are less convenient there.
- **Markers don't follow scrolling.** A marker stays where you tapped. The copied output is unaffected.
- **Screen names are a best guess.** They come from the top view controller. In SwiftUI, pushed `NavigationStack` screens may show the navigation title instead of a type name.
- **SwiftUI is best effort.** SwiftUI doesn't expose view types at runtime. Without identifiers, tags or `.agentationSource()`, output falls back to hosting-controller types, accessibility info and visible text. Style details are only captured for UIKit views.
- **No content inside Metal, SpriteKit, SceneKit or video layers.** You can annotate the containing view or an area.
- **Web views.** For content inside a `WKWebView`, inject [agentation-vanilla](https://github.com/mearnest-dev/agentation-vanilla) into the page instead.
- **Debug only.** The package refuses to start in release builds, and the SwiftUI modifiers do nothing there. The code is still linked into release builds, just never run.

## Requirements

- iOS 16+
- Xcode 15+ (Swift 5.9+)
- A Mac, because the iOS Simulator only runs on macOS
- `agentation-mcp` (optional) needs Node.js 20+ on your Mac

## Project layout

```
agentation-ios/
├── Package.swift
├── Sources/Agentation/
│   ├── Agentation.swift          // start(), stop(), Configuration
│   ├── SwiftUI/                  // .agentation(), .agentationTag(), .agentationSource()
│   ├── Overlay/                  // overlay window, toolbar, markers, editor, shake
│   ├── Capture/                  // hit testing, view path, accessibility, styles, tags
│   ├── Model/                    // Annotation, type-name parsing
│   ├── Output/                   // markdown formatter, screenshot writer
│   ├── Storage/                  // JSON persistence
│   └── Sync/                     // agentation-mcp HTTP client
├── Tests/AgentationTests/
└── Demo/                         // SwiftUI + UIKit demo app (XcodeGen)
```

## Demo

The demo has a SwiftUI checkout screen and a UIKit settings screen.

```bash
git clone https://github.com/mearnest-dev/agentation-ios.git
cd agentation-ios/Demo
brew install xcodegen    # once
xcodegen
open AgentationDemo.xcodeproj
```

Run the `AgentationDemo` scheme on any iPhone Simulator. To try MCP sync, run `npx -y agentation-mcp server` first.

## Tests

The model, formatting, storage and sync payload tests don't need UIKit, so they run on macOS:

```bash
swift test
```

Or run them on a Simulator:

```bash
xcodebuild test -scheme Agentation -destination 'platform=iOS Simulator,name=iPhone 16'
```

## Credits

The idea and the annotation format come from [Agentation](https://agentation.com) by Benji Taylor. This project is an independent implementation and is not affiliated with Agentation. It talks to the published `agentation-mcp` server; it does not include its code.

## License

MIT
