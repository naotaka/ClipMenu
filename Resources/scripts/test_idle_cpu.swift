import AppKit
import Foundation

/// Launches the direct clipM app with no menu open and fails if it burns a core.
///
/// The type-ahead thread used to call CFRunLoopRunInMode on an empty mode, which
/// returns immediately and pegs one CPU for the life of the process. This measures
/// CPU time after launch has settled, while the app is otherwise idle.

private let cpuLimit = 0.25
private let settleSeconds: TimeInterval = 2
private let sampleSeconds: TimeInterval = 3

struct ScriptError: Error, CustomStringConvertible {
    let description: String
}

/// `ps -o time=` is minutes:seconds.fraction, or hours:minutes:seconds, with an optional day prefix.
private func parsePSTime(_ text: String) -> Double? {
    var body = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !body.isEmpty else { return nil }
    var days = 0.0
    if let dash = body.firstIndex(of: "-") {
        guard let parsedDays = Double(body[..<dash]) else { return nil }
        days = parsedDays
        body = String(body[body.index(after: dash)...])
    }
    let parts = body.split(separator: ":")
    let numbers = parts.compactMap { Double($0) }
    guard numbers.count == parts.count else { return nil }
    switch numbers.count {
    case 1:
        return days * 86_400 + numbers[0]
    case 2:
        return days * 86_400 + numbers[0] * 60 + numbers[1]
    case 3:
        return days * 86_400 + numbers[0] * 3_600 + numbers[1] * 60 + numbers[2]
    default:
        return nil
    }
}

private func psCPUSeconds(pid: Int32) throws -> Double {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/ps")
    process.arguments = ["-p", String(pid), "-o", "time="]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    try process.run()
    process.waitUntilExit()
    let text = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    guard process.terminationStatus == 0, let seconds = parsePSTime(text) else {
        throw ScriptError(description: "ps time failed for pid \(pid): \(text.trimmingCharacters(in: .whitespacesAndNewlines))")
    }
    return seconds
}

/// A broken parser that always returns zero would report an idle app as passing.
private func checkMeterSeesBusyCPU() throws {
    let burner = Process()
    burner.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
    burner.arguments = ["-c", "import time\nend = time.time() + 1.0\nwhile time.time() < end:\n    pass"]
    try burner.run()
    Thread.sleep(forTimeInterval: 0.45)
    let used = try psCPUSeconds(pid: burner.processIdentifier)
    burner.terminate()
    burner.waitUntilExit()
    guard used >= 0.2 else {
        throw ScriptError(description: String(format: "CPU meter saw only %.3fs from a 0.45s busy loop", used))
    }
}

private func quit(_ bundleID: String) throws {
    let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
    for app in running {
        app.forceTerminate()
    }
    let deadline = Date().addingTimeInterval(5)
    while Date() < deadline {
        if NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty { return }
        Thread.sleep(forTimeInterval: 0.05)
    }
    throw ScriptError(description: "Could not quit existing \(bundleID)")
}

func runIdleCPUTest() throws {
    guard CommandLine.arguments.count >= 2 else {
        throw ScriptError(description: "Usage: test_idle_cpu.swift /path/to/clipM.app")
    }
    let appURL = URL(fileURLWithPath: CommandLine.arguments[1])
    guard let bundle = Bundle(url: appURL),
          let executableURL = bundle.executableURL,
          let bundleID = bundle.bundleIdentifier
    else {
        throw ScriptError(description: "Could not resolve bundle for \(appURL.path)")
    }

    try checkMeterSeesBusyCPU()
    print("[IDLE CPU] Terminating existing instances of \(bundleID)...")
    try quit(bundleID)

    var environment = ProcessInfo.processInfo.environment
    environment.removeValue(forKey: "CLIPMENU_UI_TEST_MODE")
    let process = Process()
    process.executableURL = executableURL
    process.environment = environment
    try process.run()
    let pid = process.processIdentifier
    print("[IDLE CPU] Launched \(executableURL.path) pid \(pid)")
    defer {
        if process.isRunning {
            NSRunningApplication(processIdentifier: pid)?.forceTerminate()
        }
    }

    Thread.sleep(forTimeInterval: settleSeconds)
    guard process.isRunning else {
        throw ScriptError(description: "clipM exited during settle (status \(process.terminationStatus))")
    }

    let before = try psCPUSeconds(pid: pid)
    let wallStart = Date()
    Thread.sleep(forTimeInterval: sampleSeconds)
    let after = try psCPUSeconds(pid: pid)
    let wall = Date().timeIntervalSince(wallStart)
    guard process.isRunning else {
        throw ScriptError(description: "clipM exited during the idle sample")
    }

    let cpuSeconds = after - before
    let ratio = cpuSeconds / wall
    print(String(format: "[IDLE CPU] %.1f%% of one core over %.2fs (%.3fs CPU)", ratio * 100, wall, cpuSeconds))
    guard ratio < cpuLimit else {
        throw ScriptError(description: String(format: "idle CPU %.1f%% exceeded %.0f%%", ratio * 100, cpuLimit * 100))
    }
    print("[IDLE CPU] PASS")
}

do {
    try runIdleCPUTest()
} catch {
    fputs("[IDLE CPU] FAIL: \(error)\n", stderr)
    exit(1)
}
