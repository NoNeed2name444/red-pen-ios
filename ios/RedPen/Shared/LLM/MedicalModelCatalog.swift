import Foundation

/// The medical models the app can download and run on the device, and which
/// build of each suits this particular device.
///
/// Both are GGUF files run by llama.cpp through LocalLLMClient, the same engine
/// the Gemma fallback already uses, and the same files run on Android. Neither
/// needs the tools used to train them: VeRL (Doctor-R1) and DSPy (MedVAL) are
/// training frameworks, not something a phone runs.
enum MedicalModel: String, CaseIterable, Identifiable, Hashable {
    /// Doctor-R1, 8B, trained for multi-turn clinical questioning. Writes
    /// questions and stations, and plays the patient in a case.
    case doctorR1
    /// MedVAL-4B (Stanford MIMI), grades medical text against its source:
    /// error categories plus a risk level of 1 to 4.
    case medval

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .doctorR1: return "Doctor-R1 8B"
        case .medval: return "MedVAL-4B"
        }
    }

    var purpose: String {
        switch self {
        case .doctorR1: return "Writes questions and stations, and plays the patient in Cases."
        case .medval: return "Checks generated text for hallucinations, omissions and overconfidence, with a risk level from 1 to 4."
        }
    }

    struct Variant: Hashable {
        /// Quantisation name, e.g. "Q4_K_M".
        let quant: String
        let filename: String
        let url: URL
        let bytes: Int64
        /// The least physical memory a device needs to run it without being
        /// shut down by iOS. Weights are memory-mapped, so this is the file
        /// size plus the context and working space, with a margin.
        let minimumMemoryGB: Double
    }

    /// Largest first: the first one a device has room for is the one it gets.
    var variants: [Variant] {
        switch self {
        case .doctorR1:
            let base = "https://huggingface.co/mradermacher/Doctor-R1-GGUF/resolve/main/"
            return [
                Variant(quant: "Q4_K_M", filename: "Doctor-R1.Q4_K_M.gguf",
                        url: URL(string: base + "Doctor-R1.Q4_K_M.gguf")!,
                        bytes: 5_027_784_416, minimumMemoryGB: 11),
                Variant(quant: "Q3_K_M", filename: "Doctor-R1.Q3_K_M.gguf",
                        url: URL(string: base + "Doctor-R1.Q3_K_M.gguf")!,
                        bytes: 4_124_161_760, minimumMemoryGB: 7.3),
            ]
        case .medval:
            let base = "https://huggingface.co/stanfordmimi/MedVAL-4B-GGUF/resolve/main/"
            return [
                Variant(quant: "Q4_K_M", filename: "MedVAL-4B.Q4_K_M.gguf",
                        url: URL(string: base + "MedVAL-4B.Q4_K_M.gguf")!,
                        bytes: 2_497_280_928, minimumMemoryGB: 7.3),
                Variant(quant: "Q3_K_M", filename: "MedVAL-4B.Q3_K_M.gguf",
                        url: URL(string: base + "MedVAL-4B.Q3_K_M.gguf")!,
                        bytes: 2_075_618_208, minimumMemoryGB: 5.4),
            ]
        }
    }

    /// Physical memory in GB. An "8 GB" iPhone reports about 7.5, a "6 GB" one
    /// about 5.6, which is why the thresholds above sit where they do.
    static var deviceMemoryGB: Double {
        Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824
    }

    /// The build this device should use, or nil when even the smallest would
    /// not fit - those devices use a hosted model instead.
    func variant(memoryGB: Double = MedicalModel.deviceMemoryGB) -> Variant? {
        variants.first { memoryGB >= $0.minimumMemoryGB }
    }

    static var directory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("Models/Medical", isDirectory: true)
    }

    func localURL(_ variant: Variant) -> URL {
        Self.directory.appendingPathComponent(variant.filename)
    }

    var isDownloaded: Bool {
        guard let variant = variant() else { return false }
        // most of the expected size has to be there: a half-finished or
        // corrupt file must not look ready
        let path = localURL(variant).path
        let size = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int64) ?? 0
        return (size ?? 0) > Int64(Double(variant.bytes) * 0.9)
    }

    /// Clears every build of this model except `keeping`, so switching builds
    /// never leaves two multi-gigabyte files behind.
    func removeOtherVariants(keeping: Variant?) {
        for variant in variants where variant != keeping {
            try? FileManager.default.removeItem(at: localURL(variant))
            try? FileManager.default.removeItem(
                at: Self.directory.appendingPathComponent(variant.filename + ".part"))
        }
    }
}

extension Int64 {
    /// "4.1 GB" - model sizes in the units people see in Settings.
    var gigabytes: String {
        String(format: "%.1f GB", Double(self) / 1_000_000_000)
    }
}
