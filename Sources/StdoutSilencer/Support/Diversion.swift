//
//  Diversion.swift
//  StdoutSilencer
//
//  Created by David Sherlock on 2026.
//

import Darwin
import os

/// Points one file descriptor at /dev/null and back. The first use under
/// way saves the real one and diverts; the last to end restores it — so two
/// loads that overlap cannot leave the descriptor pointing at /dev/null, as
/// two independent save-and-restore pairs would when they finish out of order.
final class Diversion: Sendable {

    /// Standard output.
    static let output = Diversion(descriptor: STDOUT_FILENO, flush: { fflush(stdout) })
    /// Standard error.
    static let error = Diversion(descriptor: STDERR_FILENO, flush: { fflush(stderr) })

    /// How many uses are under way, and the real descriptor while any is.
    private struct State {
        var depth = 0
        var saved: Int32 = -1
    }

    private let descriptor: Int32
    /// Empties the C stream's buffer on the descriptor, on the way in and out.
    private let flush: @Sendable () -> Void
    private let state = OSAllocatedUnfairLock(initialState: State())

    private init(descriptor: Int32, flush: @escaping @Sendable () -> Void) {
        self.descriptor = descriptor
        self.flush = flush
    }

    /// Starts one use; the first diverts.
    func begin() {
        state.withLock { state in
            if state.depth == 0 {
                flush()
                state.saved = dup(descriptor)
                let null = open("/dev/null", O_WRONLY)
                dup2(null, descriptor)
                close(null)
            }
            state.depth += 1
        }
    }

    /// Ends one use; the last brings the descriptor back.
    func end() {
        state.withLock { state in
            state.depth -= 1
            guard state.depth == 0 else { return }
            flush()
            dup2(state.saved, descriptor)
            close(state.saved)
            state.saved = -1
        }
    }

    /// Whether any use is under way.
    var isActive: Bool { state.withLock { $0.depth > 0 } }
}
