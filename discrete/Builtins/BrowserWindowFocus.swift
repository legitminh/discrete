import AppKit
import ApplicationServices

/// Chrome's scripting window IDs are session IDs, not WindowServer IDs.
/// Geometry usually gives a unique match. Identically placed windows are
/// disambiguated by focusing candidates and verifying the browser's front ID;
/// verified correlations are cached for subsequent invocations.
enum BrowserWindowFocus {
    private static var knownWindows: [pid_t: [String: CGWindowID]] = [:]

    static func focus(_ window: BrowserTabPolicy.Window, app: NSRunningApplication,
                      frontWindow: @escaping (@escaping (String?) -> Void) -> Void,
                      completion: @escaping () -> Void) {
        guard AXIsProcessTrusted(), window.bounds.count == 4,
              let snapshot = ApplicationWindowSnapshot.capture() else { completion(); return }
        let bounds = window.bounds
        let frame = CGRect(x: bounds[0], y: bounds[1], width: bounds[2], height: bounds[3])
        let candidates = snapshot.records.compactMap { record -> CGWindowID? in
            guard (record[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == app.processIdentifier,
                  (record[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  let raw = record[kCGWindowBounds as String] as? [String: Any],
                  let candidate = CGRect(dictionaryRepresentation: raw as CFDictionary),
                  let id = (record[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                  !(ApplicationSpaces.spaces(for: id) ?? []).isEmpty,
                  abs(frame.minX - candidate.minX) < 2, abs(frame.minY - candidate.minY) < 2,
                  abs(frame.width - candidate.width) < 2, abs(frame.height - candidate.height) < 2 else { return nil }
            return id
        }
        if let cached = knownWindows[app.processIdentifier]?[window.id], candidates.contains(cached) {
            ApplicationOpener.focusWindow(id: cached, app: app, completion: completion)
        } else if candidates.count == 1, let id = candidates.first {
            knownWindows[app.processIdentifier, default: [:]][window.id] = id
            ApplicationOpener.focusWindow(id: id, app: app, completion: completion)
        } else {
            resolve(candidates: candidates, window: window, app: app, frontWindow: frontWindow, completion: completion)
        }
    }

    private static func resolve(candidates: [CGWindowID], window: BrowserTabPolicy.Window, app: NSRunningApplication,
                                frontWindow: @escaping (@escaping (String?) -> Void) -> Void,
                                completion: @escaping () -> Void) {
        guard let id = candidates.first else { completion(); return }
        ApplicationOpener.focusWindow(id: id, app: app) {
            frontWindow { scriptingID in
                guard let scriptingID else { completion(); return }
                knownWindows[app.processIdentifier, default: [:]][scriptingID] = id
                if scriptingID == window.id { completion() }
                else {
                    resolve(candidates: Array(candidates.dropFirst()), window: window, app: app,
                            frontWindow: frontWindow, completion: completion)
                }
            }
        }
    }
}
