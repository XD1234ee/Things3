import Foundation

/// Runs a command-line tool off the main thread, with a timeout.
struct ScriptRunner: Sendable {
    struct Result: Sendable {
        let exitCode: Int32
        let stdout: Data
        let stderr: String
        let timedOut: Bool
    }

    let executable: URL

    func run(arguments: [String], timeout: TimeInterval) async throws -> Result {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    continuation.resume(returning: try runBlocking(arguments: arguments, timeout: timeout))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func runBlocking(arguments: [String], timeout: TimeInterval) throws -> Result {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()

        let timedOut = TimeoutFlag()
        let killer = DispatchWorkItem {
            if process.isRunning {
                timedOut.set()
                process.terminate()
            }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)

        // Drain both pipes concurrently so a large output can't fill a pipe buffer and deadlock.
        let stderrBox = DataBox()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
            stderrBox.data = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        let stdout = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        group.wait()
        process.waitUntilExit()
        killer.cancel()

        return Result(
            exitCode: process.terminationStatus,
            stdout: stdout,
            stderr: String(decoding: stderrBox.data, as: UTF8.self),
            timedOut: timedOut.value
        )
    }
}

private final class DataBox: @unchecked Sendable {
    var data = Data()
}

private final class TimeoutFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false
    func set() { lock.lock(); flag = true; lock.unlock() }
    var value: Bool { lock.lock(); defer { lock.unlock() }; return flag }
}
