# Swift Stdout Silencer

Silence the process's standard output around one call: a framework that prints while it loads a
model, where a command-line tool writes its JSON.

```swift
import StdoutSilencer

let pipeline = try await StandardOutput.silenced { try await Pipeline(from: bundle) }
print(json)                                   // stdout works again
let n = StandardOutput.silenced { countTokens(text) }   // a synchronous form too
```

## Why

Core AI prints six lines of compiler warnings (`warning: loc(fused[… "ANE I/O op can only do F16
MemRef <-> F32 Tensor cast"`) to standard output every time it loads FLUX.3 at 4 bits. `imagine
--flux3-small --json | jq` got those six lines ahead of the JSON. The Swift port of OmniVoice
that `swift-tts` loads prints "Using cached model at: …" to standard output, where `speak` writes
WAV bytes. Both libraries had their own copy of this; this package is the one copy.

## How

It diverts file descriptor 1 itself, so output from C, C++ or a framework's own `printf` is
dropped as well as Swift's `print`, and it flushes stdout's buffer on the way in and out so
nothing written before the call is lost or written after it is swallowed.

Uses that overlap — two models loading in two tasks — share one diversion: the first saves the
real stdout, the last to finish restores it. Two independent save-and-restore pairs finishing out
of order would restore /dev/null and leave the tool silent for good; four overlapping loads of
1–30 ms, finishing in every order, are tested to leave stdout working.

Anything else the process writes to stdout during the call is dropped too, so write diagnostics
to standard error.

## Measured

- **One silenced call costs about 8 µs** (7.7–8.1 µs over 100,000 calls, release build, M3 Max).
- `imagine --flux3-small --json`: six warning lines on stdout before; none after (the JSON
  parses).
- Tests: six mutations of the rules (no diversion, every use re-saving, the first end
  restoring, the synchronous form not diverting, a throw leaving stdout silenced, `isSilenced`
  wrong) are each caught.

## Requirements

macOS 14 or iOS 17; Swift 6.2. No dependencies.

## Licence

MIT — see LICENSE.
