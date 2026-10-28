#if os(iOS)
import UIKit

/// Root of the overlay window. Owns the toolbar, modes, markers, editor and sync.
final class OverlayViewController: UIViewController {
    private let config: Configuration
    private let store: AnnotationStore
    private let sync: SyncClient?
    weak var overlayWindow: UIWindow?

    private(set) var mode: OverlayMode = .off
    private(set) var isExpanded = false
    private weak var previousKeyWindow: UIWindow?
    private var timer: Timer?
    private var ticks = 0
    private var currentScreen = ""
    private var inFlight = Set<String>()
    private var syncFailing = false
    private var lastInspected: (element: CapturedElement, point: CGPoint)?
    private var toolbarAnchor: CGPoint?
    private var areaStart: CGPoint?

    private let captureView = UIView()
    private let highlightView = HighlightView()
    private let areaView = UIView()
    private let markersContainer = PassthroughView()
    private let inspectPanel = InspectPanelView()
    private let toolbar = ToolbarView()
    private let toast = ToastView()

    private lazy var tapRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
    private lazy var areaRecognizer = UIPanGestureRecognizer(target: self, action: #selector(handleAreaPan(_:)))

    init(configuration: Configuration, store: AnnotationStore = AnnotationStore()) {
        self.config = configuration
        self.store = store
        self.sync = configuration.endpoint.flatMap { SyncClient(endpoint: $0, sessionURL: AppInfo.sessionURL) }
        super.init(nibName: nil, bundle: nil)
        if configuration.endpoint != nil && sync == nil {
            print("[Agentation] Ignoring invalid endpoint: \(configuration.endpoint ?? "")")
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    deinit {
        timer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }

    var allAnnotations: [Annotation] { store.annotations }

    // MARK: - View setup

    override func loadView() {
        view = PassthroughView()
        view.backgroundColor = .clear
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        captureView.frame = view.bounds
        captureView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        captureView.isHidden = true
        captureView.addGestureRecognizer(tapRecognizer)
        captureView.addGestureRecognizer(areaRecognizer)
        captureView.accessibilityLabel = "Agentation selection layer"

        areaView.isUserInteractionEnabled = false
        areaView.isHidden = true
        areaView.layer.borderWidth = 2
        areaView.layer.borderColor = UIColor.systemOrange.cgColor
        areaView.backgroundColor = UIColor.systemOrange.withAlphaComponent(0.12)
        areaView.layer.cornerRadius = 4

        markersContainer.frame = view.bounds
        markersContainer.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        markersContainer.isHidden = true

        for subview in [captureView, highlightView, areaView, markersContainer, inspectPanel, toolbar, toast] {
            view.addSubview(subview)
        }

        inspectPanel.translatesAutoresizingMaskIntoConstraints = false
        toast.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            inspectPanel.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 12),
            inspectPanel.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -12),
            inspectPanel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            toast.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            toast.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            toast.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, constant: -40),
        ])

        toolbar.onExpand = { [weak self] in self?.setExpanded(true) }
        toolbar.onCollapse = { [weak self] in self?.setExpanded(false) }
        toolbar.onInspect = { [weak self] in self?.toggle(.inspect) }
        toolbar.onAnnotate = { [weak self] in self?.toggle(.annotate) }
        toolbar.onCopy = { [weak self] in self?.copyAll() }
        toolbar.onClear = { [weak self] in self?.confirmClear() }
        toolbar.onDrag = { [weak self] gesture in self?.handleToolbarDrag(gesture) }
        toolbar.setSyncState(sync == nil ? .disabled : .unknown)
        toolbar.setCount(store.annotations.count)

        inspectPanel.onCopy = { [weak self] in self?.copyInspect() }
        inspectPanel.onAnnotate = { [weak self] in self?.annotateInspected() }
        inspectPanel.onClose = { [weak self] in
            self?.inspectPanel.hide()
            self?.highlightView.hide()
        }

        NotificationCenter.default.addObserver(self, selector: #selector(handleShake), name: .agentationShake, object: nil)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        layoutToolbar()
        layoutMarkers()
    }

    // Defer system appearance to the app underneath.
    override var prefersStatusBarHidden: Bool { appTopViewController?.prefersStatusBarHidden ?? false }
    override var preferredStatusBarStyle: UIStatusBarStyle { appTopViewController?.preferredStatusBarStyle ?? .default }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        appWindow()?.rootViewController?.supportedInterfaceOrientations ?? .all
    }

    private var appTopViewController: UIViewController? {
        appWindow().flatMap { ScreenResolver.topViewController(in: $0) }
    }

    // MARK: - App window

    /// The app window under the overlay that taps should be resolved against.
    func appWindow() -> UIWindow? {
        guard let scene = overlayWindow?.windowScene else { return nil }
        let candidates = scene.windows.filter { window in
            window !== overlayWindow && !window.isHidden && window.alpha > 0.01 && !Self.isSystemWindow(window)
        }
        if let previous = previousKeyWindow, candidates.contains(where: { $0 === previous }) { return previous }
        if let key = candidates.first(where: { $0.isKeyWindow }) { return key }
        return candidates.last(where: { $0.windowLevel == .normal }) ?? candidates.last
    }

    private static func isSystemWindow(_ window: UIWindow) -> Bool {
        let name = String(describing: type(of: window))
        return name.contains("Keyboard") || name.contains("TextEffects") || name.contains("UIRemote")
    }

    private func overlayPointToApp(_ point: CGPoint, _ window: UIWindow) -> CGPoint {
        let screenPoint = view.convert(point, to: window.screen.coordinateSpace)
        return window.convert(screenPoint, from: window.screen.coordinateSpace)
    }

    private func overlayRectToApp(_ rect: CGRect, _ window: UIWindow) -> CGRect {
        let screenRect = view.convert(rect, to: window.screen.coordinateSpace)
        return window.convert(screenRect, from: window.screen.coordinateSpace)
    }

    private func appRectToOverlay(_ rect: CGRect, _ window: UIWindow) -> CGRect {
        let screenRect = window.convert(rect, to: window.screen.coordinateSpace)
        return view.convert(screenRect, from: window.screen.coordinateSpace)
    }

    private func appPointToOverlay(_ point: CGPoint, _ window: UIWindow) -> CGPoint {
        let screenPoint = window.convert(point, to: window.screen.coordinateSpace)
        return view.convert(screenPoint, from: window.screen.coordinateSpace)
    }

    // MARK: - Expand / collapse

    func setExpanded(_ expanded: Bool) {
        guard expanded != isExpanded else { return }
        isExpanded = expanded
        if expanded {
            previousKeyWindow = overlayWindow?.windowScene?.windows.first { $0.isKeyWindow && $0 !== overlayWindow }
            overlayWindow?.makeKey()
            becomeFirstResponder()
            refreshScreen(force: true)
            startTimer()
            pollServer()
        } else {
            setMode(.off)
            stopTimer()
            resignFirstResponder()
            if let previous = previousKeyWindow, !previous.isHidden { previous.makeKey() }
        }
        markersContainer.isHidden = !expanded
        toolbar.setExpanded(expanded)
        UIView.animate(withDuration: 0.2) { self.layoutToolbar() }
    }

    @objc private func handleShake() {
        setExpanded(!isExpanded)
    }

    // MARK: - Modes

    private func toggle(_ newMode: OverlayMode) {
        setMode(mode == newMode ? .off : newMode)
    }

    private func setMode(_ newMode: OverlayMode) {
        mode = newMode
        captureView.isHidden = newMode == .off
        switch newMode {
        case .off: captureView.backgroundColor = .clear
        case .inspect: captureView.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.04)
        case .annotate: captureView.backgroundColor = UIColor.systemOrange.withAlphaComponent(0.04)
        }
        areaRecognizer.isEnabled = newMode == .annotate
        highlightView.hide()
        areaView.isHidden = true
        if newMode != .inspect { inspectPanel.hide() }
        toolbar.setActiveMode(newMode)
    }

    // MARK: - Gestures

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        guard let window = appWindow() else { return }
        let point = overlayPointToApp(gesture.location(in: view), window)
        let element = ElementCapture.element(at: point, in: window)
        let frame = appRectToOverlay(element.frame, window)

        switch mode {
        case .inspect:
            highlightView.show(frame: frame, caption: element.element, color: .systemBlue)
            lastInspected = (element, point)
            inspectPanel.show(text: MarkdownFormatter.inspect(element, screen: ScreenResolver.screenName(in: window)))
        case .annotate:
            highlightView.show(frame: frame, caption: element.element, color: .systemOrange)
            beginAnnotation(element, anchor: point, in: window)
        case .off:
            break
        }
    }

    @objc private func handleAreaPan(_ gesture: UIPanGestureRecognizer) {
        let location = gesture.location(in: view)
        switch gesture.state {
        case .began:
            let translation = gesture.translation(in: view)
            let start = CGPoint(x: location.x - translation.x, y: location.y - translation.y)
            areaStart = start
            highlightView.hide()
            areaView.frame = Self.rect(start, location)
            areaView.isHidden = false
        case .changed:
            if let start = areaStart { areaView.frame = Self.rect(start, location) }
        case .ended:
            guard let start = areaStart, let window = appWindow() else {
                areaView.isHidden = true
                return
            }
            areaStart = nil
            let rect = Self.rect(start, location)
            guard rect.width >= 16, rect.height >= 16 else {
                areaView.isHidden = true
                return
            }
            let appRect = overlayRectToApp(rect, window)
            let element = ElementCapture.area(appRect, in: window)
            beginAnnotation(element, anchor: CGPoint(x: appRect.maxX, y: appRect.minY), in: window)
        default:
            areaStart = nil
            areaView.isHidden = true
        }
    }

    private static func rect(_ a: CGPoint, _ b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }

    // MARK: - Inspect

    private func copyInspect() {
        UIPasteboard.general.string = inspectPanel.text
        config.onCopy?(inspectPanel.text)
        toast.show("Copied element details")
    }

    private func annotateInspected() {
        guard let inspected = lastInspected, let window = appWindow() else { return }
        inspectPanel.hide()
        setMode(.annotate)
        highlightView.show(frame: appRectToOverlay(inspected.element.frame, window),
                           caption: inspected.element.element, color: .systemOrange)
        beginAnnotation(inspected.element, anchor: inspected.point, in: window)
    }

    // MARK: - Annotations

    private func beginAnnotation(_ element: CapturedElement, anchor: CGPoint, in window: UIWindow) {
        let screen = ScreenResolver.screenName(in: window)
        let id = UUID().uuidString
        let shot = config.captureScreenshots
            ? ScreenshotWriter.capture(element.frame, in: window, name: "annotation-\(id.prefix(8).lowercased())")
            : nil
        let windowSize = window.bounds.size
        let title = element.isArea ? "Area on \(screen)" : element.element
        let subtitle = element.agentationTag ?? element.accessibilityIdentifier ?? element.elementPath

        presentEditor(title: title, subtitle: subtitle, comment: "", intent: nil, allowsDelete: false) { [weak self] result in
            guard let self else { return }
            self.highlightView.hide()
            self.areaView.isHidden = true
            switch result {
            case .cancel, .delete:
                if let shot { ScreenshotWriter.delete(shot) }
            case let .save(comment, intent):
                let annotation = Annotation(
                    id: id, captured: element, comment: comment, intent: intent, screen: screen,
                    anchor: anchor, windowSize: windowSize, screenshotPath: shot, url: AppInfo.url(for: screen))
                self.store.add(annotation)
                self.config.onAnnotationAdd?(annotation)
                self.rebuildMarkers()
                self.push(annotation)
            }
        }
    }

    private func edit(_ id: String) {
        guard let original = store.annotation(id: id) else { return }
        let title = original.isArea ? "Area on \(original.screen)" : original.element
        presentEditor(title: title, subtitle: original.elementPath, comment: original.comment,
                      intent: original.intent, allowsDelete: true) { [weak self] result in
            guard let self else { return }
            switch result {
            case .cancel:
                break
            case let .save(comment, intent):
                guard var updated = self.store.annotation(id: id) else { return }
                updated.comment = comment
                updated.intent = intent
                self.store.update(updated)
                self.rebuildMarkers()
                self.pushUpdate(updated)
            case .delete:
                self.remove([original])
            }
        }
    }

    private func presentEditor(title: String, subtitle: String?, comment: String, intent: Intent?, allowsDelete: Bool,
                               completion: @escaping (AnnotationEditorViewController.Result) -> Void) {
        guard presentedViewController == nil else { return }
        overlayWindow?.makeKey()
        let editor = AnnotationEditorViewController(
            title: title, subtitle: subtitle, comment: comment, intent: intent,
            allowsDelete: allowsDelete, completion: completion)
        present(editor, animated: true)
    }

    private func remove(_ annotations: [Annotation]) {
        for annotation in annotations {
            store.remove(id: annotation.id)
            if let shot = annotation.screenshotPath { ScreenshotWriter.delete(shot) }
            if let serverId = annotation.serverId { remoteDelete(serverId) }
        }
        rebuildMarkers()
    }

    func copyAll() {
        let all = store.annotations
        guard !all.isEmpty else {
            toast.show("No annotations yet")
            return
        }
        let markdown = MarkdownFormatter.document(
            all,
            appName: config.appName ?? AppInfo.displayName,
            bundleID: AppInfo.bundleID,
            device: DeviceInfo.current(window: appWindow()))
        UIPasteboard.general.string = markdown
        config.onCopy?(markdown)
        toast.show(all.count == 1 ? "Copied 1 annotation" : "Copied \(all.count) annotations")
    }

    private func confirmClear() {
        let all = store.annotations
        guard !all.isEmpty else {
            toast.show("Nothing to clear")
            return
        }
        let onScreen = all.filter { $0.screen == currentScreen }
        let alert = UIAlertController(title: "Clear annotations?", message: nil, preferredStyle: .actionSheet)
        if !onScreen.isEmpty {
            alert.addAction(UIAlertAction(title: "This screen (\(onScreen.count))", style: .destructive) { [weak self] _ in
                self?.remove(onScreen)
            })
        }
        alert.addAction(UIAlertAction(title: "All screens (\(all.count))", style: .destructive) { [weak self] _ in
            self?.remove(all)
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.popoverPresentationController?.sourceView = toolbar
        alert.popoverPresentationController?.sourceRect = toolbar.bounds
        present(alert, animated: true)
    }

    // MARK: - Markers

    private func refreshScreen(force: Bool = false) {
        guard let window = appWindow() else { return }
        let name = ScreenResolver.screenName(in: window)
        if force || name != currentScreen {
            currentScreen = name
            rebuildMarkers()
            UIView.animate(withDuration: 0.2) { self.layoutToolbar() }
        }
    }

    private func rebuildMarkers() {
        markersContainer.subviews.forEach { $0.removeFromSuperview() }
        let all = store.annotations
        for (index, annotation) in all.enumerated() where annotation.screen == currentScreen {
            let marker = MarkerView(number: index + 1, intent: annotation.intent)
            marker.annotationID = annotation.id
            let id = annotation.id
            marker.addAction(UIAction { [weak self] _ in self?.edit(id) }, for: .touchUpInside)
            markersContainer.addSubview(marker)
        }
        layoutMarkers()
        toolbar.setCount(all.count)
    }

    private func layoutMarkers() {
        let bounds = view.bounds
        let window = appWindow()
        for case let marker as MarkerView in markersContainer.subviews {
            guard let annotation = store.annotation(id: marker.annotationID) else { continue }
            var point = CGPoint(x: CGFloat(annotation.x) / 100 * bounds.width, y: CGFloat(annotation.y))
            if let window { point = appPointToOverlay(point, window) }
            marker.center = CGPoint(x: min(max(point.x, 14), bounds.width - 14),
                                    y: min(max(point.y, 14), bounds.height - 14))
        }
    }

    // MARK: - Toolbar layout

    /// Area the toolbar stays inside. Uses the app's own safe area when it is smaller,
    /// so the toolbar sits above tab bars and toolbars instead of covering them.
    private var toolbarSafeArea: CGRect {
        var safe = view.bounds.inset(by: view.safeAreaInsets)
        if let window = appWindow(), let content = appTopViewController?.view, content.window === window {
            let appSafe = appRectToOverlay(content.convert(content.safeAreaLayoutGuide.layoutFrame, to: nil), window)
            let narrowed = safe.intersection(appSafe)
            // Ignore odd results, e.g. a screen that is mid-transition.
            if !narrowed.isNull, narrowed.height > safe.height * 0.5, narrowed.width > safe.width * 0.5 { safe = narrowed }
        }
        return safe.insetBy(dx: 12, dy: 8)
    }

    private func layoutToolbar() {
        let size = toolbar.fittingSize
        let safe = toolbarSafeArea
        let anchor = toolbarAnchor ?? defaultToolbarAnchor(in: safe)
        let right = anchor.x > safe.midX
        let bottom = anchor.y > safe.midY
        var origin = CGPoint(x: right ? anchor.x - size.width : anchor.x,
                             y: bottom ? anchor.y - size.height : anchor.y)
        origin.x = min(max(origin.x, safe.minX), max(safe.maxX - size.width, safe.minX))
        origin.y = min(max(origin.y, safe.minY), max(safe.maxY - size.height, safe.minY))
        toolbar.frame = CGRect(origin: origin, size: size)
    }

    private func defaultToolbarAnchor(in safe: CGRect) -> CGPoint {
        switch config.toolbarPosition {
        case .bottomTrailing: return CGPoint(x: safe.maxX, y: safe.maxY)
        case .bottomLeading: return CGPoint(x: safe.minX, y: safe.maxY)
        case .topTrailing: return CGPoint(x: safe.maxX, y: safe.minY)
        case .topLeading: return CGPoint(x: safe.minX, y: safe.minY)
        }
    }

    private func handleToolbarDrag(_ gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in: view)
        toolbar.center = CGPoint(x: toolbar.center.x + translation.x, y: toolbar.center.y + translation.y)
        gesture.setTranslation(.zero, in: view)
        if gesture.state == .ended || gesture.state == .cancelled {
            let safe = toolbarSafeArea
            let frame = toolbar.frame
            toolbarAnchor = CGPoint(x: frame.midX > safe.midX ? frame.maxX : frame.minX,
                                    y: frame.midY > safe.midY ? frame.maxY : frame.minY)
            UIView.animate(withDuration: 0.2) { self.layoutToolbar() }
        }
    }

    // MARK: - Keyboard

    override var canBecomeFirstResponder: Bool { true }

    override var keyCommands: [UIKeyCommand]? {
        guard config.enableKeyCommands, isExpanded, presentedViewController == nil else { return nil }
        let commands = [
            UIKeyCommand(title: "Inspect", action: #selector(keyInspect), input: "i"),
            UIKeyCommand(title: "Annotate", action: #selector(keyAnnotate), input: "a"),
            UIKeyCommand(title: "Copy annotations", action: #selector(keyCopy), input: "c"),
            UIKeyCommand(title: "Close", action: #selector(keyEscape), input: UIKeyCommand.inputEscape),
        ]
        commands.forEach { $0.wantsPriorityOverSystemBehavior = true }
        return commands
    }

    @objc private func keyInspect() { toggle(.inspect) }
    @objc private func keyAnnotate() { toggle(.annotate) }
    @objc private func keyCopy() { copyAll() }

    @objc private func keyEscape() {
        if !inspectPanel.isHidden {
            inspectPanel.hide()
            highlightView.hide()
        } else if mode != .off {
            setMode(.off)
        } else {
            setExpanded(false)
        }
    }

    // MARK: - Timer

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        ticks += 1
        refreshScreen()
        if ticks % 4 == 0 { pollServer() }
    }

    // MARK: - Sync

    private func push(_ annotation: Annotation) {
        guard let sync, !inFlight.contains(annotation.id) else { return }
        inFlight.insert(annotation.id)
        Task { @MainActor [weak self] in
            do {
                let serverId = try await sync.create(annotation)
                guard let self else { return }
                self.inFlight.remove(annotation.id)
                self.syncSucceeded()
                guard let current = self.store.annotation(id: annotation.id) else {
                    // Deleted while the request was in flight.
                    self.remoteDelete(serverId)
                    return
                }
                self.store.setServerId(serverId, for: annotation.id)
                if current.comment != annotation.comment || current.intent != annotation.intent {
                    var updated = current
                    updated.serverId = serverId
                    self.pushUpdate(updated)
                }
            } catch {
                self?.inFlight.remove(annotation.id)
                self?.syncFailed(error)
            }
        }
    }

    private func pushUpdate(_ annotation: Annotation) {
        guard let sync, let serverId = annotation.serverId else { return }
        Task { @MainActor [weak self] in
            do {
                try await sync.update(serverId: serverId, with: annotation)
                self?.syncSucceeded()
            } catch {
                self?.syncFailed(error)
            }
        }
    }

    private func remoteDelete(_ serverId: String) {
        guard let sync else { return }
        Task { @MainActor [weak self] in
            do {
                try await sync.delete(serverId: serverId)
            } catch {
                self?.syncFailed(error)
            }
        }
    }

    private func pollServer() {
        guard let sync else { return }
        for annotation in store.annotations where annotation.serverId == nil {
            push(annotation)
        }
        Task { @MainActor [weak self] in
            do {
                let statuses = try await sync.fetchStatuses()
                self?.applyStatuses(statuses)
                self?.syncSucceeded()
            } catch {
                self?.syncFailed(error)
            }
        }
    }

    /// Removes annotations the agent resolved or dismissed.
    private func applyStatuses(_ statuses: [String: String]) {
        let done = store.annotations.filter { annotation in
            guard let serverId = annotation.serverId, let status = statuses[serverId] else { return false }
            return status == "resolved" || status == "dismissed"
        }
        guard !done.isEmpty else { return }
        for annotation in done {
            store.remove(id: annotation.id)
            if let shot = annotation.screenshotPath { ScreenshotWriter.delete(shot) }
        }
        rebuildMarkers()
        toast.show(done.count == 1 ? "1 annotation resolved by your agent" : "\(done.count) annotations resolved by your agent")
    }

    private func syncSucceeded() {
        syncFailing = false
        toolbar.setSyncState(.connected)
    }

    private func syncFailed(_ error: Error) {
        toolbar.setSyncState(.failing)
        guard !syncFailing else { return }
        syncFailing = true
        let endpoint = sync?.endpoint.absoluteString ?? ""
        toast.show("Can't reach agentation-mcp at \(endpoint)")
        print("[Agentation] Sync failed: \(error)")
    }
}
#endif
