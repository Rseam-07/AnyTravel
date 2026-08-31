import SwiftUI
import UIKit

struct ActivityShareView: UIViewControllerRepresentable {
    let payload: PlanSharePayload

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: payload.urls, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
