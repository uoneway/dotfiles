# Right Shift English

Hold right Shift for temporary uppercase English; release it to restore the
baseline input source. F18 toggles the baseline between ABC and Korean. The app
runs independently of Karabiner; Karabiner may map Caps Lock to F18.

## 1.0.4: shorter waits, safe completion handling, and diagnostic context

Each transition now has a 300 ms deadline, rather than two seconds. When a new
Shift/language action arrives after the active transition has already waited
100 ms, its remaining wait is capped at 25 ms. Earlier queued text retains its
order; normal rapid Shift sequences are not interrupted. A stalled attempt ends
before the newer command is processed, and completed requests cannot run stale
completion handlers or source-selection polling callbacks.

Failed attempts still stop automatic recovery. Superseded attempts are recorded
separately from failures. A native shortcut already posted to macOS cannot be
withdrawn; a source change while recovery is paused is logged without retrying.
This bounds app-controlled waiting but does not guarantee a target app's IME
composition or eliminate OS-side late activation.

Abnormal-transition logs contain UTC time, request ID, command, result/reason,
stage timings, elapsed time, deadline, initial/target/current sources, source
changes, the configured switching shortcut, baseline/Shift state, queued event
and command counts and buffer age, initial/current app bundle IDs, source-selection
OS status codes, permission checks, app/OS versions, and up to eight recent
transition summaries. Duplicate late completions are ignored and logged once.
Successful transitions remain in the bounded in-memory history and are included
only when a later abnormal transition needs context. Input text, ordinary key
codes, Unicode payloads, window titles, and document contents are not logged.
The launch agent writes diagnostics to
`~/.local/share/karabiner-shift-english/daemon-error.log`.

## 1.0.3: stop automatic recovery after a failure

A failed transition logs its diagnostic details and disables automatic source
repairs for the rest of that attempt. Idle timers, ordinary typing, status queries,
and shutdown do not retry the failed transition. Queued text passes through using
the current input source. The original baseline remains journaled until a
successful restore.

The next explicit right-Shift press/release, F18 toggle, or source selection starts
a new attempt. A successful transition enables normal drift checks again.
`status` and `barrier` only observe state. Replies expose `automatic_recovery`,
`consecutive_failures`, and `last_error`; timed retry intervals are removed.
The initial attempt still has its existing two-second timeout. Starting a new
process may make one startup restore attempt from the saved journal.

## 1.0.2: bounded recovery after failed transitions

A failed source transition previously triggered repeated background repairs with
no cooldown. A queued key could also retry the same failed repair indefinitely.
Failures now delay automatic repairs by 1, 2, 4, 8, 16, then at most 30 seconds.
A successful source activation resets the delay. Explicit Shift/F18 commands
still attempt the requested transition immediately.

During cooldown, keyboard events pass through using the current input source;
the pending restore remains available for later recovery. The first transition
attempt still buffers input until it succeeds or reaches its two-second timeout.
This avoids indefinitely holding keys when native switching is unavailable.

Each failure logs its UTC time, command, stage, target/current source, and retry
interval. Socket replies expose `last_error`, `consecutive_failures`, and
`retry_in_seconds`; the `barrier` command observes state without selecting sources.
Historical counters do not identify the cause of earlier failures.

## 1.0.1: activate Korean in the focused app

`TISSelectInputSource` can update the menu-bar source ID without activating the
Korean input context in the focused app. In Slack this produced English letters
while the source ID was Korean; switching apps restored Korean input.

Version 1.0.1 selects Korean, selects ABC, then uses macOS's **Select the previous
input source** shortcut to finish the Korean activation. It reads that shortcut
from `com.apple.symbolichotkeys` (ID 60), including custom key and modifier
settings. Without an override, it uses the macOS default Control-Space. A disabled
or malformed shortcut fails the transition; it does not report a successful
menu-only selection. The shortcut events bypass the app's F18 interception.

Subsequent input remains buffered until the native switch completes. The native
switch wait never falls back to a programmatic selection. The restore journal
remains pending if the transition fails.

References: [Karabiner issue #1602](https://github.com/pqrs-org/Karabiner-Elements/issues/1602)
and [macism's explanation](https://github.com/laishulu/macism).

## Verification

Build and run the keyboard pipeline regression checks when the regular daemon
is stopped and the keyboard is not in use:

```sh
swiftc -O packages/right-shift-english/1.0.4/ShiftEnglish.swift -o /tmp/right-shift-english-test
/tmp/right-shift-english-test --self-test-interruption
/tmp/right-shift-english-test --self-test-recovery
/tmp/right-shift-english-test --self-test-keyboard
```

The interruption regression injects stalled transitions and checks newer language
actions, bounded waits, obsolete completions, and diagnostic metadata.
The recovery regression injects failures without changing the system input source
and checks that failed restores retain their journal, automatic retries stop,
ordinary typing and status queries do not retry, and explicit retries can recover.
The keyboard pipeline checks exercise queued events, both Shifts, lost releases,
other modifiers, F18 during Shift, and late input-source changes. They verify source selection at
event delivery, including native CJK activation, but do not assert what a target
app actually inserts.

For the app-level regression, use a Slack composer with no recipients. Switch
ABC to Korean and type the physical A key followed by Space without leaving the
app. The expected text is `ㅁ `, not `a `. Repeat after temporary English and
manual language toggles. Never send the test draft; clear its text afterwards.
