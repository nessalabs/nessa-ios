---
id: "history-storage"
title: "Understand storage failures"
kind: "contract"
status: "implemented"
summary: "Atomic replacement and readback do not turn an unconfirmed durable write into success."
parent: "history"
sources:
  [
    "Sources/NessaFeatures/Infrastructure/PrivatePhoneFiles.swift",
    "Sources/NessaFeatures/Infrastructure/PrivatePhoneRecordPublication.swift",
    "Sources/NessaFeatures/Infrastructure/PhoneProfileStore.swift",
    "Sources/NessaFeatures/Infrastructure/PhoneProfileCredentials.swift",
    "Sources/NessaFeatures/Infrastructure/NessaCredentialStore.swift",
    "Sources/NessaFeatures/Infrastructure/PhoneCommandStore.swift",
    "Sources/NessaFeatures/Infrastructure/PhoneOutboxFileStore.swift",
  ]
sourceRevision: "8a027f07ecc1b27fb63502852648cb467e308720"
diagramLinks: {}
---

# Interpret local storage failures

A local storage error can occur after replacement bytes become visible. The phone
therefore distinguishes successful durable publication from a readback that merely
sees the intended bytes. Recovery may find either the old record, the new record
or uncertainty; callers must not assume rollback from an error alone.

Private file stores use bounded regular files and validated hexadecimal keys,
private directory/file permissions, backup exclusion and atomic replacement.
They synchronize the file and directory and use stable nonblocking file locks
for transactions. These checks are infrastructure defenses, not a model of every
filesystem crash. Profile and intent stores validate schemas and exact identities
before using loaded records.

Credentials use Keychain in live mode. A profile's credential reference is kept
separately from its registry metadata. Development uses in-memory adapters. A
simulator build needs suitable signing/entitlements for Keychain; a successful
Swift build on macOS does not prove iPhone credential storage.

Storage tests exercise compare-and-replace, bounded records, locking and injected
publication failures. [Profile preparation](profiles.md) models only the caller's
write ordering. The current verification did not power-cycle a device, prove
filesystem durability, or inspect private user credentials.
