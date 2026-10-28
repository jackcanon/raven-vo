import SwiftUI
import AppKit

@main struct RavenVOApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = StudioModel()
    var body: some Scene {
        Window("Raven VO", id: "studio") {
            ContentView(model: model)
                .onAppear { delegate.model = model; delegate.capturePreviewIfRequested() }
        }
        .defaultSize(width: 1100, height: 800)
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandGroup(after: .appInfo) {
                Link("Raven VO Website", destination: URL(string: "https://www.ravenvo.app")!)
                Button("Licenses and credits…") {
                    if let url = Bundle.main.resourceURL?.appendingPathComponent("ThirdParty/README.md") { NSWorkspace.shared.open(url) }
                }
            }
            CommandGroup(after: .saveItem) {
                Button("Save Script") { model.saveDraft() }.keyboardShortcut("s")
            }
        }
    }
}
@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    var model: StudioModel?
    func applicationDidFinishLaunching(_ notification: Notification) {
        if let icon = Bundle.main.url(forResource: "AppIcon", withExtension: "icns") {
            NSApp.applicationIconImage = NSImage(contentsOf: icon)
        }
        NSApp.activate(ignoringOtherApps: true)
    }
    func capturePreviewIfRequested() {
        // Optional local UI-verification capture of this application's own view.
        if let index = CommandLine.arguments.firstIndex(of: "--capture-preview"), CommandLine.arguments.count > index + 1 {
            let path = CommandLine.arguments[index + 1]
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                if let view = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil })?.contentView,
                   let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                    view.cacheDisplay(in: view.bounds, to: bitmap)
                    if let data = bitmap.representation(using: .png, properties: [:]) {
                        try? data.write(to: URL(fileURLWithPath: path))
                    }
                }
            }
        }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if model?.isDeleting == true || model?.yourVoice.isRecording == true || model?.yourVoice.busy == true {
            let alert = NSAlert()
            alert.messageText = "Finish the current file operation or stop recording before quitting."
            alert.informativeText = "Your recording and saved settings will stay in your selected storage folder."
            alert.runModal()
            return .terminateCancel
        }
        if model?.isGenerating == true {
            let alert = NSAlert()
            alert.messageText = "Cancel generation and quit?"
            alert.informativeText = "Your script is saved. The current take will stop generating."
            alert.addButton(withTitle: "Keep Generating")
            alert.addButton(withTitle: "Cancel and Quit")
            if alert.runModal() == .alertFirstButtonReturn { return .terminateCancel }
        }
        model?.shutdown()
        Task { @MainActor in
            await model?.flushSettings()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
