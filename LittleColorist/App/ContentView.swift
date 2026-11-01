import SwiftUI

struct ContentView: View {
    @StateObject private var model = GameWebModel()

    var body: some View {
        ZStack {
            Color(red: 0.98, green: 0.97, blue: 0.95)
                .ignoresSafeArea()

            OfflineGameView(model: model)

            if model.isLoading {
                LoadingView()
                    .transition(.opacity)
            }

            if let error = model.loadError {
                ErrorView(message: error) {
                    model.retry()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .saveCurrentArtwork)) { _ in
            model.saveCurrentArtwork()
        }
    }
}

private struct LoadingView: View {
    var body: some View {
        VStack(spacing: 18) {
            ProgressView()
                .controlSize(.large)
                .tint(Color(red: 0.54, green: 0.65, blue: 0.48))
            Text("正在打开彩色小世界…")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(Color(red: 0.42, green: 0.36, blue: 0.30))
        }
        .padding(30)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
    }
}

private struct ErrorView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "paintpalette")
                .font(.system(size: 34))
                .foregroundStyle(Color(red: 0.54, green: 0.65, blue: 0.48))
            Text("画册没有打开")
                .font(.title3.bold())
            Text(message)
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("再试一次", action: retry)
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.54, green: 0.65, blue: 0.48))
        }
        .padding(28)
        .frame(maxWidth: 390)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22))
        .padding(30)
    }
}

final class GameWebModel: ObservableObject {
    @Published var isLoading = true
    @Published var loadError: String?

    weak var webView: WKWebView?

    func didFinishLoading() {
        isLoading = false
        loadError = nil
    }

    func didFailLoading(_ message: String) {
        isLoading = false
        loadError = message
    }

    func saveCurrentArtwork() {
        webView?.evaluateJavaScript(
            "document.querySelector('.save-button')?.click();",
            completionHandler: nil
        )
    }

    func retry() {
        isLoading = true
        loadError = nil
        webView?.reload()
    }
}

#if os(macOS)
import AppKit
import WebKit
#elseif os(iOS)
import UIKit
import WebKit
#endif
