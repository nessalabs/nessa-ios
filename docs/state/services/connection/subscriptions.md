---
id: "connection-subscriptions"
title: "Follow live changes"
kind: "statechart"
status: "implemented"
summary: "A cancelled pending subscription cannot become a live feed when its
  reply arrives late."
parent: "connection"
sources:
  [
    "Sources/NessaFeatures/Infrastructure/GatewaySubscriptions.swift",
    "Sources/NessaFeatures/Application/ConversationFollowing.swift",
    "Sources/NessaFeatures/Application/MessagingService.swift",
    "Tests/NessaFeaturesTests/LiveFeedTests.swift",
  ]
sourceRevision: "8a027f07ecc1b27fb63502852648cb467e308720"
diagramLinks: {}
model:
  {
    "spec": "tla/SubscriptionCancellation.tla",
    "config": "tla/SubscriptionCancellation.cfg",
  }
modelCheck:
  sourceRevision: "8a027f07ecc1b27fb63502852648cb467e308720"
  checker: tlc-1.7.4
  date: 2026-11-03T08:47:59.870Z
  config: tla/SubscriptionCancellation.cfg
  modelDigest: cbad33008579a24c8dcf20fc68a9a0c8b837de3da47585050f31d1deb9551e08
  states: 5
  held:
    - NoCancelledActivation
    - LateIDRetainedForCleanup
  broke: []
  unchecked: []
diagramDetails:
  [
    {
      "diagram": 0,
      "node": "CancelledPending",
      "section": "Keep the late registration cleanup path",
    },
    {
      "diagram": 0,
      "node": "Ended",
      "section": "An ended feed is not deleted history",
    },
  ]
---

# Follow the inbox and current thread

While connected, the phone follows one inbox and one visible thread. The gateway
sends replacement views rather than a durable replay log for the phone. A slow
screen retains only the newest pending frame per feed, so a missed intermediate
frame is not itself a lost persisted message.

Before sending a subscription request, the socket owner records the caller. It
registers the server's returned ID before resuming that caller. If the caller
cancelled while registration was pending, the late ID is returned for cleanup
instead of becoming a live feed.

```mermaid
stateDiagram-v2
  [*] --> Pending
  Pending --> Live: Server ID received while caller remains
  Pending --> CancelledPending: Caller cancels
  CancelledPending --> Cleanup: Late server ID arrives
  Live --> Ended: Cancel or server termination
  Live --> Ended: Malformed frame for this feed
```

Unknown or retired IDs are ignored. A thread frame must name that thread; a list
frame belongs only to the inbox. A malformed publication closes its own feed,
not every other subscription. An ended feed can be lagging, refused, source-closed
or too-large. The application retries lag/source closure with its applied cursor;
it does not retry a refusal as if access had been granted.

A cursor identifies the source incarnation and offset. Older offsets from the
same incarnation are ignored. Applied view cursors are UI observation state,
not the native retained engine's physical replication checkpoint.

`SubscriptionCancellation` models one pending registration, caller cancellation
and late activation. It checks that a cancelled caller is never activated and
that the late server ID is returned for cleanup. Controls remove the cancellation
branch or its cleanup assignment. Capacity two, frame grammar, buffering and
actual socket ordering remain implementation test scope.

## Keep the late registration cleanup path

Cancelling the caller removes its continuation but retains the pending registration. If the server ID arrives later, it is returned for cleanup rather than becoming a live feed.

## An ended feed is not deleted history

The feed can end because of cancellation, lag, source closure, refusal, or a malformed publication. The application retries lag/source closure; refusal is not retried as if authorized. Persisted conversation history is a different owner.
