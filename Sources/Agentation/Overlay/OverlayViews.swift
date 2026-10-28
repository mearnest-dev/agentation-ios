#if os(iOS)
import UIKit

enum OverlayMode {
    case off, inspect, annotate
}

enum SyncState {
    case disabled, unknown, connected, failing
}

/// Window above the app. Touches that don't land on Agentation's own controls fall through to the app.
final class PassthroughWindow: UIWindow {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        if hit === self || hit is PassthroughView { return nil }
        return hit
    }
}

/// A container that never takes touches itself; only its subviews do.
/// Returning nil lets hit-testing continue to siblings underneath, such as the selection layer.
class PassthroughView: UIView {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        return hit === self ? nil : hit
    }
}

class PaddedLabel: UILabel {
    var insets = UIEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)

    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: insets))
    }

    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(width: size.width + insets.left + insets.right, height: size.height + insets.top + insets.bottom)
    }
}

/// Outline drawn around the selected element.
final class HighlightView: UIView {
    private let caption = PaddedLabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isHidden = true
        layer.borderWidth = 2
        layer.cornerRadius = 4
        caption.font = .monospacedSystemFont(ofSize: 11, weight: .semibold)
        caption.textColor = .white
        caption.layer.cornerRadius = 4
        caption.clipsToBounds = true
        caption.insets = UIEdgeInsets(top: 2, left: 6, bottom: 2, right: 6)
        addSubview(caption)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func show(frame rect: CGRect, caption text: String, color: UIColor) {
        frame = rect.insetBy(dx: -2, dy: -2)
        layer.borderColor = color.cgColor
        backgroundColor = color.withAlphaComponent(0.12)
        caption.text = text
        caption.backgroundColor = color
        let size = caption.intrinsicContentSize
        // Above the outline when there is room, otherwise inside it.
        let y: CGFloat = frame.minY > size.height + 4 ? -size.height - 2 : 2
        caption.frame = CGRect(origin: CGPoint(x: 0, y: y), size: size)
        isHidden = false
    }

    func hide() {
        isHidden = true
    }
}

/// Numbered dot showing where an annotation was left.
final class MarkerView: UIButton {
    var annotationID = ""

    init(number: Int, intent: Intent?) {
        super.init(frame: CGRect(x: 0, y: 0, width: 26, height: 26))
        setTitle("\(number)", for: .normal)
        setTitleColor(.white, for: .normal)
        titleLabel?.font = .systemFont(ofSize: 12, weight: .bold)
        backgroundColor = MarkerView.color(for: intent)
        layer.cornerRadius = 13
        layer.borderWidth = 2
        layer.borderColor = UIColor.white.cgColor
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.3
        layer.shadowRadius = 3
        layer.shadowOffset = CGSize(width: 0, height: 1)
        accessibilityLabel = "Annotation \(number)"
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    static func color(for intent: Intent?) -> UIColor {
        switch intent {
        case .bug: return .systemRed
        case .style: return .systemPurple
        case .feature: return .systemGreen
        case .content: return .systemOrange
        case nil: return .systemBlue
        }
    }
}

/// Short message at the top of the screen.
final class ToastView: PaddedLabel {
    private var hideWork: DispatchWorkItem?

    override init(frame: CGRect) {
        super.init(frame: frame)
        insets = UIEdgeInsets(top: 8, left: 14, bottom: 8, right: 14)
        font = .systemFont(ofSize: 13, weight: .semibold)
        textColor = .white
        backgroundColor = UIColor.black.withAlphaComponent(0.82)
        textAlignment = .center
        numberOfLines = 2
        layer.cornerRadius = 14
        clipsToBounds = true
        alpha = 0
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func show(_ message: String) {
        text = message
        hideWork?.cancel()
        UIView.animate(withDuration: 0.15) { self.alpha = 1 }
        let work = DispatchWorkItem { [weak self] in
            UIView.animate(withDuration: 0.3) { self?.alpha = 0 }
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2, execute: work)
    }
}

/// Floating toolbar. Collapsed it is one button; expanded it shows the mode and action buttons.
final class ToolbarView: UIView {
    var onExpand: (() -> Void)?
    var onCollapse: (() -> Void)?
    var onInspect: (() -> Void)?
    var onAnnotate: (() -> Void)?
    var onCopy: (() -> Void)?
    var onClear: (() -> Void)?
    var onDrag: ((UIPanGestureRecognizer) -> Void)?

    private let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterialDark))
    private let stack = UIStackView()
    private let mainButton = ToolbarView.makeButton("square.and.pencil", "Show Agentation")
    private let inspectButton = ToolbarView.makeButton("scope", "Inspect")
    private let annotateButton = ToolbarView.makeButton("text.bubble", "Annotate")
    private let copyButton = ToolbarView.makeButton("doc.on.doc", "Copy annotations")
    private let clearButton = ToolbarView.makeButton("trash", "Clear annotations")
    private let closeButton = ToolbarView.makeButton("xmark", "Hide Agentation")
    private let badge = PaddedLabel()
    private let syncDot = UIView()
    private let syncDotContainer = UIView()
    private var syncState: SyncState = .disabled
    private var expanded = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.25
        layer.shadowRadius = 8
        layer.shadowOffset = CGSize(width: 0, height: 2)

        blur.translatesAutoresizingMaskIntoConstraints = false
        blur.clipsToBounds = true
        addSubview(blur)

        stack.axis = .horizontal
        stack.spacing = 2
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        blur.contentView.addSubview(stack)

        syncDot.translatesAutoresizingMaskIntoConstraints = false
        syncDot.layer.cornerRadius = 4
        syncDotContainer.translatesAutoresizingMaskIntoConstraints = false
        syncDotContainer.addSubview(syncDot)
        syncDotContainer.accessibilityLabel = "Sync status"

        for view in [mainButton, inspectButton, annotateButton, copyButton, clearButton, syncDotContainer, closeButton] {
            stack.addArrangedSubview(view)
        }

        badge.font = .systemFont(ofSize: 10, weight: .bold)
        badge.textColor = .white
        badge.backgroundColor = .systemRed
        badge.insets = UIEdgeInsets(top: 1, left: 4, bottom: 1, right: 4)
        badge.layer.cornerRadius = 8
        badge.clipsToBounds = true
        badge.translatesAutoresizingMaskIntoConstraints = false
        badge.isHidden = true
        mainButton.addSubview(badge)

        NSLayoutConstraint.activate([
            blur.leadingAnchor.constraint(equalTo: leadingAnchor),
            blur.trailingAnchor.constraint(equalTo: trailingAnchor),
            blur.topAnchor.constraint(equalTo: topAnchor),
            blur.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: blur.contentView.leadingAnchor, constant: 4),
            stack.trailingAnchor.constraint(equalTo: blur.contentView.trailingAnchor, constant: -4),
            stack.topAnchor.constraint(equalTo: blur.contentView.topAnchor, constant: 4),
            stack.bottomAnchor.constraint(equalTo: blur.contentView.bottomAnchor, constant: -4),
            syncDotContainer.widthAnchor.constraint(equalToConstant: 14),
            syncDotContainer.heightAnchor.constraint(equalToConstant: 40),
            syncDot.widthAnchor.constraint(equalToConstant: 8),
            syncDot.heightAnchor.constraint(equalToConstant: 8),
            syncDot.centerXAnchor.constraint(equalTo: syncDotContainer.centerXAnchor),
            syncDot.centerYAnchor.constraint(equalTo: syncDotContainer.centerYAnchor),
            badge.topAnchor.constraint(equalTo: mainButton.topAnchor, constant: 2),
            badge.trailingAnchor.constraint(equalTo: mainButton.trailingAnchor, constant: -2),
            badge.heightAnchor.constraint(equalToConstant: 16),
            badge.widthAnchor.constraint(greaterThanOrEqualToConstant: 16),
        ])

        mainButton.addAction(UIAction { [weak self] _ in self?.onExpand?() }, for: .touchUpInside)
        inspectButton.addAction(UIAction { [weak self] _ in self?.onInspect?() }, for: .touchUpInside)
        annotateButton.addAction(UIAction { [weak self] _ in self?.onAnnotate?() }, for: .touchUpInside)
        copyButton.addAction(UIAction { [weak self] _ in self?.onCopy?() }, for: .touchUpInside)
        clearButton.addAction(UIAction { [weak self] _ in self?.onClear?() }, for: .touchUpInside)
        closeButton.addAction(UIAction { [weak self] _ in self?.onCollapse?() }, for: .touchUpInside)

        addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:))))
        setExpanded(false)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        blur.layer.cornerRadius = bounds.height / 2
    }

    var fittingSize: CGSize {
        systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
    }

    func setExpanded(_ value: Bool) {
        expanded = value
        mainButton.isHidden = value
        for button in [inspectButton, annotateButton, copyButton, clearButton, closeButton] {
            button.isHidden = !value
        }
        syncDotContainer.isHidden = !value || syncState == .disabled
    }

    func setActiveMode(_ mode: OverlayMode) {
        setActive(inspectButton, mode == .inspect, color: .systemBlue)
        setActive(annotateButton, mode == .annotate, color: .systemOrange)
    }

    func setCount(_ count: Int) {
        badge.text = "\(count)"
        badge.isHidden = count == 0
        copyButton.accessibilityValue = "\(count) annotations"
    }

    func setSyncState(_ state: SyncState) {
        syncState = state
        switch state {
        case .disabled, .unknown: syncDot.backgroundColor = .systemGray
        case .connected: syncDot.backgroundColor = .systemGreen
        case .failing: syncDot.backgroundColor = .systemRed
        }
        syncDotContainer.isHidden = !expanded || state == .disabled
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        onDrag?(gesture)
    }

    private func setActive(_ button: UIButton, _ active: Bool, color: UIColor) {
        button.configuration?.background.backgroundColor = active ? color : .clear
    }

    private static func makeButton(_ symbol: String, _ label: String) -> UIButton {
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(
            systemName: symbol,
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold))
        configuration.baseForegroundColor = .white
        configuration.cornerStyle = .capsule
        let button = UIButton(configuration: configuration)
        button.accessibilityLabel = label
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 40),
            button.heightAnchor.constraint(equalToConstant: 40),
        ])
        return button
    }
}

/// Card that shows inspect output for the tapped element.
final class InspectPanelView: UIView {
    var onCopy: (() -> Void)?
    var onAnnotate: (() -> Void)?
    var onClose: (() -> Void)?

    private let textLabel = UILabel()
    private let scrollView = UIScrollView()
    private(set) var text = ""

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor.secondarySystemBackground.withAlphaComponent(0.97)
        layer.cornerRadius = 14
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.2
        layer.shadowRadius = 10
        isHidden = true

        textLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        textLabel.textColor = .label
        textLabel.numberOfLines = 0
        textLabel.translatesAutoresizingMaskIntoConstraints = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(textLabel)

        func button(_ title: String, _ handler: @escaping () -> Void) -> UIButton {
            var configuration = UIButton.Configuration.tinted()
            configuration.title = title
            configuration.buttonSize = .small
            return UIButton(configuration: configuration, primaryAction: UIAction { _ in handler() })
        }
        let copy = button("Copy") { [weak self] in self?.onCopy?() }
        let annotate = button("Annotate") { [weak self] in self?.onAnnotate?() }
        let close = button("Close") { [weak self] in self?.onClose?() }
        let spacer = UIView()
        let buttons = UIStackView(arrangedSubviews: [copy, annotate, spacer, close])
        buttons.axis = .horizontal
        buttons.spacing = 8

        let stack = UIStackView(arrangedSubviews: [scrollView, buttons])
        stack.axis = .vertical
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        let fitHeight = scrollView.heightAnchor.constraint(equalTo: textLabel.heightAnchor)
        fitHeight.priority = .defaultHigh
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
            textLabel.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            textLabel.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            textLabel.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            textLabel.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            textLabel.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            fitHeight,
            scrollView.heightAnchor.constraint(lessThanOrEqualToConstant: 220),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func show(text: String) {
        self.text = text
        textLabel.text = text
        scrollView.contentOffset = .zero
        isHidden = false
    }

    func hide() {
        isHidden = true
    }
}
#endif
