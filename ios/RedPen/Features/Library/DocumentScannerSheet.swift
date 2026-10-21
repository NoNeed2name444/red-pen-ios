import SwiftUI
#if canImport(VisionKit) && !SWIFT_PACKAGE
import VisionKit
#endif

/// The system document camera, for "From a photo or scan".
///
/// Only in the Xcode build. The Swift Playgrounds package has no Info.plist of
/// its own for a rear-camera purpose, so there the button is simply not
/// shown and Photos and Files do the job. `isAvailable` also says no on a
/// device that cannot scan (the Simulator, a Mac running the iPad app).
enum DocumentScanning {
    static var isAvailable: Bool {
        #if canImport(VisionKit) && !SWIFT_PACKAGE
        return VNDocumentCameraViewController.isSupported
        #else
        return false
        #endif
    }
}

#if canImport(VisionKit) && !SWIFT_PACKAGE
/// VisionKit's scanner: finds the page's edges, flattens it and evens the
/// light. Hands back every page scanned, in order.
struct DocumentScannerSheet: UIViewControllerRepresentable {
    let onFinish: ([UIImage]) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish, onCancel: onCancel)
    }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: VNDocumentCameraViewController, context: Context) {}

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let onFinish: ([UIImage]) -> Void
        let onCancel: () -> Void

        init(onFinish: @escaping ([UIImage]) -> Void, onCancel: @escaping () -> Void) {
            self.onFinish = onFinish
            self.onCancel = onCancel
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                          didFinishWith scan: VNDocumentCameraScan) {
            var pages: [UIImage] = []
            // ten pages is a lecture handout; more is a book, and each page
            // is seconds of reading
            let count: Int = min(scan.pageCount, PictureFromPhotoView.pageLimit)
            for index in 0..<count {
                pages.append(scan.imageOfPage(at: index))
            }
            onFinish(pages)
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            onCancel()
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                          didFailWithError error: Error) {
            onCancel()
        }
    }
}
#endif
