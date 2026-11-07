---
id: "inventory"
title: "Feature and owner inventory"
kind: "guide"
status: "reference"
summary: "Every major reachable feature, reusable API and platform boundary has a stated owner and verification scope."
parent: "nessa-ios"
sources:
  [
    "Package.swift",
    "Sources/NessaFeatures/Composition/NessaDependencies.swift",
    "Sources/NessaFeatures/Presentation/Pages/NessaMessagesView.swift",
  ]
sourceRevision: "8a027f07ecc1b27fb63502852648cb467e308720"
diagramLinks: {}
---

# Feature inventory and source ownership

This inventory follows the app entry point, application ports, concrete adapters
and UI actions at the recorded source. A source-reviewed page is not necessarily
a modeled page. Direct models check only the bounded claims described there;
other behavior is explicitly source/test evidence rather than a borrowed proof.

| Feature or owner                                                                       | Verification disposition                 | Main source owner                                                                |
| -------------------------------------------------------------------------------------- | ---------------------------------------- | -------------------------------------------------------------------------------- |
| [Find a chat and move between screens](navigation.md)                                  | Source review; no direct model           | `Sources/NessaFeatures/Presentation/Pages/NessaMessagesView.swift`               |
| [Chat and delivery](services/chat/README.md)                                           | Index                                    | `Sources/NessaFeatures/Presentation/ViewModels/MessagesViewModel.swift`          |
| [Send a message and recover uncertain delivery](services/chat/delivery.md)             | Direct model: `OutboxRecovery`           | `Sources/NessaFeatures/Application/PhoneOutbox.swift`                            |
| [Keep edits made while a send is finishing](services/chat/draft.md)                    | Direct model: `DraftOwnership`           | `Sources/NessaFeatures/Presentation/ViewModels/ComposerDraftViewModel.swift`     |
| [Check or retry a saved command](services/chat/journal.md)                             | Direct model: `JournalRefusal`           | `Sources/NessaFeatures/Application/PhoneCommandJournal.swift`                    |
| [Ask the current turn to stop](services/chat/stop.md)                                  | Source review; no direct model           | `Sources/NessaFeatures/Application/PhoneProductChat.swift`                       |
| [Answer a waiting permission request](services/chat/permissions.md)                    | Source review; no direct model           | `Sources/NessaFeatures/Application/ReviewDetails.swift`                          |
| [Read replies and keep local reactions](services/chat/reading.md)                      | Source review; no direct model           | `Sources/NessaFeatures/Presentation/Pages/NessaThreadView.swift`                 |
| [Archive or delete a chat](services/chat/archive-delete.md)                            | Source review; no direct model           | `Sources/NessaFeatures/Presentation/ViewModels/MessagesViewModel.swift`          |
| [Connect the phone](services/connection/README.md)                                     | Index                                    | `Sources/NessaFeatures/Presentation/Pages/NessaConnectionView.swift`             |
| [Pair with a Mac or forget its link](services/connection/pairing.md)                   | Direct model: `LinkedRetirement`         | `Sources/NessaFeatures/Application/DesktopLinking.swift`                         |
| [Pause a connection and reconnect](services/connection/session.md)                     | Source review; no direct model           | `Sources/NessaFeatures/Presentation/ViewModels/MessagesViewModel.swift`          |
| [Follow the inbox and current thread](services/connection/subscriptions.md)            | Direct model: `SubscriptionCancellation` | `Sources/NessaFeatures/Infrastructure/GatewaySubscriptions.swift`                |
| [Understand the native bridge boundary](services/connection/native.md)                 | Source review; no direct model           | `Sources/NessaFeatures/Infrastructure/Native/NativeGatewayProductExchange.swift` |
| [Read saved chats without inventing access](services/history/README.md)                | Index                                    | `Sources/NessaFeatures/Application/PhoneRetainedHistory.swift`                   |
| [Read history belonging to the current profile](services/history/retained.md)          | Direct model: `HistoryCorrelation`       | `Sources/NessaFeatures/Application/PhoneRetainedHistory.swift`                   |
| [Prepare and retire a native profile](services/history/profiles.md)                    | Direct model: `ProfilePreparation`       | `Sources/NessaFeatures/Application/PhoneProfilePreparation.swift`                |
| [Keep a bounded local display cache](services/history/snapshot.md)                     | Source review; no direct model           | `Sources/NessaFeatures/Application/PhoneSnapshots.swift`                         |
| [Distinguish management APIs from screen actions](services/history/management-apis.md) | Source review; no direct model           | `Sources/NessaFeatures/Application/PhoneConversationSharing.swift`               |
| [Interpret local storage failures](services/history/storage.md)                        | Source review; no direct model           | `Sources/NessaFeatures/Infrastructure/PrivatePhoneFiles.swift`                   |
| [Send media or dictate a message](services/media/README.md)                            | Index                                    | `Sources/NessaFeatures/Presentation/Composites/MessageComposer.swift`            |
| [Prepare and upload a photo or file](services/media/attachments.md)                    | Source review; no direct model           | `Sources/NessaFeatures/Application/AttachmentPolicy.swift`                       |
| [View a photo or file in a conversation](services/media/display.md)                    | Source review; no direct model           | `Sources/NessaFeatures/Presentation/Components/PhotoAttachment.swift`            |
| [Dictate text and cancel stale results](services/media/dictation.md)                   | Direct model: `DictationGeneration`      | `Sources/NessaFeatures/Presentation/ViewModels/DictationViewModel.swift`         |

## Supporting and non-screen areas

| Area                                                                                   | Boundary and destination                                                                                         |
| -------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------- |
| Domain IDs, command/refusal values, channels, agent/model catalogue, reply projections | Value contracts used by chat/navigation pages; no fabricated retained lifecycle.                                 |
| Design-system tokens, shared controls, glass, haptics and motion                       | [Development](development.md) and [reading](services/chat/reading.md); platform visual checks unrun.             |
| Native retained/product wrappers and generated bindings                                | [Native bridge](services/connection/native.md); independent vendor pin and platform artifacts.                   |
| Generated ready/pairing/wire DTO grammar                                               | Infrastructure adapter validation; generator pin is separate from vendor pin.                                    |
| Keychain, profile, command, outbox, deletion/share and approval stores                 | [Storage](services/history/storage.md) and [management APIs](services/history/management-apis.md).               |
| Development fixtures and mocks                                                         | [Composition](development.md); sample behavior is not live gateway qualification.                                |
| Swift verifier, socket fixtures, stress driver, architecture/design checks and CI      | [Verification](verification.md); commands listed separately from what ran.                                       |
| Historical design plans and audits                                                     | Existing docs remain intact; this atlas checkpoints current composition rather than declaring all plans shipped. |
| External gateway/provider and Apple services                                           | Explicit external boundaries; client-side models cannot prove their behavior.                                    |

The normal entry point does not expose every reusable management API. Read the
management page before claiming a user can perform those operations. New features
should gain a concrete owner/explanation and a justified verification disposition;
adding a generic model merely to increase coverage counts is not useful.
