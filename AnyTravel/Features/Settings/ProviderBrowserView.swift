import SwiftUI
import WebKit

struct ProviderBrowserView: View {
    let destination: ProviderBrowserDestination
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var currentURL: URL?
    @State private var isLoading = true
    @State private var loadError: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "person.crop.circle.badge.checkmark")
                        .foregroundStyle(AnyTravelPalette.route)
                    Text("正沿用应用内的\(destination.provider.title)网页会话。最后的价格与订单，请以平台结算页为准。")
                        .font(.caption)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 14)
                .frame(minHeight: 48)
                .background(AnyTravelPalette.softSurface)

                ZStack {
                    SessionBrowserWebView(
                        initialURL: destination.url,
                        currentURL: $currentURL,
                        isLoading: $isLoading,
                        loadError: $loadError
                    )
                    if isLoading {
                        ProgressView("正在前往\(destination.title)")
                            .padding(16)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                }

                if let loadError {
                    Label(loadError, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(AnyTravelPalette.warm)
                        .padding(10)
                }
            }
            .navigationTitle(destination.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        openURL(currentURL ?? destination.url)
                    } label: {
                        Label("在浏览器中打开", systemImage: "safari")
                    }
                }
            }
        }
    }
}

private struct SessionBrowserWebView: UIViewRepresentable {
    let initialURL: URL
    @Binding var currentURL: URL?
    @Binding var isLoading: Bool
    @Binding var loadError: String?

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.load(URLRequest(url: initialURL))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        var parent: SessionBrowserWebView

        init(parent: SessionBrowserWebView) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation?) {
            parent.isLoading = true
            parent.loadError = nil
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation?) {
            parent.isLoading = false
            parent.currentURL = webView.url
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation?,
            withError error: Error
        ) {
            parent.isLoading = false
            parent.loadError = error.localizedDescription
        }
    }
}
