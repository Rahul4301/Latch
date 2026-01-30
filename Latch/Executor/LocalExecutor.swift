import Foundation

/// Runs a single executable with no shell. Enforces absolute path, working directory, minimal env,
/// timeout, and stdout/stderr caps (AGENTS.md, SRS FR-14–FR-19).
final class LocalExecutor {

    func run(
        executablePath: String,
        args: [String],
        workingDirectory: URL,
        timeoutSeconds: Double,
        maxStdoutBytes: Int,
        maxStderrBytes: Int
    ) async -> (exitCode: Int32, stdout: String, stderr: String, stdoutTruncated: Bool, stderrTruncated: Bool, didTimeout: Bool) {
        if !executablePath.hasPrefix("/") {
            return (-1, "", "executablePath must be absolute", false, false, false)
        }

        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = args
        process.currentDirectoryURL = workingDirectory
        process.environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin"]
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let didTimeoutBox = Box(false)
        let processTask: Task<(exitCode: Int32, stdoutData: Data, stderrData: Data, launchError: Error?), Never> = Task {
            do {
                try process.run()
                process.waitUntilExit()
                let stdoutData: Data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let stderrData: Data = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                return (process.terminationStatus, stdoutData, stderrData, nil)
            } catch {
                return (-1, Data(), Data(), error)
            }
        }
        let timeoutTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
            didTimeoutBox.value = true
            process.terminate()
        }

        let result = await processTask.value
        _ = timeoutTask

        if let launchError = result.launchError {
            return (-1, "", launchError.localizedDescription, false, false, false)
        }

        let stdoutTruncated = result.stdoutData.count > maxStdoutBytes
        let stderrTruncated = result.stderrData.count > maxStderrBytes
        let stdoutDataCapped = result.stdoutData.prefix(maxStdoutBytes)
        let stderrDataCapped = result.stderrData.prefix(maxStderrBytes)
        let stdoutStr = String(data: Data(stdoutDataCapped), encoding: .utf8) ?? ""
        let stderrStr = String(data: Data(stderrDataCapped), encoding: .utf8) ?? ""

        return (
            result.exitCode,
            stdoutStr,
            stderrStr,
            stdoutTruncated,
            stderrTruncated,
            didTimeoutBox.value
        )
    }
}

private final class Box<T> {
    var value: T
    init(_ value: T) { self.value = value }
}
