import Foundation
import QuartzCore
#if canImport(Darwin)
import Darwin
#endif

/// A diagnostic for the Launch recording only (`-uiPreviewSplash`): what
/// holds the main thread up while home moves in at the hand-off.
///
/// A display link notes each refresh that reaches the main thread, with the
/// opening's time (LaunchStage.now) then. A sampler thread watches it: when
/// no refresh has come for over 30 ms while home is moving, it reads the
/// main thread's stack every 2 ms until one comes. Both are written to the
/// app's Caches (launch-frames.txt and launch-hang.txt), which the workflow
/// reads back after each take and names with atos.
final class LaunchHangProbe: NSObject {
    static let shared = LaunchHangProbe()

    private var link: CADisplayLink?
    private let sampler = HangSampler()
    private var lines: [String] = []
    private var last: CFTimeInterval = 0

    /// From the app's start, on the main thread.
    static func startIfRecording() {
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("-uiPreviewSplash"), !args.contains("-uiPreviewSplashHold") else { return }
        shared.start()
    }

    private func start() {
        guard link == nil else { return }
        sampler.start()
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        self.link = link
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in self?.finish() }
    }

    @objc private func tick(_ link: CADisplayLink) {
        let opening = MainActor.assumeIsolated { LaunchStage.shared.now }
        sampler.note(host: link.timestamp, opening: opening)
        let gap = last > 0 ? link.timestamp - last : 0
        last = link.timestamp
        let when = opening.isFinite ? String(format: "%.3f", opening) : "rest"
        lines.append(String(format: "%.4f %.1f ", link.timestamp - sampler.origin, gap * 1000) + when)
    }

    private func finish() {
        link?.invalidate()
        link = nil
        guard let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return }
        let text = "host-origin-s opening-gap-ms opening-time\n" + lines.joined(separator: "\n") + "\n"
        try? text.write(to: dir.appendingPathComponent("launch-frames.txt"), atomically: true, encoding: .utf8)
    }
}

/// The probe's sampling half, on its own thread. Nothing is allocated while
/// the main thread is suspended (it may hold the allocator's lock): the
/// registers and the stack go into buffers made beforehand.
final class HangSampler: @unchecked Sendable {
    let origin = CACurrentMediaTime()
    /// [the last refresh's host time, the opening's time then]: written by
    /// the main thread each refresh, read here.
    private let beat = UnsafeMutablePointer<Double>.allocate(capacity: 2)
    private let regs = UnsafeMutablePointer<UInt32>.allocate(capacity: 68)
    private let stack = UnsafeMutablePointer<UInt64>.allocate(capacity: 64)
    private var mainThread: mach_port_t = 0

    private struct Stall {
        var start: Double
        var opening: Double
        var samples: [(time: Double, pcs: [UInt64])] = []
    }
    private var stalls: [Stall] = []

    init() {
        beat[0] = 0
        beat[1] = 0
    }

    /// On the main thread: the thread to sample is this one.
    func start() {
        mainThread = mach_thread_self()
        let thread = Thread { [self] in self.run() }
        thread.qualityOfService = .userInteractive
        thread.start()
    }

    /// On the main thread, each refresh.
    func note(host: Double, opening: Double) {
        beat[0] = host
        beat[1] = opening
    }

    private func run() {
        var current: Stall?
        while CACurrentMediaTime() - origin < 12 {
            usleep(2000)
            let now = CACurrentMediaTime()
            let last = beat[0], opening = beat[1]
            if last > 0, now - last > 0.03, opening > 0, opening.isFinite {
                let pcs = sample()
                if current == nil || current?.start != last {
                    if let c = current { stalls.append(c) }
                    current = Stall(start: last, opening: opening)
                }
                if (current?.samples.count ?? 0) < 300 { current?.samples.append((time: now, pcs: pcs)) }
            } else if let c = current {
                stalls.append(c)
                current = nil
            }
        }
        if let c = current { stalls.append(c) }
        write()
    }

    /// The main thread's return addresses, innermost first: its pc and lr,
    /// then the frame-pointer chain.
    private func sample() -> [UInt64] {
        #if arch(arm64)
        guard thread_suspend(mainThread) == KERN_SUCCESS else { return [] }
        var count = mach_msg_type_number_t(68)
        let kr = thread_get_state(mainThread, thread_state_flavor_t(6), regs, &count)  // ARM_THREAD_STATE64
        var n = 0
        if kr == KERN_SUCCESS {
            // arm_thread_state64_t: x0-x28, fp, lr, sp, pc (64-bit words)
            let fpWord = UInt64(regs[58]) | (UInt64(regs[59]) << 32)
            stack[0] = UInt64(regs[64]) | (UInt64(regs[65]) << 32)
            stack[1] = UInt64(regs[60]) | (UInt64(regs[61]) << 32)
            n = 2
            var fp = fpWord
            while n < 64, fp != 0, fp & 7 == 0 {
                var pair: (UInt64, UInt64) = (0, 0)
                var got: vm_size_t = 0
                let r = withUnsafeMutablePointer(to: &pair) { p in
                    vm_read_overwrite(mach_task_self_, vm_address_t(fp), vm_size_t(16),
                                      vm_address_t(UInt(bitPattern: p)), &got)
                }
                if r != KERN_SUCCESS || got != 16 || pair.1 == 0 { break }
                stack[n] = pair.1
                n += 1
                if pair.0 <= fp { break }
                fp = pair.0
            }
        }
        thread_resume(mainThread)
        return Array(UnsafeBufferPointer(start: stack, count: n))
        #else
        return []
        #endif
    }

    private func write() {
        guard let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return }
        var named: [UInt64: String] = [:]
        func describe(_ pc: UInt64) -> String {
            if let s = named[pc] { return s }
            var text = String(format: "0x%llx 0x0 ? ?", pc)
            var info = Dl_info()
            if dladdr(UnsafeRawPointer(bitPattern: UInt(pc)), &info) != 0 {
                let path = info.dli_fname.map { String(cString: $0) } ?? "?"
                let base = UInt64(UInt(bitPattern: info.dli_fbase))
                let name = info.dli_sname.map { String(cString: $0) } ?? "?"
                text = String(format: "0x%llx 0x%llx ", pc, base) + path + " " + name
            }
            named[pc] = text
            return text
        }
        var out = String(format: "origin %.4f\n", origin)
        for s in stalls {
            let end = s.samples.last?.time ?? s.start
            out += String(format: "stall after %.4f, at least %.0f ms, opening %.3f, %ld samples\n",
                          s.start - origin, (end - s.start) * 1000, s.opening, s.samples.count)
            for sample in s.samples {
                out += String(format: "sample %.4f\n", sample.time - origin)
                for pc in sample.pcs { out += "  " + describe(pc) + "\n" }
            }
        }
        try? out.write(to: dir.appendingPathComponent("launch-hang.txt"), atomically: true, encoding: .utf8)
    }
}
