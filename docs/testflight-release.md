# TestFlight release rule

- Keep `MARKETING_VERSION` at `0.1` until a deliberate app version change.
- Before every App Store Connect upload, increment `CURRENT_PROJECT_VERSION` in both app configurations in `ios/AIQuickNote.xcodeproj/project.pbxproj` (for example, `1` to `2`). Never reuse an uploaded build number for the same marketing version.
- Do not commit signing certificates, private keys, provisioning profiles, Apple passwords, API keys, or session tokens.
