import SwiftUI
import WebKit

struct ProviderLoginView: View {
    let provider: ProviderAccount
    @Bindable var sessionStore: ProviderSessionStore
    @Environment(\.dismiss) private var dismiss
    @State private var currentURL: URL?
    @State private var isLoading = true
    @State private var loadError: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "lock.shield")
                        .foregroundStyle(AnyTravelPalette.route)
                    Text("账号与密码只会送往\(provider.title)页面；AnyTravel 不会读取你输入的内容。")
                        .font(.caption)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 14)
                .frame(minHeight: 48)
                .background(AnyTravelPalette.softSurface)

                ZStack {
                    ProviderWebView(
                        provider: provider,
                        currentURL: $currentURL,
                        isLoading: $isLoading,
                        loadError: $loadError
                    )
                    if isLoading {
                        ProgressView("正在前往\(provider.title)")
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
            .navigationTitle("连接\(provider.title)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存此会话") {
                        sessionStore.markSessionReady(provider)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

private struct ProviderWebView: UIViewRepresentable {
    let provider: ProviderAccount
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
        webView.load(URLRequest(url: provider.loginURL))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        var parent: ProviderWebView

        init(parent: ProviderWebView) {
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
