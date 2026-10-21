#if canImport(Darwin)
import Darwin
import Foundation
import os

/// For the design preview only (`-graphPreview`): now and then the app has
/// frozen in the 3D map's UI tests (the screen stops changing, a query times
/// out, the app cannot be ended; plan.md step 6d), and sampling it from
/// outside held it still, so the tests could not end it. This watches from
/// inside instead. When the main thread has been in one step of its run loop,
/// or the map's render thread has not drawn, for 3 seconds, it writes to the
/// app's log (category "hang") where each of them is: its state and the
/// return addresses up its stack, named; again every 15 seconds while it
/// lasts, with every other thread the first and fourth time. While all is
/// well it writes a line every 30 seconds: frames drawn, the main thread's
/// longest step, the app's memory and paging. The main thread is watched
/// through its run loop, never asked anything, so the UI tests' wait for the
/// app to be idle is untouched. A thread is held only while its registers and
/// frame records are read, and nothing is allocated, logged or locked
/// meanwhile. tools/hang_watch.sh keeps the log.
nonisolated enum GraphHangReporter {
    static let isOn: Bool = GraphPreview.isOn

    /// Starts the watch, once; called on the main thread, which it then
    /// knows as the one to watch.
    static func start() {
        guard isOn, Thread.isMainThread else { return }
        GraphHangWatch.shared.start()
    }

    /// The map's render thread is about to draw a frame.
    static func frame() {
        guard isOn else { return }
        GraphHangWatch.shared.frame()
    }
}

nonisolated final class GraphHangWatch: @unchecked Sendable {
    static let shared = GraphHangWatch()
    private static let quiet: UInt64 = 3_000_000_000
    private static let again: UInt64 = 15_000_000_000
    private static let alive: UInt64 = 30_000_000_000
    private static let depth: Int = 64
    private let log = Logger(subsystem: "com.cramdown.app", category: "hang")
    private let lock = NSLock()
    /// Room for one thread's registers, its return addresses and one frame
    /// record, made once, so nothing is allocated while a thread is held.
    private let registers = UnsafeMutablePointer<natural_t>.allocate(capacity: 96)
    private let returns = UnsafeMutablePointer<UInt>.allocate(capacity: GraphHangWatch.depth)
    private let record = UnsafeMutablePointer<UInt>.allocate(capacity: 2)
    // under the lock
    private var started: Bool = false
    private var mainPort: mach_port_t = 0
    private var renderPort: mach_port_t = 0
    /// When the main run loop began the step it is in; 0 while it sleeps.
    private var mainStepSince: UInt64 = 0
    /// The run-loop activity that began it.
    private var mainStep: CFOptionFlags = 0
    /// Its longest step since the last line saying all is well.
    private var mainLongest: UInt64 = 0
    private var frameAt: UInt64 = 0
    private var frames: Int = 0

    func start() {
        let now: UInt64 = Self.now()
        lock.lock()
        let first: Bool = !started
        started = true
        if first {
            mainPort = pthread_mach_thread_np(pthread_self())
            mainStepSince = now // called from inside a step
        }
        lock.unlock()
        guard first else { return }
        let observer: CFRunLoopObserver? = CFRunLoopObserverCreateWithHandler(
            kCFAllocatorDefault, CFRunLoopActivity.allActivities.rawValue, true, CFIndex.max
        ) { [self] _, activity in step(Self.mask(activity)) }
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
        let info = ProcessInfo.processInfo
        say("hang watch on: pid \(getpid()), \(info.activeProcessorCount) cores, \(info.physicalMemory / 1_048_576) MB; \(Self.memory()); \(info.arguments.dropFirst().joined(separator: " "))")
        let thread = Thread { [self] in watch() }
        thread.name = "graph hang watch"
        thread.qualityOfService = .userInteractive
        thread.start()
    }

    func frame() {
        let port: mach_port_t = pthread_mach_thread_np(pthread_self())
        lock.lock()
        renderPort = port
        frameAt = Self.now()
        frames += 1
        lock.unlock()
    }

    /// Each activity of the main run loop ends one step and begins the next;
    /// going to sleep ends the last.
    private func step(_ activity: CFOptionFlags) {
        lock.lock()
        let now: UInt64 = Self.now()
        let took: UInt64 = Self.since(mainStepSince, now)
        if took > mainLongest { mainLongest = took }
        mainStepSince = activity == CFRunLoopActivity.beforeWaiting.rawValue ? 0 : now
        mainStep = activity
        lock.unlock()
    }

    private func watch() {
        let me: mach_port_t = pthread_mach_thread_np(pthread_self())
        let began: UInt64 = Self.now()
        var stalls: Int = 0, reports: Int = 0, stuck: Bool = false
        var reportedAt: UInt64 = 0, aliveAt: UInt64 = began
        while true {
            usleep(500_000)
            lock.lock()
            let now: UInt64 = Self.now()
            let mainStuck: UInt64 = Self.since(mainStepSince, now)
            let since: String = Self.activity(mainStep)
            let renderQuiet: UInt64 = frames == 0 ? 0 : Self.since(frameAt, now)
            let drawn: Int = frames
            let longest: UInt64 = mainLongest
            lock.unlock()
            if mainStuck >= Self.quiet || renderQuiet >= Self.quiet {
                if !stuck { stuck = true; stalls += 1; reports = 0 }
                if reports < 12 && (reports == 0 || now &- reportedAt >= Self.again) {
                    reports += 1
                    reportedAt = now
                    report("hang \(stalls).\(reports)",
                           what: "main stuck \(Self.seconds(mainStuck)) s (since \(since)), render quiet \(Self.seconds(renderQuiet)) s, frames \(drawn)",
                           up: now &- began, everyThread: reports == 1 || reports == 4, me: me)
                }
            } else if stuck {
                stuck = false
                say("hang \(stalls) over: main's longest step \(longest / 1_000_000) ms, frames \(drawn)")
            }
            if now &- aliveAt >= Self.alive {
                aliveAt = now
                lock.lock(); mainLongest = 0; lock.unlock()
                say("alive at \(Self.seconds(now &- began)) s: frames \(drawn), main's longest step \(longest / 1_000_000) ms, main stuck \(Self.seconds(mainStuck)) s, render quiet \(Self.seconds(renderQuiet)) s; \(Self.memory())")
            }
        }
    }

    private func report(_ name: String, what: String, up: UInt64, everyThread: Bool, me: mach_port_t) {
        lock.lock()
        let main: mach_port_t = mainPort
        let render: mach_port_t = renderPort
        lock.unlock()
        say("\(name) at \(Self.seconds(up)) s: \(what); \(Self.memory())")
        dump("\(name) main", port: main, me: me)
        if render != 0 && render != main { dump("\(name) render", port: render, me: me) }
        if everyThread { dumpOthers(name, skipping: [main, render, me], me: me) }
    }

    /// One thread: its name and state, then its stack, innermost first.
    private func dump(_ name: String, port: mach_port_t, me: mach_port_t) {
        guard port != 0, port != me else { return }
        let state: String = Self.state(of: port)
        let n: Int = addresses(of: port)
        say("\(name): \(state), \(n) frames")
        var line: String = name
        for i in 0..<n {
            let frame: String = " | \(i) \(Self.symbol(returns[i], returnAddress: i > 0))"
            if line.count + frame.count > 700 {
                say(line)
                line = name
            }
            line += frame
        }
        if n > 0 { say(line) }
    }

    private func dumpOthers(_ name: String, skipping: [mach_port_t], me: mach_port_t) {
        var list: thread_act_array_t?
        var count: mach_msg_type_number_t = 0
        guard task_threads(mach_task_self_, &list, &count) == KERN_SUCCESS, let list else { return }
        let ports: [mach_port_t] = (0..<Int(count)).map { list[$0] }
        say("\(name): \(ports.count) threads")
        for (i, port) in ports.enumerated() where !skipping.contains(port) {
            dump("\(name) t\(i)", port: port, me: me)
        }
        for port in ports { mach_port_deallocate(mach_task_self_, port) }
        vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: list)),
                      vm_size_t(ports.count * MemoryLayout<thread_act_t>.stride))
    }

    /// A thread's name (asked while it runs), its run state, how often it is
    /// held, and its CPU time.
    private static func state(of port: mach_port_t) -> String {
        var label: String = "port \(port)"
        let thread: pthread_t? = pthread_from_mach_thread_np(port)
        if let thread {
            let capacity: Int = 64
            var buffer = [CChar](repeating: 0, count: capacity)
            if pthread_getname_np(thread, &buffer, capacity) == 0, buffer[0] != 0 {
                let bytes: [UInt8] = buffer.prefix(while: { $0 != 0 }).map { UInt8(bitPattern: $0) }
                label = "\"\(String(decoding: bytes, as: UTF8.self))\" " + label
            }
        } else {
            label += " (no pthread)"
        }
        var info = thread_basic_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<thread_basic_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                thread_info(port, thread_flavor_t(THREAD_BASIC_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return "\(label), no state (\(result))" }
        let states: [Int32: String] = [1: "running", 2: "stopped", 3: "waiting", 4: "uninterruptible", 5: "halted"]
        let run: String = states[info.run_state] ?? "state \(info.run_state)"
        let cpu: Double = Double(info.user_time.seconds + info.system_time.seconds)
            + Double(info.user_time.microseconds + info.system_time.microseconds) / 1_000_000
        return "\(label) \(run), held \(info.suspend_count), cpu \(String(format: "%.2f", cpu)) s, now \(info.cpu_usage / 10)%, asleep \(info.sleep_time) s"
    }

    /// A code address as "image symbol + offset" (a return address is looked
    /// up one byte back, inside the call that made it).
    private static func symbol(_ address: UInt, returnAddress: Bool) -> String {
        let hex: String = "0x" + String(address, radix: 16)
        guard address > 0x1000,
              let pointer = UnsafeRawPointer(bitPattern: returnAddress ? address &- 1 : address) else { return hex }
        var info = Dl_info()
        guard dladdr(pointer, &info) != 0 else { return hex }
        let file: UnsafePointer<CChar>? = info.dli_fname
        var image: String = file.map { String(cString: $0) } ?? "?"
        if let slash = image.lastIndex(of: "/") { image = String(image[image.index(after: slash)...]) }
        let name: UnsafePointer<CChar>? = info.dli_sname
        let start: UnsafeMutableRawPointer? = info.dli_saddr
        if let name, let start {
            let symbol: String = String(cString: name)
            if symbol != "<redacted>" { return "\(image) \(symbol) + \(address &- UInt(bitPattern: start))" }
        }
        let base: UnsafeMutableRawPointer? = info.dli_fbase
        return "\(image) +0x\(String(address &- UInt(bitPattern: base), radix: 16))"
    }

    /// pc, lr, then the return address in each frame record up the stack,
    /// into `returns`. Between holding the thread and letting it go there are
    /// only kernel calls: the frame records are copied by the kernel, so a
    /// stack that is going away cannot fault, and nothing allocates, logs or
    /// takes a lock the held thread might have.
    private func addresses(of port: mach_port_t) -> Int {
        #if arch(arm64)
        let depth: Int = GraphHangWatch.depth
        let registers: UnsafeMutablePointer<natural_t> = self.registers
        let returns: UnsafeMutablePointer<UInt> = self.returns
        let record: UnsafeMutablePointer<UInt> = self.record
        let into = vm_address_t(UInt(bitPattern: record))
        let mask: UInt = 0x0000_7FFF_FFFF_FFFF
        let flavor = thread_state_flavor_t(ARM_THREAD_STATE64)
        var count = mach_msg_type_number_t(68)
        var copied: vm_size_t = 0
        var n: Int = 0
        guard thread_suspend(port) == KERN_SUCCESS else { return 0 }
        if thread_get_state(port, flavor, registers, &count) == KERN_SUCCESS && count >= 68 {
            // x0...x28, then fp, lr, sp, pc
            let saved = UnsafeRawPointer(registers)
            var fp: UInt = saved.loadUnaligned(fromByteOffset: 232, as: UInt.self) & mask
            returns[0] = saved.loadUnaligned(fromByteOffset: 256, as: UInt.self) & mask
            returns[1] = saved.loadUnaligned(fromByteOffset: 240, as: UInt.self) & mask
            n = 2
            while n < depth && fp > 0x1000 && fp & 7 == 0 {
                guard vm_read_overwrite(mach_task_self_, vm_address_t(fp), 16, into, &copied) == KERN_SUCCESS,
                      copied == 16 else { break }
                let next: UInt = record[0] & mask
                let back: UInt = record[1] & mask
                if back == 0 { break }
                returns[n] = back
                n += 1
                // records run up the stack, never far apart
                if next <= fp || next &- fp > 0x100_0000 { break }
                fp = next
            }
        }
        thread_resume(port)
        return n
        #else
        return 0
        #endif
    }

    /// The app's memory and paging, and its CPU time.
    private static func memory() -> String {
        var vm = task_vm_info_data_t()
        var vmCount = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let vmResult: kern_return_t = withUnsafeMutablePointer(to: &vm) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(vmCount)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &vmCount)
            }
        }
        var events = task_events_info_data_t()
        var eventsCount = mach_msg_type_number_t(MemoryLayout<task_events_info_data_t>.size / MemoryLayout<natural_t>.size)
        let eventsResult: kern_return_t = withUnsafeMutablePointer(to: &events) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(eventsCount)) {
                task_info(mach_task_self_, task_flavor_t(TASK_EVENTS_INFO), $0, &eventsCount)
            }
        }
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        let cpu: Double = Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec)
            + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000
        var parts: [String] = []
        if vmResult == KERN_SUCCESS {
            parts.append("footprint \(vm.phys_footprint / 1_048_576) MB, resident \(vm.resident_size / 1_048_576) MB, compressed \(vm.compressed / 1_048_576) MB")
        }
        if eventsResult == KERN_SUCCESS { parts.append("page-ins \(events.pageins), faults \(events.faults)") }
        parts.append("cpu \(String(format: "%.1f", cpu)) s")
        return parts.joined(separator: ", ")
    }

    /// The activity's bits, whichever type the SDK hands the observer's
    /// block (the iOS 26 one gives plain CFOptionFlags).
    private static func mask(_ activity: CFOptionFlags) -> CFOptionFlags { activity }
    private static func mask(_ activity: CFRunLoopActivity) -> CFOptionFlags { activity.rawValue }

    /// The run-loop activity a step began with.
    private static func activity(_ raw: CFOptionFlags) -> String {
        switch raw {
        case CFRunLoopActivity.entry.rawValue: return "entry"
        case CFRunLoopActivity.beforeTimers.rawValue: return "before timers"
        case CFRunLoopActivity.beforeSources.rawValue: return "before sources"
        case CFRunLoopActivity.beforeWaiting.rawValue: return "asleep"
        case CFRunLoopActivity.afterWaiting.rawValue: return "woken"
        case CFRunLoopActivity.exit.rawValue: return "exit"
        default: return "start"
        }
    }

    private func say(_ text: String) { log.error("\(text, privacy: .public)") }
    private static func now() -> UInt64 { DispatchTime.now().uptimeNanoseconds }
    private static func since(_ then: UInt64, _ now: UInt64) -> UInt64 { then == 0 || then > now ? 0 : now - then }
    private static func seconds(_ nanoseconds: UInt64) -> String { String(format: "%.1f", Double(nanoseconds) / 1e9) }
}
#endif
