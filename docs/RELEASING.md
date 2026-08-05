# Release checklist

This checklist describes public release mechanics. Signing credentials and private infrastructure details must not be added to this repository.

- [ ] Confirm the intended QLab 5 feature set and version number.
- [ ] Update `Packaging/Info.plist`, `README.md`, `CHANGELOG.md`, and compatibility documentation.
- [ ] Run automated tests and build validation.
- [ ] Build the universal app and verify `arm64` and `x86_64` slices.
- [ ] Verify both slices retain the macOS 11 deployment target.
- [ ] Sign and validate the app bundle.
- [ ] Test the packaged app on relevant physical macOS and QLab environments.
- [ ] Preserve the numbered app locally.
- [ ] Create a Mac-aware ZIP containing the normally named app bundle.
- [ ] Verify the ZIP and record its SHA-256 digest.
- [ ] Commit with the public GitHub no-reply identity.
- [ ] Push `main` to GitHub `origin` and the `gitea` remote.
- [ ] Create and push the version tag to both remotes.
- [ ] Publish the GitHub Release and attach the ZIP.
- [ ] Verify the uploaded asset digest and download instructions.
- [ ] Update `COMPATIBILITY.md` as release testing is completed.
- [ ] Check whether the corresponding QLab 4 release needs aligned changes and versioning.
