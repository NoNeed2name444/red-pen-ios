import SwiftUI
import UIKit

/// A thin SwiftUI wrapper around `UIActivityViewController` — SwiftUI has
/// no native "share this file" sheet, so this is the standard bridge.
/// Used to hand the PDF `PDFExporter` builds to Mail, Files, AirDrop, etc.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
