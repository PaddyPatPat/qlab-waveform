# Contributing

Bug reports, compatibility results, documentation improvements, and focused code contributions are welcome.

## Before opening an issue

- Use this repository for the QLab 5 edition. QLab 4.7 and Catalina issues belong in [qlab-waveform-qlab4](https://github.com/PaddyPatPat/qlab-waveform-qlab4).
- Search existing issues first.
- For compatibility reports, include the Mac model, processor architecture, exact macOS version, exact QLab version, and QLab Waveform version.
- Never post OSC passcodes, private QLab shows, licensed media, or other sensitive production information.

## Development

Build and run the Swift package with:

```sh
swift build
swift run QLabWaveform
```

Build the universal ad-hoc-signed app with:

```sh
./scripts/package-universal-app.sh
```

QLab communication must stay off the main UI thread. OSC credentials must remain in memory and must never be persisted or logged. QLab 4 and QLab 5 behavior should remain aligned unless an implementation or compatibility difference requires otherwise.

## Pull requests

- Keep changes focused and explain their user-visible effect.
- Add or update tests when practical.
- Describe the macOS, architecture, and QLab versions used for runtime testing.
- Do not commit build output, QLab show files, media, credentials, or local machine paths.
- Confirm `swift build` succeeds before requesting review.

Contributions are accepted under the repository's GPL-3.0-only licence.
