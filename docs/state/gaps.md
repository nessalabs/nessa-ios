---
id: "gaps"
title: "Known limits and findings"
kind: "guide"
status: "reference"
summary: "Do not infer missing product capabilities from the existence of lower-level helpers."
parent: "nessa-ios"
sources:
  [
    "README.md",
    "Sources/NessaFeatures/Composition/NessaDependencies.swift",
    "Sources/NessaFeatures/Presentation/ViewModels/MessagesViewModel.swift",
    "Sources/NessaFeatures/Application/PhoneProductChat.swift",
  ]
sourceRevision: "8a027f07ecc1b27fb63502852648cb467e308720"
diagramLinks: {}
---

# Known limits and source-review findings

The current phone has useful working paths and deliberate boundaries. These
limits affect what a reader can safely conclude from the map.

| Boundary                                                                                          | Consequence                                                                         |
| ------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------- |
| Normal swipe deletion does not call the durable deletion actor                                    | No promise of restart-safe Check/Retry for that screen action.                      |
| Live product outbox treats unknown delivery as retained                                           | The unchanged composer can clear while Delivery not confirmed remains.              |
| Product outbox and alternate native-history path use different readiness gates                    | Cached history and command authority must be explained per route.                   |
| Technical sharing/profile controls are absent from normal Settings                                | API tests do not make those controls available or widen remote grants.              |
| Remote photo retrieval is absent                                                                  | A valid message may show a local unavailable-image placeholder.                     |
| Reactions, unread and mute preferences are local                                                  | Another device does not automatically receive them; mute is not push configuration. |
| Audio attachments, general agent questions, push and full transcript pagination remain unfinished | Dictation and permission cards must not be presented as those features.             |
| First Home/channel message is passed through in-memory navigation                                 | Creating a chat does not guarantee its first draft survives app termination.        |

The source README has broad historical statements about fresh native evidence
before sending and drafts remaining until success. The current composition and
outbox view-model branches require the more specific account above. This atlas
records the inspected implementation; it does not silently change product code
to match the older prose. Those differences are documentation reconciliation
findings, not newly reproduced runtime defects.

No new app bug is claimed solely from a model failure or static concern. The
[verification page](verification.md) states the actual tests and unrun platforms.
Where a recovery operation is not available, these pages say so rather than
inventing a safe retry recipe.
