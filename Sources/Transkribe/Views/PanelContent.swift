import AppKit
import SwiftUI

extension NSPanel {
    /// Shows SwiftUI in a panel whose frame we set ourselves (the notch island, the dictation pill).
    ///
    /// The hosting view sits inside a plain container rather than being the content view. When it is
    /// the content view, SwiftUI clamps the window to the root view's size on every window layout,
    /// and while a spring animates the island it resizes the window mid-layout. Each resize asks for
    /// another constraints pass, and a window with this few views is only allowed a couple of those,
    /// so AppKit aborts the app ("more Update Constraints in Window passes than there are views").
    func setSwiftUIContent<Content: View>(_ view: Content) {
        let host = NSHostingView(rootView: view)
        host.sizingOptions = []
        let container = NSView(frame: contentView?.bounds ?? .zero)
        host.frame = container.bounds
        host.autoresizingMask = [.width, .height]
        container.addSubview(host)
        contentView = container
    }
}
