import SwiftUI

#if os(macOS)
import AppKit
#endif

extension Notification.Name {
    static let saveCurrentArtwork = Notification.Name("LittleColorist.saveCurrentArtwork")
}

@main
struct LittleColoristApp: App {
    var body: some Scene {
#if os(macOS)
        WindowGroup("小小涂色家") {
            ContentView()
                .frame(minWidth: 980, minHeight: 680)
        }
        .defaultSize(width: 1440, height: 900)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .help) {
                Link("隐私说明", destination: URL(string: "https://qq1592263515.github.io/little-colorist-support/privacy.html")!)
            }
            CommandGroup(after: .saveItem) {
                Button("保存当前作品…") {
                    NotificationCenter.default.post(name: .saveCurrentArtwork, object: nil)
                }
                .keyboardShortcut("s", modifiers: .command)
            }
        }
#else
        WindowGroup {
            ContentView()
                .ignoresSafeArea()
        }
#endif
    }
}
