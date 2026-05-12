import AppKit

@main
struct R2TransMain {
    @MainActor private static let delegate = AppDelegate()

    @MainActor
    static func main() {
        let app = NSApplication.shared

        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }
}
