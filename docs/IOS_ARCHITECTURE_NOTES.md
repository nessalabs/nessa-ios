# iOS Architecture Notes

This app starts as a local-first native SwiftUI shell around a reusable Swift package.

Sources used for the initial direction:

- Apple SwiftUI model-data guidance: keep a source of truth in model data and separate data models from views for modularity and testability.
- Apple Swift packages guidance: use local packages to organize reusable code that can be developed alongside an app.
- Apple XCTest and Swift Testing guidance: use Swift Testing for modern unit tests where practical, and XCTest for UI automation.
- Apple Logger guidance: create loggers with subsystem and category so app logs are searchable later.

Decisions:

- The reusable code lives in SwiftPM targets: `SharedKernel`, `ClawdiaObservability`, `ClawdiaDesignSystem`, and `ClawdiaFeatures`.
- The app shell in `App/Clawdia` launches `DevModeRootView` so every mock screen and design-system component is easy to open during development.
- Localhost and future cloud communication share the `ClawdiaEndpoint` domain concept. `LocalhostClawdiaClient` currently probes `/health` on `127.0.0.1:<port>` for local development.
- Verification is scripted through `scripts/verify.sh` and checks DDD boundaries, design-system use, and tests.
