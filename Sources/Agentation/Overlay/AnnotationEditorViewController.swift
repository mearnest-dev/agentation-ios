#if os(iOS)
import UIKit

/// Sheet for writing or editing an annotation's note and intent.
final class AnnotationEditorViewController: UIViewController, UITextViewDelegate, UIAdaptivePresentationControllerDelegate {
    enum Result {
        case save(comment: String, intent: Intent?)
        case delete
        case cancel
    }

    private let headerTitle: String
    private let headerSubtitle: String?
    private let initialComment: String
    private let initialIntent: Intent?
    private let allowsDelete: Bool
    private var completion: ((Result) -> Void)?

    private let textView = UITextView()
    private let placeholder = UILabel()
    private let intentControl = UISegmentedControl(items: ["None"] + Intent.allCases.map { $0.label })
    private var saveButton: UIButton?

    init(title: String, subtitle: String?, comment: String, intent: Intent?, allowsDelete: Bool,
         completion: @escaping (Result) -> Void) {
        self.headerTitle = title
        self.headerSubtitle = subtitle
        self.initialComment = comment
        self.initialIntent = intent
        self.allowsDelete = allowsDelete
        self.completion = completion
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .pageSheet
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        let titleLabel = UILabel()
        titleLabel.text = headerTitle
        titleLabel.font = .preferredFont(forTextStyle: .headline)

        let subtitleLabel = UILabel()
        subtitleLabel.text = headerSubtitle
        subtitleLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.numberOfLines = 2
        subtitleLabel.lineBreakMode = .byTruncatingHead
        subtitleLabel.isHidden = headerSubtitle == nil

        textView.text = initialComment
        textView.font = .preferredFont(forTextStyle: .body)
        textView.layer.borderColor = UIColor.separator.cgColor
        textView.layer.borderWidth = 1
        textView.layer.cornerRadius = 10
        textView.textContainerInset = UIEdgeInsets(top: 10, left: 6, bottom: 10, right: 6)
        textView.delegate = self
        textView.accessibilityLabel = "Note"

        placeholder.text = "What should change?"
        placeholder.font = .preferredFont(forTextStyle: .body)
        placeholder.textColor = .placeholderText
        placeholder.translatesAutoresizingMaskIntoConstraints = false
        textView.addSubview(placeholder)

        if let intent = initialIntent, let index = Intent.allCases.firstIndex(of: intent) {
            intentControl.selectedSegmentIndex = index + 1
        } else {
            intentControl.selectedSegmentIndex = 0
        }

        let cancel = UIButton(configuration: .plain(), primaryAction: UIAction(title: "Cancel") { [weak self] _ in
            self?.finish(.cancel)
        })
        let save = UIButton(configuration: .borderedProminent(), primaryAction: UIAction(title: "Save") { [weak self] _ in
            self?.save()
        })
        saveButton = save

        var rowItems: [UIView] = []
        if allowsDelete {
            var configuration = UIButton.Configuration.plain()
            configuration.baseForegroundColor = .systemRed
            rowItems.append(UIButton(configuration: configuration, primaryAction: UIAction(title: "Delete") { [weak self] _ in
                self?.finish(.delete)
            }))
        }
        rowItems.append(UIView())
        rowItems.append(cancel)
        rowItems.append(save)
        let buttonRow = UIStackView(arrangedSubviews: rowItems)
        buttonRow.axis = .horizontal
        buttonRow.spacing = 8

        let stack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel, textView, intentControl, buttonRow])
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
            textView.heightAnchor.constraint(greaterThanOrEqualToConstant: 110),
            placeholder.leadingAnchor.constraint(equalTo: textView.leadingAnchor, constant: 11),
            placeholder.topAnchor.constraint(equalTo: textView.topAnchor, constant: 10),
        ])

        if let sheet = sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }
        presentationController?.delegate = self
        refreshState()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        textView.becomeFirstResponder()
    }

    func textViewDidChange(_ textView: UITextView) {
        refreshState()
    }

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        // Swiped down.
        completion?(.cancel)
        completion = nil
    }

    private func refreshState() {
        placeholder.isHidden = !textView.text.isEmpty
        saveButton?.isEnabled = !trimmedComment.isEmpty
    }

    private var trimmedComment: String {
        textView.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func save() {
        let comment = trimmedComment
        guard !comment.isEmpty else { return }
        let index = intentControl.selectedSegmentIndex
        let intent = index > 0 ? Intent.allCases[index - 1] : nil
        finish(.save(comment: comment, intent: intent))
    }

    private func finish(_ result: Result) {
        guard let completion else { return }
        self.completion = nil
        dismiss(animated: true) { completion(result) }
    }
}
#endif
