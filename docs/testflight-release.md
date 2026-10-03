# TestFlight release rule

Current release and handoff state is maintained in [AIQuickNote Current Status and Handoff](../CURRENT_STATUS.md), including the passed pipeline status and the planned STAGING Build 6. The release rules below remain in effect.

- Keep `MARKETING_VERSION` at `0.1` until a deliberate app version change.
- Before every App Store Connect upload, increment `CURRENT_PROJECT_VERSION` in both app configurations in `ios/AIQuickNote.xcodeproj/project.pbxproj` (for example, `1` to `2`). Never reuse an uploaded build number for the same marketing version.
- Do not commit signing certificates, private keys, provisioning profiles, Apple passwords, API keys, or session tokens.
