---
id: "development"
title: "Run the app"
kind: "guide"
status: "reference"
summary: "Debug sample mode, live mode and vendored artifacts have different evidence boundaries."
parent: "nessa-ios"
sources:
  [
    "Package.swift",
    "App/Nessa/NessaApp.swift",
    "Sources/NessaFeatures/Composition/NessaDependencies.swift",
    "scripts/verify.sh",
    "Vendor/NessaNative/SOURCE.json",
  ]
sourceRevision: "8a027f07ecc1b27fb63502852648cb467e308720"
diagramLinks: {}
---

# Run the app and understand its adapters

Open `App/Nessa.xcodeproj`, choose the Nessa scheme and an iPhone simulator for
an app build. The Swift package also builds on macOS for local tests and the
PhoneSyncVerification executable. These are different targets; macOS tests do
not render the iPhone app.

Debug defaults to `MockRepository`, in-memory credentials/preferences and a mock
speech transcriber. Its chats reset on restart. Set `NESSA_MODE=live` in the Xcode
scheme environment to use live adapters. Release always selects live. Optional
Debug launch connection variables are verification inputs, not shipped credentials.
Use a reachable gateway; a phone's localhost is the phone itself.

`NessaDependencies` is the composition root: it supplies repository, directory,
credential/preference stores, retained session factory, profile runtime and product
outbox. Views receive view models; domain code does not import SwiftUI. The design
system owns shared color, spacing, typography, shapes and motion. iOS 26 uses
system safe-area bars/scroll effects; older supported systems have a fallback.
These are platform branches requiring visual qualification.

Run the repository's documented baseline from its root:

```sh
./scripts/verify.sh
```

It runs architecture/design-system checks, builds Swift products and executes
Swift tests. [Verification](verification.md) records this run's actual results
and separate native fixture/live-file commands. No user gateway credentials were
read or used for this atlas.

The [native bridge](services/connection/native.md) records the exact independent
vendor revision. Generated gateway grammar is maintained from its own reviewed
schema pin. Do not update either pin merely to make a documentation date current.
