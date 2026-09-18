import Foundation

/// Getting the offline model onto the phone.
///
/// Two files, downloaded one after the other and reported as one bar, because
/// to the student it is one thing: either the app can write questions without
/// Apple Intelligence or it cannot.
extension GemmaModel {

    func download() {
        guard downloadTask == nil else { return }
        setStatus(.downloading(fraction: 0))
        downloadTask = Task {
            do {
                try FileManager.default.createDirectory(at: Self.modelsDirectory,
                                                        withIntermediateDirectories: true)
                let total = Double(Self.approxTotalDownloadBytes)
                let textWeight = Double(Self.approxDownloadBytes) / total
                let mmprojWeight = Double(Self.approxMmprojDownloadBytes) / total

                // each file lands beside its final name first: a download
                // interrupted halfway must not leave something that looks
                // complete enough to load
                let textTmp = Self.modelsDirectory.appendingPathComponent(Self.filename + ".part")
                try await Self.download(from: Self.downloadURL, to: textTmp) { fraction in
                    Task { @MainActor in self.setStatus(.downloading(fraction: fraction * textWeight)) }
                }
                try Task.checkCancellation()
                try Self.replace(Self.localURL, with: textTmp)

                let mmprojTmp = Self.modelsDirectory.appendingPathComponent(Self.mmprojFilename + ".part")
                try await Self.download(from: Self.mmprojDownloadURL, to: mmprojTmp) { fraction in
                    Task { @MainActor in
                        self.setStatus(.downloading(fraction: textWeight + fraction * mmprojWeight))
                    }
                }
                try Task.checkCancellation()
                try Self.replace(Self.mmprojLocalURL, with: mmprojTmp)

                await MainActor.run { self.setStatus(.ready) }
            } catch is CancellationError {
                await MainActor.run {
                    self.setStatus(Self.isDownloaded ? .ready : .notDownloaded)
                }
            } catch {
                await MainActor.run { self.setStatus(.failed(error.localizedDescription)) }
            }
            await MainActor.run { self.downloadTask = nil }
        }
    }

    func cancelDownload() {
        downloadTask?.cancel()
    }

    static func replace(_ destination: URL, with temporary: URL) throws {
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: temporary, to: destination)
    }

    /// A plain URLSession download with progress - no networking dependency,
    /// just the delegate API URLSession has always had for exactly this.
    static func download(from url: URL, to destination: URL,
                         onProgress: @escaping (Double) -> Void) async throws {
        let delegate = DownloadProgressDelegate(onProgress: onProgress)
        let (tempFileURL, response) = try await URLSession.shared.download(from: url, delegate: delegate)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw GenerationError.underlying("Download failed (HTTP \(http.statusCode)).")
        }
        try replace(destination, with: tempFileURL)
    }
}

/// URLSessionDownloadDelegate does not hand back progress through async/await
/// on its own; this bridges its callbacks to the fraction the download UI wants.
final class DownloadProgressDelegate: NSObject, URLSessionDownloadDelegate, URLSessionTaskDelegate {
    private let onProgress: (Double) -> Void
    init(onProgress: @escaping (Double) -> Void) { self.onProgress = onProgress }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        onProgress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        // handled by the async download(from:delegate:) call, which returns
        // this same temporary URL
    }
}
