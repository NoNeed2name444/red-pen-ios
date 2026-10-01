# Red Pen — native apps

The native rewrite of [Red Pen](https://claude.ai/artifact/JAJnuA78ieocypcaS4YF4X), a
medical-exam study app. Everything here is pushed and built from the Red Pen
chat through its bridge; the repository is public so that GitHub's macOS
runners are free.

- `ios/` — the SwiftUI app (see `ios/README.md`).
- `.github/workflows/ios-preview.yml` — builds the app on a macOS runner,
  screenshots every screen in the iOS Simulator (light and dark), and pushes
  the pictures, build log and compile errors to the `previews` branch.
- `android/` — planned; not started yet.
