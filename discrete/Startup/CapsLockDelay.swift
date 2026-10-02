import Foundation

/// Sets the OS's own CapsLock delay to discrete's tap/hold threshold, so a
/// CapsLock press either opens/closes discrete (a tap, shorter than the
/// threshold) or toggles caps lock (a hold, at least the threshold) —
/// never both, never neither. The OS only toggles caps lock once the key
/// has been held for `CapsLockDelayOverride` milliseconds.
enum CapsLockDelay {
    static func apply(threshold: TimeInterval) {
        let milliseconds = Int((threshold * 1000).rounded())
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hidutil")
        process.arguments = ["property", "--set", "{\"CapsLockDelayOverride\":\(milliseconds)}"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { process in
            if process.terminationStatus == 0 {
                print("✅ CapsLock delay set to \(milliseconds) ms")
            } else {
                print("❌ hidutil failed to set CapsLock delay (status \(process.terminationStatus))")
            }
        }

        do {
            try process.run()
        } catch {
            print("❌ Failed to run hidutil: \(error)")
        }
    }
}
