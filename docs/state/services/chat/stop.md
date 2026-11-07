---
id: "chat-stop"
title: "Stop the current turn"
kind: "operation"
status: "implemented"
summary: "Stop records a stable identity; reconnect checks it without automatically sending again."
parent: "chat"
sources:
  [
    "Sources/NessaFeatures/Application/PhoneProductChat.swift",
    "Sources/NessaFeatures/Presentation/ViewModels/MessagesViewModel.swift",
    "Sources/NessaFeatures/Presentation/Pages/NessaThreadView.swift",
  ]
sourceRevision: "8a027f07ecc1b27fb63502852648cb467e308720"
diagramLinks: {}
diagramDetails:
  [
    {
      "diagram": 0,
      "node": "Unknown",
      "section": "Unknown Stop is not verified termination",
    },
  ]
---

# Ask the current turn to stop

The thread's Stop control targets the turn currently shown as running. It does
not cancel every conversation and does not prove that all provider work has
already ended. The phone asks the product gateway to stop that conversation and
execution ID, then observes the gateway's answer.

Before sending, the live product owner saves a Stop record with a request ID.
If you explicitly stop the same turn again, it looks up that saved request first.
Only an absent receipt permits another send with the same ID. Restart recovery
looks up retryable Stop records and does not resend them.

```mermaid
flowchart LR
  Tap[Tap Stop for shown turn] --> Saved[Save original Stop identity]
  Saved --> Ask[Ask gateway]
  Ask --> Known[Known stage or refusal]
  Ask --> Unknown[Unknown delivery]
  Unknown --> Lookup[Restart checks receipt]
  Lookup --> Unknown
  Unknown --> Explicit[Another explicit Stop]
  Explicit --> LookupFirst[Lookup before same-ID resend]
```

Accepted, running and done describe gateway receipt stages. Lost/unreadable
responses lead to lookup; an attempted or unresolved result remains uncertain.
A revocation refusal disables automatic connection. The view model does not
publish a separate durable Stop status row or a universal cleanup confirmation.
If the thread still shows running, no local timer proves remote termination.

The flow is source-reviewed, with PhoneProductChat tests in the Swift baseline.
The outbox model's no-replay principle is related, but it does not directly model
Stop's record grammar or provider termination. These are explicit unmodeled
boundaries, not an additional claimed TLA pass.

## Unknown Stop is not verified termination

The gateway may have acted despite a missing reply. Restart looks up this saved Stop and never resends it automatically. Another explicit Stop checks the original receipt and only resends the same request if absent.
