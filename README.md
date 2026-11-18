# WalkTour

Turn a walk-through video into a tappable photo-hop tour (Street View style) on iPhone and iPad. Everything stays on the device: no accounts, no uploads.

## Use
1. Film a slow walk through a space (landscape or portrait, steady, good light).
2. Tap **+**, pick the video, choose the spacing (a stop every 0.5–4 s), tap **Build**.
3. In the tour: tap the right/left side of the screen or drag to hop; **walk** button autoplays; slider scrubs; **tag** button labels a spot (Kitchen, Bedroom) and adds a jump chip; tap the centre to hide controls.

Near-duplicate frames (when you paused) are skipped automatically.

## Build
**Option A: you have a Mac.** `brew install xcodegen && xcodegen generate`, open `WalkTour.xcodeproj`, set your team, run.

**Option B: no Mac.** Push to GitHub; the `iOS Build (unsigned IPA)` workflow produces `WalkTour-unsigned.ipa`. Sideload with AltServer for Windows using your Apple ID.

Targets iOS 17+, iPhone and iPad (all orientations, Split View/Slide Over supported).
