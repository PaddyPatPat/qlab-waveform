# Compatibility

This table records runtime tests performed with the downloadable GitHub release, not merely successful compilation against a deployment target.

| App version | QLab version | macOS | Architecture | Status | Evidence |
|---|---|---|---|---|---|
| 0.4.0 | QLab 5 | Big Sur 11 | Intel | Pending | [Validation issue](https://github.com/PaddyPatPat/qlab-waveform/issues?q=is%3Aissue+label%3A%22Intel%22+label%3Acompatibility) |
| 0.4.0 | QLab 5 | Big Sur 11 | Apple Silicon | Pending | [Validation issue](https://github.com/PaddyPatPat/qlab-waveform/issues?q=is%3Aissue+label%3A%22Apple+Silicon%22+label%3A%22Big+Sur%22) |
| 0.4.0 | QLab 5 | macOS 26 Tahoe | Intel | Pending | [Validation issue](https://github.com/PaddyPatPat/qlab-waveform/issues?q=is%3Aissue+label%3A%22Intel%22+label%3A%22macOS+26%22) |
| 0.4.0 | QLab 5.6.3 | macOS 26.6 Tahoe (25G72) | Apple Silicon | Passed | [Issue #4](https://github.com/PaddyPatPat/qlab-waveform/issues/4) — validated by Patrick Duncan |

## Validation checklist

A compatibility result should record the Mac model, processor architecture, exact macOS version, and exact QLab version, then verify:

- The ZIP was downloaded from the GitHub Release and expanded successfully.
- The app passed the documented first-launch and Gatekeeper process.
- macOS Automation permission was granted.
- OSC connected, including passcode entry where applicable.
- Audio cue start, pause, resume, seek, stop, and waveform switching worked.
- Elapsed and remaining timers behaved correctly.
- Countdown background pulses appeared at the documented thresholds.
- Auto-follow and monitoring states were accurate.
- OSC fallback and reconnection behaved correctly.

Build success alone does not change a row to Passed. Runtime validation requires QLab and the named macOS environment.
