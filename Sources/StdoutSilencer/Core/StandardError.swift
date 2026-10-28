//
//  StandardError.swift
//  StdoutSilencer
//
//  Created by David Sherlock on 2026.
//
//  The same for standard error: Apple's face grouping (MediaIntelligence)
//  writes CoreData's debug lines there — "CoreData: debug: WAL checkpoint" —
//  on a terminal where a tool reports its progress.
//

/// The process's standard error, silenced around a call.
///
/// ```swift
/// let groups = try await StandardError.silenced {
///     try await StandardOutput.silenced { try await analyzer.update() }
/// }
/// ```
///
/// Everything the process writes to standard error meanwhile is dropped,
/// warnings and diagnostics included, so keep the call narrow; a thrown
/// error still reaches the caller. Uses that overlap share one diversion.
public enum StandardError {

    /// Runs `body` with standard error pointing at /dev/null.
    ///
    /// - Parameter body: The call whose output to drop.
    /// - Returns: What `body` returns.
    /// - Throws: What `body` throws; standard error comes back either way.
    public static func silenced<T>(_ body: () async throws -> T) async rethrows -> T {
        Diversion.error.begin()
        defer { Diversion.error.end() }
        return try await body()
    }

    /// Runs `body` with standard error pointing at /dev/null.
    ///
    /// - Parameter body: The call whose output to drop.
    /// - Returns: What `body` returns.
    /// - Throws: What `body` throws; standard error comes back either way.
    public static func silenced<T>(_ body: () throws -> T) rethrows -> T {
        Diversion.error.begin()
        defer { Diversion.error.end() }
        return try body()
    }

    /// Whether standard error is silenced at this moment.
    public static var isSilenced: Bool { Diversion.error.isActive }
}
