//
//  Diversion.swift
//  StdoutSilencer
//
//  Created by David Sherlock on 2026.
//

import Darwin
import os

/// Points file descriptor 1 at /dev/null and back. The first use under way
/// saves the real one and diverts; the last to end restores it — so two loads
/// that overlap cannot leave standard output pointing at /dev/null, as two
/// independent save-and-restore pairs would when they finish out of order.
enum Diversion {

    /// How many uses are under way, and the real stdout while any is.
    private struct State {
        var depth = 0
        var saved: Int32 = -1
    }

    private static let state = OSAllocatedUnfairLock(initialState: State())

    /// Starts one use; the first diverts.
    static func begin() {
        state.withLock { state in
            if state.depth == 0 {
                fflush(stdout)
                state.saved = dup(STDOUT_FILENO)
                let null = open("/dev/null", O_WRONLY)
                dup2(null, STDOUT_FILENO)
                close(null)
            }
            state.depth += 1
        }
    }

    /// Ends one use; the last brings standard output back.
    static func end() {
        state.withLock { state in
            state.depth -= 1
            guard state.depth == 0 else { return }
            fflush(stdout)
            dup2(state.saved, STDOUT_FILENO)
            close(state.saved)
            state.saved = -1
        }
    }

    /// Whether any use is under way.
    static var isActive: Bool { state.withLock { $0.depth > 0 } }
}
