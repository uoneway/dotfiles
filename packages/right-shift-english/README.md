# Right Shift English

Hold right Shift for temporary uppercase English; release it to restore the
baseline input source. F18 toggles the baseline between ABC and Korean. The app
runs independently of Karabiner; Karabiner may map Caps Lock to F18.

## 1.0.2: request Accessibility permission during installation

When permission is missing, the installer requests the macOS Accessibility
prompt and reports that approval is required before use. Approve the app in
System Settings, then run `dotfiles install right-shift-english` to start it.
The app checks and requests Core Graphics PostEvent access, which is required
for its filtering keyboard event tap and synthetic input-source shortcut events.
An Accessibility check alone can disagree with this permission on macOS 27.
The installer opens the app separately to request permission and confirms the
LaunchAgent is running before reporting success. An already-running daemon takes
precedence over a terminal-launched permission check.

The system controls whether it displays the prompt again. Silent permission
checks remain available through `--check-permission`.

If the System Settings toggle is enabled but the daemon exits, inspect
`~/.local/share/karabiner-shift-english/daemon-error.log` and the macOS TCC log.
When TCC specifically reports a denied PostEvent record despite the enabled
toggle, reset only this app's PostEvent approval, preserving its Accessibility
approval, then restart the app:

```sh
tccutil reset PostEvent local.karabiner.shift-english
dotfiles install right-shift-english
```

This is a recovery step for a confirmed permission mismatch, not an automatic
part of installation. Approve any permission request shown by macOS.

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
swiftc -O packages/right-shift-english/1.0.1/ShiftEnglish.swift -o /tmp/right-shift-english-test
/tmp/right-shift-english-test --self-test-keyboard
```

These checks exercise queued events, both Shifts, lost releases, other modifiers,
F18 during Shift, and late input-source changes. They verify source selection at
event delivery, including native CJK activation, but do not assert what a target
app actually inserts.

For the app-level regression, use a Slack composer with no recipients. Switch
ABC to Korean and type the physical A key followed by Space without leaving the
app. The expected text is `ㅁ `, not `a `. Repeat after temporary English and
manual language toggles. Never send the test draft; clear its text afterwards.
