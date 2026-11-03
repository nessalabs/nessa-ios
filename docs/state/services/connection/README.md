---
id: "connection"
title: "Connect the phone"
kind: "service"
status: "implemented"
summary: "Use a paired Mac or an explicit gateway connection; disconnect is a local pause."
parent: "nessa-ios"
sources:
  [
    "Sources/NessaFeatures/Presentation/Pages/NessaConnectionView.swift",
    "Sources/NessaFeatures/Presentation/Pages/PairWithDesktopView.swift",
    "Sources/NessaFeatures/Application/DesktopLinking.swift",
    "Sources/NessaFeatures/Infrastructure/NessaGatewayClient.swift",
  ]
sourceRevision: "8a027f07ecc1b27fb63502852648cb467e308720"
diagramLinks: {}
---

# Connect the phone

The live phone can reach a paired Mac through its native link or use an explicit
gateway address and credential. The app keeps the gateway's remote authorization
separate from its local choice to connect. Disconnect pauses this phone; it does
not revoke the device on the Mac.

- [Pair, replace or forget a Mac](pairing.md).
- [Connect, disconnect and recover](session.md).
- [Follow live chat changes](subscriptions.md).
- [Native bridge ownership](native.md).

For offline content, continue to [saved history](../history/README.md). The Apple
network permission, Bonjour discovery and a reachable gateway are prerequisites;
passing a local fixture is not proof they work on a physical phone.
