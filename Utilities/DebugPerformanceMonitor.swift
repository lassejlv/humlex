//
//  DebugPerformanceMonitor.swift
//  AI Chat
//
//  Created by Codex on 12/02/2026.
//

import Foundation
import Darwin

@MainActor
final class DebugPerformanceMonitor: ObservableObject {
    @Published private(set) var fps: Int = 0
    @Published private(set) var cpuPercent: Double = 0
    @Published private(set) var memoryMB: Double = 0

    private var frameTimer: DispatchSourceTimer?
    private var sampleTimer: DispatchSourceTimer?
    private var frameCount = 0
    private var lastSampleTime = CFAbsoluteTimeGetCurrent()

    func start() {
        guard frameTimer == nil, sampleTimer == nil else { return }

        frameCount = 0
        lastSampleTime = CFAbsoluteTimeGetCurrent()

        let frameTimer = DispatchSource.makeTimerSource(queue: DispatchQueue.main)
        frameTimer.schedule(deadline: .now(), repeating: .milliseconds(16), leeway: .milliseconds(4))
        frameTimer.setEventHandler { [weak self] in
            guard let self else { return }
            self.frameCount += 1
        }
        frameTimer.resume()
        self.frameTimer = frameTimer

        let sampleTimer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        sampleTimer.schedule(deadline: .now() + 1, repeating: 1, leeway: .milliseconds(120))
        sampleTimer.setEventHandler { [weak self] in
            guard let self else { return }

            let now = CFAbsoluteTimeGetCurrent()
            let elapsed = max(0.001, now - self.lastSampleTime)
            let sampledFPS = Int((Double(self.frameCount) / elapsed).rounded())
            self.frameCount = 0
            self.lastSampleTime = now

            let sampledCPU = Self.sampleCPUPercent()
            let sampledMemory = Self.sampleMemoryMB()

            Task { @MainActor in
                self.fps = sampledFPS
                self.cpuPercent = sampledCPU
                self.memoryMB = sampledMemory
            }
        }
        sampleTimer.resume()
        self.sampleTimer = sampleTimer
    }

    func stop() {
        frameTimer?.cancel()
        sampleTimer?.cancel()
        frameTimer = nil
        sampleTimer = nil
        frameCount = 0
    }

    private static func sampleMemoryMB() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4

        let result = withUnsafeMutablePointer(to: &info) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), intPtr, &count)
            }
        }

        guard result == KERN_SUCCESS else { return 0 }
        return Double(info.resident_size) / (1024 * 1024)
    }

    private static func sampleCPUPercent() -> Double {
        var threads: thread_act_array_t?
        var threadCount: mach_msg_type_number_t = 0

        let result = task_threads(mach_task_self_, &threads, &threadCount)
        guard result == KERN_SUCCESS, let threads else { return 0 }

        defer {
            let size = vm_size_t(threadCount) * vm_size_t(MemoryLayout<thread_t>.stride)
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: threads), size)
        }

        var totalCPU: Double = 0
        for index in 0..<Int(threadCount) {
            var threadInfo = thread_basic_info()
            var threadInfoCount = mach_msg_type_number_t(THREAD_INFO_MAX)

            let threadResult = withUnsafeMutablePointer(to: &threadInfo) { ptr in
                ptr.withMemoryRebound(to: integer_t.self, capacity: Int(threadInfoCount)) {
                    intPtr in
                    thread_info(
                        threads[index],
                        thread_flavor_t(THREAD_BASIC_INFO),
                        intPtr,
                        &threadInfoCount
                    )
                }
            }

            guard threadResult == KERN_SUCCESS else { continue }
            if (threadInfo.flags & TH_FLAGS_IDLE) == 0 {
                totalCPU += (Double(threadInfo.cpu_usage) / Double(TH_USAGE_SCALE)) * 100.0
            }
        }

        return totalCPU
    }
}
