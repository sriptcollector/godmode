import Foundation
import UIKit

// Live device readings, including this app's real memory footprint from the mach kernel.
enum Telemetry {
    static func footprintMB() -> Int {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return 0 }
        return Int(info.phys_footprint / (1024 * 1024))
    }

    static func freeRAMMB() -> Int {
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return 0 }
        let pageSize = Double(vm_kernel_page_size)
        let free = Double(stats.free_count + stats.inactive_count) * pageSize
        return Int(free / (1024 * 1024))
    }

    static func thermalWord() -> String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return "nominal"
        case .fair: return "fair"
        case .serious: return "serious"
        case .critical: return "critical"
        @unknown default: return "unknown"
        }
    }

    static func snapshot() -> GMActivityAttributes.ContentState {
        let d = UIDevice.current
        d.isBatteryMonitoringEnabled = true
        return .init(
            thermal: thermalWord(),
            battery: d.batteryLevel < 0 ? -1 : Int((d.batteryLevel * 100).rounded()),
            charging: d.batteryState == .charging || d.batteryState == .full,
            ramUsedMB: footprintMB(),
            ramFreeMB: freeRAMMB(),
            updated: Date()
        )
    }
}
