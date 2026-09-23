# UI regression repair — baseline 0c45692

Scope: Home navigation gestures and floating Detail presentation only. Core, parser, speech, persisted fields, search and reminder semantics are frozen.

- Confirmed device failure: a zero-distance DragGesture inside the NavigationLink label begins immediately and competes with semantic activation. Move visual observation onto the link, require 12 points of movement, and reset GestureState with a spring on completion/cancellation. Decorative overlays do not hit-test.
- Routing audit: Home -> ModuleListView -> record button -> sheet and SearchView -> result button -> sheet already exist. No legacy Detail push exists in this baseline. Home's broken link blocks the first route. The former 88%/large detents also leave too little visible parent context and can expand to a full-page appearance. Device-specific presentation state cannot be proven from source alone.
- Both actual record routes now share DetailSheet at 76% height, with native dimming, 32-point corners, drag indicator, scrolling and dismissal physics, plus a top-right accessible X. Primary module navigation remains a push.
- Add XCUITest interaction coverage and retained screenshots before packaging. Test fixtures are DEBUG-only, isolated from production records, and use the existing Core.
- Physical-device Reduce Motion, VoiceOver, imported/Falling skins and exact gesture feel still require device confirmation.
