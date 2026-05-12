import AppKit

@MainActor
final class TranslationProgressWindowController: NSWindowController {
    private let progressIndicator = NSProgressIndicator()
    private let label = NSTextField(labelWithString: AppText.text(.translating))

    init() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 220, height: 82),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]

        super.init(window: panel)

        setupContent(in: panel)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func showProgress() {
        guard let window else {
            return
        }

        label.stringValue = AppText.text(.translating)
        centerWindow(window)
        progressIndicator.startAnimation(nil)
        window.orderFrontRegardless()
    }

    func hideProgress() {
        progressIndicator.stopAnimation(nil)
        window?.orderOut(nil)
    }

    private func setupContent(in panel: NSPanel) {
        let container = NSVisualEffectView()
        container.material = .hudWindow
        container.blendingMode = .behindWindow
        container.state = .active
        container.wantsLayer = true
        container.layer?.cornerRadius = 12
        container.layer?.masksToBounds = true
        container.translatesAutoresizingMaskIntoConstraints = false

        progressIndicator.style = .spinning
        progressIndicator.controlSize = .regular
        progressIndicator.translatesAutoresizingMaskIntoConstraints = false

        label.font = .systemFont(ofSize: 15, weight: .semibold)
        label.textColor = .labelColor
        label.translatesAutoresizingMaskIntoConstraints = false

        let stackView = NSStackView(views: [progressIndicator, label])
        stackView.orientation = .horizontal
        stackView.alignment = .centerY
        stackView.spacing = 12
        stackView.translatesAutoresizingMaskIntoConstraints = false

        panel.contentView = container
        container.addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            stackView.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])
    }

    private func centerWindow(_ window: NSWindow) {
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let frame = window.frame
        let origin = NSPoint(
            x: screenFrame.midX - frame.width / 2,
            y: screenFrame.midY - frame.height / 2
        )

        window.setFrameOrigin(origin)
    }
}
