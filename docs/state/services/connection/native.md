---
id: "connection-native"
title: "Native bridge boundary"
kind: "contract"
status: "implemented"
summary: "Swift wrappers call a pinned native package; model and fixture evidence do not certify live device transport."
parent: "connection"
sources:
  [
    "Sources/NessaFeatures/Infrastructure/Native/NativeGatewayProductExchange.swift",
    "Sources/NessaFeatures/Infrastructure/Native/NativeLinkedProducts.swift",
    "Sources/NessaFeatures/Infrastructure/Native/NativeRetainedSession.swift",
    "Vendor/NessaNative/Sources/NativeProductWorker.swift",
    "Vendor/NessaNative/Sources/ProductSubmitLane.swift",
    "Vendor/NessaNative/SOURCE.json",
  ]
sourceRevision: "8a027f07ecc1b27fb63502852648cb467e308720"
diagramLinks: {}
---

# Understand the native bridge boundary

A paired Mac connection uses the native package's saved device identity. Swift
opens a retained session, opens its product child, and closes both through the
exchange owner. The linked-desktop owner counts that exchange as an active reader
until its physical close is reported, so local Forget cannot remove files while
it is using them.

The Swift product wrapper queues short submission calls in arrival order. The
queue releases when native returns a ticket, an object that owns waiting for the
response; it does not serialize all response waits. Queued cancellation removes
that attempt. Once a native handoff starts, cancellation or orderly close cannot
prove that the gateway command did nothing. The Swift queue itself has no size
limit or queue-wait timeout; downstream native deadlines are separate.

The package is vendored from nessa-agent commit
`bd278df230863db5eb0aee615dcd9069bd5e8fe5`, recorded with artifact hashes in
[SOURCE.json](../../../../Vendor/NessaNative/SOURCE.json). Its generated bindings
and arm64 XCFramework are not current source from this repository. The phone's
generated gateway grammar has its own pin, maintained by
[the generator](../../../../scripts/generate-gateway-pairing.py).

Local Swift tests can call the included macOS native artifact and use fixtures
for mapped statuses, identity, cancellation and close/reopen. They do not prove
the iPhone binary, TLS peer, deployed gateway or physical network behaves the
same. No duplicate native lifecycle model is claimed here; the upstream native
owner and this adapter's source remain separate review scopes.
