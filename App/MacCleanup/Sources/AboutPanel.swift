import Analysis
import AppKit

enum AboutPanel {
    @MainActor
    static func present() {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let credits = NSAttributedString(
            string: AboutCopy.credits,
            attributes: [
                .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paragraph,
            ]
        )
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "mac-cleanup",
            .credits: credits,
        ])
    }
}
