#if os(iOS)
import SwiftUI

@MainActor
public extension View {
    /// Starts Agentation when this view appears. Put it on your root view.
    /// Does nothing in release builds.
    func agentation(
        endpoint: String? = nil,
        appName: String? = nil,
        captureScreenshots: Bool = true,
        toolbarPosition: ToolbarPosition = .bottomTrailing,
        enableKeyCommands: Bool = true,
        allowOnDevice: Bool = false,
        onAnnotationAdd: ((Annotation) -> Void)? = nil,
        onCopy: ((String) -> Void)? = nil
    ) -> some View {
        #if DEBUG
        let configuration = Configuration(
            endpoint: endpoint, appName: appName, captureScreenshots: captureScreenshots,
            toolbarPosition: toolbarPosition, enableKeyCommands: enableKeyCommands,
            allowOnDevice: allowOnDevice, onAnnotationAdd: onAnnotationAdd, onCopy: onCopy)
        return onAppear { Agentation.start(configuration) }
        #else
        return self
        #endif
    }

    /// Names this view in annotations, so an agent has something to grep for.
    /// Does nothing in release builds.
    func agentationTag(_ tag: String) -> some View {
        #if DEBUG
        return background(AgentationMarker(tag: tag, source: nil).allowsHitTesting(false).accessibilityHidden(true))
        #else
        return self
        #endif
    }

    /// Records the file and line where this modifier is written, e.g. `MyApp/CheckoutView.swift:42`.
    /// Does nothing in release builds.
    func agentationSource(file: StaticString = #fileID, line: UInt = #line) -> some View {
        #if DEBUG
        return background(
            AgentationMarker(tag: nil, source: "\(file):\(line)").allowsHitTesting(false).accessibilityHidden(true))
        #else
        return self
        #endif
    }
}

/// Places an invisible `AgentationMarkerView` behind the modified view.
struct AgentationMarker: UIViewRepresentable {
    let tag: String?
    let source: String?

    func makeUIView(context: Context) -> AgentationMarkerView {
        let view = AgentationMarkerView()
        view.markerTag = tag
        view.source = source
        return view
    }

    func updateUIView(_ view: AgentationMarkerView, context: Context) {
        view.markerTag = tag
        view.source = source
    }
}
#endif
