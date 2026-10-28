//
//  StdoutSilencerTests.swift
//  StdoutSilencerTests
//
//  Created by David Sherlock on 2026.
//
//  Each test points stdout at a file of its own, runs, and reads back what
//  arrived. Serialized: stdout belongs to the whole process.
//

import Darwin
import Foundation
import Testing
@testable import StdoutSilencer

@Suite("Standard output", .serialized)
struct StdoutSilencerTests {

    /// What reaches stdout (or `descriptor`) while `body` runs, caught in a file.
    private func caught(_ descriptor: Int32 = STDOUT_FILENO,
                        _ body: () async throws -> Void) async throws -> String {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("stdout-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: file) }
        fflush(stdout)
        fflush(stderr)
        let real = dup(descriptor)
        let sink = open(file.path, O_WRONLY | O_CREAT | O_TRUNC, 0o600)
        dup2(sink, descriptor)
        close(sink)
        defer {
            fflush(stdout)
            fflush(stderr)
            dup2(real, descriptor)
            close(real)
        }
        try await body()
        fflush(stdout)
        fflush(stderr)
        return try String(contentsOf: file, encoding: .utf8)
    }

    /// Writes straight to file descriptor 1, below Swift's and C's buffers,
    /// as a framework's own logging can.
    private func writeRaw(_ text: String) {
        _ = text.withCString { write(STDOUT_FILENO, $0, strlen($0)) }
    }

    @Test("A load's warnings go nowhere; the JSON after them arrives")
    func asyncSilenced() async throws {
        let out = try await caught {
            let value = await StandardOutput.silenced { () async -> Int in
                print("warning: loc(fused…")
                writeRaw("ANE I/O op can only do F16\n")
                return 7
            }
            #expect(value == 7)
            print("[{\"seed\":21}]")
        }
        #expect(!out.contains("warning: loc"))
        #expect(!out.contains("ANE I/O"))
        #expect(out.contains("[{\"seed\":21}]"))
    }

    @Test("The synchronous form silences too")
    func syncSilenced() async throws {
        let out = try await caught {
            let value = StandardOutput.silenced { () -> String in
                print("progress 50%")
                return "model"
            }
            #expect(value == "model")
            print("done")
        }
        #expect(!out.contains("progress"))
        #expect(out.contains("done"))
    }

    @Test("A throwing call still brings stdout back")
    func throwing() async throws {
        struct Failed: Error {}
        let out = try await caught {
            #expect(throws: Failed.self) {
                try StandardOutput.silenced { () throws -> Void in
                    print("half a warning")
                    throw Failed()
                }
            }
            #expect(!StandardOutput.isSilenced)
            print("the error JSON")
        }
        #expect(!out.contains("half a warning"))
        #expect(out.contains("the error JSON"))
    }

    @Test("Overlapping uses: stdout comes back only when the last one ends")
    func overlapping() async throws {
        let out = try await caught {
            Diversion.output.begin()
            Diversion.output.begin()
            #expect(StandardOutput.isSilenced)
            Diversion.output.end()
            print("still loading")
            #expect(StandardOutput.isSilenced)
            Diversion.output.end()
            #expect(!StandardOutput.isSilenced)
            print("the JSON")
        }
        #expect(!out.contains("still loading"))
        #expect(out.contains("the JSON"))
    }

    @Test("Two loads at once, finishing in either order, leave stdout working")
    func concurrent() async throws {
        let out = try await caught {
            await withTaskGroup(of: Void.self) { group in
                for delay in [30, 5, 15, 1] {
                    group.addTask {
                        await StandardOutput.silenced {
                            print("load \(delay)")
                            try? await Task.sleep(for: .milliseconds(delay))
                        }
                    }
                }
            }
            #expect(!StandardOutput.isSilenced)
            print("after all four")
        }
        #expect(!out.contains("load "))
        #expect(out.contains("after all four"))
    }

    @Test("Standard error is silenced on its own, and comes back")
    func standardError() async throws {
        let errors = try await caught(STDERR_FILENO) {
            let printed = try await caught {
                StandardError.silenced {
                    #expect(StandardError.isSilenced)
                    #expect(!StandardOutput.isSilenced, "stdout is not touched")
                    fputs("CoreData: debug: WAL checkpoint\n", stderr)
                    _ = "progress\n".withCString { write(STDERR_FILENO, $0, strlen($0)) }
                    print("the JSON")
                }
            }
            #expect(printed.contains("the JSON"))
            #expect(!StandardError.isSilenced)
            fputs("scene.mov (1/1)…\n", stderr)
        }
        #expect(!errors.contains("CoreData"))
        #expect(!errors.contains("progress"))
        #expect(errors.contains("scene.mov (1/1)"))
    }
}
