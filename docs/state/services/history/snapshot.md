---
id: "history-snapshot"
title: "Keep recent display data"
kind: "flow"
status: "implemented"
summary: "Snapshot writes are serialized and withdrawn scopes cannot be hydrated again."
parent: "history"
sources:
  [
    "Sources/NessaFeatures/Application/PhoneSnapshots.swift",
    "Sources/NessaFeatures/Application/PhoneSnapshotWithdrawal.swift",
    "Sources/NessaFeatures/Infrastructure/PhoneSnapshotStore.swift",
    "Sources/NessaFeatures/Infrastructure/SnapshotWithdrawalMarker.swift",
    "Tests/NessaFeaturesTests/PhoneSnapshotTests.swift",
    "Tests/NessaFeaturesTests/PhoneSnapshotWithdrawalTests.swift",
  ]
sourceRevision: "8a027f07ecc1b27fb63502852648cb467e308720"
diagramLinks: {}
---

# Keep a bounded local display cache

The legacy display cache lets an eligible phone reopen recent content while it
has no network connection. It stores a list, agent summaries and up to twenty
recent conversation views. It is derived screen data, not a native replication
checkpoint or a credential granting access.

Each scope is a hash of length-delimited address, instance and credential values.
The session gives its writer a lease for that exact scope. Older saves finish
before newer ones start; queued updates coalesce after a short delay. A callback
with an old lease cannot change the new snapshot.

A withdrawal permanently suppresses that display scope: the session blocks it
before awaiting a writer, clears queued updates for it, then asks storage to
publish a withdrawal marker. If that write fails, the operation reports failure;
it does not call visible bytes a durable success. Suppressing this derived cache
does not itself revoke or purge the native receiver.

A list that omits a conversation does not delete its cached transcript, because
the live inbox excludes archived chats. Explicit confirmed local removal marks
the ID so a later old view cannot put it back. Corrupt, oversized or unavailable
cache content cannot establish live authority.

The implementation has tests for held writers, scope replacement, withdrawal and
publication failures. This page is a source-reviewed flow with no direct TLA
model; do not interpret the profile preparation model as proving all cache races.
