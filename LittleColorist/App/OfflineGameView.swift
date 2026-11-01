import SwiftUI
import WebKit

#if os(macOS)
struct OfflineGameView: NSViewRepresentable {
    @ObservedObject var model: GameWebModel

    func makeCoordinator() -> OfflineGameCoordinator {
        OfflineGameCoordinator(model: model)
    }

    func makeNSView(context: Context) -> WKWebView {
        context.coordinator.makeWebView()
    }

    func updateNSView(_ webView: WKWebView, context: Context) {}

    static func dismantleNSView(_ webView: WKWebView, coordinator: OfflineGameCoordinator) {
        coordinator.removeMessageHandler()
    }
}
#elseif os(iOS)
struct OfflineGameView: UIViewRepresentable {
    @ObservedObject var model: GameWebModel

    func makeCoordinator() -> OfflineGameCoordinator {
        OfflineGameCoordinator(model: model)
    }

    func makeUIView(context: Context) -> WKWebView {
        context.coordinator.makeWebView()
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    static func dismantleUIView(_ webView: WKWebView, coordinator: OfflineGameCoordinator) {
        coordinator.removeMessageHandler()
    }
}
#endif

final class OfflineGameCoordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    private let model: GameWebModel
    private let messageHandlerName = "littleColorNative"
    private weak var webView: WKWebView?

    init(model: GameWebModel) {
        self.model = model
    }

    func makeWebView() -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.preferences.isElementFullscreenEnabled = true
        configuration.userContentController.addUserScript(
            WKUserScript(
                source: Self.artworkBridgeScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
        )
        configuration.userContentController.add(self, name: messageHandlerName)

#if os(iOS)
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
#endif

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
#if os(macOS)
        webView.underPageBackgroundColor = NSColor(
            calibratedRed: 0.98,
            green: 0.97,
            blue: 0.95,
            alpha: 1
        )
#elseif os(iOS)
        webView.isOpaque = false
        webView.backgroundColor = .clear
#endif
        self.webView = webView
        model.webView = webView

        guard let indexURL = Bundle.main.url(forResource: "index", withExtension: "html") else {
            model.didFailLoading("应用内缺少离线画册资源，请重新安装应用。")
            return webView
        }

        let resourceDirectory = indexURL.deletingLastPathComponent()
        webView.loadFileURL(indexURL, allowingReadAccessTo: resourceDirectory)
        return webView
    }

    func removeMessageHandler() {
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: messageHandlerName)
        webView?.navigationDelegate = nil
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        model.didFinishLoading()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        model.didFailLoading(error.localizedDescription)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        model.didFailLoading(error.localizedDescription)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        model.didFailLoading("离线画册进程意外结束，请重新打开应用。")
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url,
              let scheme = url.scheme?.lowercased() else {
            decisionHandler(.allow)
            return
        }

        if scheme == "http" || scheme == "https" {
#if os(macOS)
            NSWorkspace.shared.open(url)
#elseif os(iOS)
            UIApplication.shared.open(url)
#endif
            decisionHandler(.cancel)
            return
        }

        decisionHandler(.allow)
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard message.name == messageHandlerName,
              let body = message.body as? [String: Any],
              body["type"] as? String == "artwork",
              let dataURL = body["dataURL"] as? String,
              let comma = dataURL.firstIndex(of: ","),
              let data = Data(base64Encoded: String(dataURL[dataURL.index(after: comma)...])) else {
            return
        }

        let requestedName = body["filename"] as? String ?? "我的涂色作品.png"
        let mimeType = body["mimeType"] as? String ?? "image/png"
        guard let webView else { return }
        ArtworkExporter.present(data: data, requestedName: requestedName, mimeType: mimeType, from: webView)
    }

    private static let artworkBridgeScript = #"""
    (function () {
      if (!window.webkit || !window.webkit.messageHandlers || !window.webkit.messageHandlers.littleColorNative) {
        return;
      }

      const nativeHandler = window.webkit.messageHandlers.littleColorNative;
      const originalCreateObjectURL = URL.createObjectURL.bind(URL);
      const originalRevokeObjectURL = URL.revokeObjectURL.bind(URL);
      const originalAnchorClick = HTMLAnchorElement.prototype.click;
      const objectURLs = new Map();

      URL.createObjectURL = function (object) {
        const url = originalCreateObjectURL(object);
        objectURLs.set(url, object);
        return url;
      };

      URL.revokeObjectURL = function (url) {
        objectURLs.delete(url);
        return originalRevokeObjectURL(url);
      };

      function postArtwork(dataURL, filename, mimeType) {
        nativeHandler.postMessage({
          type: "artwork",
          dataURL: dataURL,
          filename: filename,
          mimeType: mimeType
        });
      }

      function readAsDataURL(blob) {
        return new Promise(function (resolve, reject) {
          const reader = new FileReader();
          reader.onload = function () { resolve(reader.result); };
          reader.onerror = reject;
          reader.readAsDataURL(blob);
        });
      }

      async function rasterizeSVG(blob) {
        const source = await blob.text();
        const svgBlob = new Blob([source], { type: "image/svg+xml;charset=utf-8" });
        const svgURL = originalCreateObjectURL(svgBlob);

        try {
          const image = await new Promise(function (resolve, reject) {
            const img = new Image();
            img.onload = function () { resolve(img); };
            img.onerror = reject;
            img.src = svgURL;
          });

          const canvas = document.createElement("canvas");
          canvas.width = 1200;
          canvas.height = 1040;
          const context = canvas.getContext("2d");
          context.fillStyle = "#fffdf8";
          context.fillRect(0, 0, canvas.width, canvas.height);
          context.drawImage(image, 0, 0, canvas.width, canvas.height);
          return canvas.toDataURL("image/png");
        } finally {
          originalRevokeObjectURL(svgURL);
        }
      }

      HTMLAnchorElement.prototype.click = function () {
        const blob = objectURLs.get(this.href);
        if (!this.download || !this.href.startsWith("blob:") || !blob) {
          return originalAnchorClick.call(this);
        }

        const fallbackName = this.download || "我的涂色作品.svg";

        Promise.resolve().then(async function () {
          try {
            const pngDataURL = await rasterizeSVG(blob);
            const pngName = fallbackName.replace(/\.svg$/i, ".png");
            postArtwork(pngDataURL, pngName, "image/png");
          } catch (error) {
            const svgDataURL = await readAsDataURL(blob);
            postArtwork(svgDataURL, fallbackName, "image/svg+xml");
          }
        });
      };
    })();
    """#
}

#if os(macOS)
import AppKit
import UniformTypeIdentifiers

private enum ArtworkExporter {
    static func present(data: Data, requestedName: String, mimeType: String, from webView: WKWebView) {
        guard let window = webView.window else { return }

        let isPNG = mimeType == "image/png"
        let panel = NSSavePanel()
        panel.title = "保存涂色作品"
        panel.prompt = "保存"
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [isPNG ? .png : .svg]
        panel.nameFieldStringValue = sanitizedFilename(requestedName, fallbackExtension: isPNG ? "png" : "svg")

        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let destination = panel.url else { return }
            do {
                try data.write(to: destination, options: .atomic)
            } catch {
                let alert = NSAlert()
                alert.messageText = "作品没有保存成功"
                alert.informativeText = error.localizedDescription
                alert.alertStyle = .warning
                alert.runModal()
            }
        }
    }

    private static func sanitizedFilename(_ name: String, fallbackExtension: String) -> String {
        let invalid = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        let cleaned = name.components(separatedBy: invalid).joined()
        let stripped = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        if stripped.isEmpty {
            return "我的涂色作品.\(fallbackExtension)"
        }
        return stripped.contains(".") ? stripped : "\(stripped).\(fallbackExtension)"
    }
}
#elseif os(iOS)
import UIKit

private enum ArtworkExporter {
    static func present(data: Data, requestedName: String, mimeType: String, from webView: WKWebView) {
        guard let rootController = webView.window?.rootViewController else { return }
        var presenter = rootController
        while let presented = presenter.presentedViewController {
            presenter = presented
        }

        let activity: UIActivityViewController
        if mimeType == "image/png", let image = UIImage(data: data) {
            activity = UIActivityViewController(activityItems: [image], applicationActivities: nil)
        } else {
            let safeName = requestedName.isEmpty ? "我的涂色作品.svg" : requestedName
            let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(safeName)
            do {
                try data.write(to: fileURL, options: .atomic)
                activity = UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)
            } catch {
                showError(error.localizedDescription, from: presenter)
                return
            }
        }

        if let popover = activity.popoverPresentationController {
            popover.sourceView = webView
            popover.sourceRect = CGRect(
                x: webView.bounds.midX,
                y: webView.bounds.midY,
                width: 1,
                height: 1
            )
        }

        presenter.present(activity, animated: true)
    }

    private static func showError(_ message: String, from presenter: UIViewController) {
        let alert = UIAlertController(title: "作品没有分享成功", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "好", style: .default))
        presenter.present(alert, animated: true)
    }
}
#endif
