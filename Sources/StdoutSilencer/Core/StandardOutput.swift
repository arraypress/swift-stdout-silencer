//
//  StandardOutput.swift
//  StdoutSilencer
//
//  Created by David Sherlock on 2026.
//
//  Some frameworks print to standard output while they load a model — Core
//  AI's compiler warnings, a Python-ported loader's progress — where a command
//  line tool writes its JSON. While such a call runs, the process's standard
//  output points at /dev/null (Diversion), then comes back.
//

/// The process's standard output, silenced around a call.
///
/// ```swift
/// let model = try await StandardOutput.silenced { try await Model.load(from: folder) }
/// print(json)   // reaches stdout as before
/// ```
///
/// It is the file descriptor that is diverted, so output written below Swift —
/// by C, C++ or a framework's own `printf` — is silenced too; and so is
/// anything else in the process that writes to standard output meanwhile. Write
/// diagnostics to standard error. Uses that overlap share one diversion, which
/// ends when the last of them does, so standard output comes back whatever
/// order they finish in.
public enum StandardOutput {

    /// Runs `body` with standard output pointing at /dev/null.
    ///
    /// - Parameter body: The call whose output to drop.
    /// - Returns: What `body` returns.
    /// - Throws: What `body` throws; standard output comes back either way.
    public static func silenced<T>(_ body: () async throws -> T) async rethrows -> T {
        Diversion.begin()
        defer { Diversion.end() }
        return try await body()
    }

    /// Runs `body` with standard output pointing at /dev/null.
    ///
    /// - Parameter body: The call whose output to drop.
    /// - Returns: What `body` returns.
    /// - Throws: What `body` throws; standard output comes back either way.
    public static func silenced<T>(_ body: () throws -> T) rethrows -> T {
        Diversion.begin()
        defer { Diversion.end() }
        return try body()
    }

    /// Whether standard output is silenced at this moment.
    public static var isSilenced: Bool { Diversion.isActive }
}
