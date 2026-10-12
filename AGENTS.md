# InputPilot

- Native macOS 13+ menu-bar application. Swift Package Manager builds the executable; scripts/build-app.sh creates the app bundle.
- Sources/InputPilotCore contains pure rule/state logic. Sources/InputPilot contains AppKit/SwiftUI and Carbon/ServiceManagement adapters.
- Explicit fixed rules take precedence over remembered input. Programmatic changes must never overwrite remembered choices. New activations invalidate old switching requests.
- Configuration belongs to Application Support/InputPilot/config.json. Never read or mutate other input-switching apps' preferences.
- Run swift run InputPilotCoreChecks and scripts/build-app.sh for behavior changes. The local Command Line Tools lack XCTest; the checks use a standalone assertion runner. Keep runtime verification separate from build/test results.
- Do not commit derived binaries, user configuration, or the parent directory's reverse-engineering evidence.
