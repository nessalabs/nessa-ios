import Foundation
import NessaNative

// NoHandle fakes are never lowered into Rust. Each getter checks off-UI capture.
final class FixtureNativeCatalogueEntry: NativeCatalogueEntry, @unchecked Sendable {
  let stored_agent: String?
  let stored_archived: Bool?
  let stored_createdAtMs: UInt64?
  let stored_deleted: Bool
  let stored_key: NativeEntryKey
  let stored_model: String?
  let stored_preview: String?
  let stored_revision: UInt64
  let stored_title: String?
  let stored_updatedAtMs: UInt64?
  init(
    agent: String? = "  NativeCatalogueEntry.agent  ", archived: Bool? = true,
    createdAtMs: UInt64? = UInt64.max - 2, deleted: Bool = true,
    key: NativeEntryKey = FixtureNativeEntryKey(),
    model: String? = "  NativeCatalogueEntry.model  ",
    preview: String? = "  NativeCatalogueEntry.preview  ", revision: UInt64 = UInt64.max - 7,
    title: String? = "  NativeCatalogueEntry.title  ", updatedAtMs: UInt64? = UInt64.max - 9
  ) {
    stored_agent = agent
    stored_archived = archived
    stored_createdAtMs = createdAtMs
    stored_deleted = deleted
    stored_key = key
    stored_model = model
    stored_preview = preview
    stored_revision = revision
    stored_title = title
    stored_updatedAtMs = updatedAtMs
    super.init(noHandle: .init())
  }
  required init(unsafeFromHandle handle: UInt64) { fatalError("fixture cannot be lowered") }
  override func agent() -> String? {
    precondition(!Thread.isMainThread)
    return stored_agent
  }
  override func archived() -> Bool? {
    precondition(!Thread.isMainThread)
    return stored_archived
  }
  override func createdAtMs() -> UInt64? {
    precondition(!Thread.isMainThread)
    return stored_createdAtMs
  }
  override func deleted() -> Bool {
    precondition(!Thread.isMainThread)
    return stored_deleted
  }
  override func key() -> NativeEntryKey {
    precondition(!Thread.isMainThread)
    return stored_key
  }
  override func model() -> String? {
    precondition(!Thread.isMainThread)
    return stored_model
  }
  override func preview() -> String? {
    precondition(!Thread.isMainThread)
    return stored_preview
  }
  override func revision() -> UInt64 {
    precondition(!Thread.isMainThread)
    return stored_revision
  }
  override func title() -> String? {
    precondition(!Thread.isMainThread)
    return stored_title
  }
  override func updatedAtMs() -> UInt64? {
    precondition(!Thread.isMainThread)
    return stored_updatedAtMs
  }
}

final class FixtureNativeCataloguePage: NativeCataloguePage, @unchecked Sendable {
  let stored_activeBoundary: UInt64?
  let stored_activeCursor: NativeEntryKey?
  let stored_completed: UInt64
  let stored_entries: [NativeCatalogueEntry]
  let stored_generation: UInt64
  let stored_next: NativeEntryKey?
  let stored_scope: NativeScope
  init(
    activeBoundary: UInt64? = UInt64.max - 0,
    activeCursor: NativeEntryKey? = FixtureNativeEntryKey(), completed: UInt64 = UInt64.max - 2,
    entries: [NativeCatalogueEntry] = [FixtureNativeCatalogueEntry()],
    generation: UInt64 = UInt64.max - 4, next: NativeEntryKey? = FixtureNativeEntryKey(),
    scope: NativeScope = FixtureNativeScope()
  ) {
    stored_activeBoundary = activeBoundary
    stored_activeCursor = activeCursor
    stored_completed = completed
    stored_entries = entries
    stored_generation = generation
    stored_next = next
    stored_scope = scope
    super.init(noHandle: .init())
  }
  required init(unsafeFromHandle handle: UInt64) { fatalError("fixture cannot be lowered") }
  override func activeBoundary() -> UInt64? {
    precondition(!Thread.isMainThread)
    return stored_activeBoundary
  }
  override func activeCursor() -> NativeEntryKey? {
    precondition(!Thread.isMainThread)
    return stored_activeCursor
  }
  override func completed() -> UInt64 {
    precondition(!Thread.isMainThread)
    return stored_completed
  }
  override func entries() -> [NativeCatalogueEntry] {
    precondition(!Thread.isMainThread)
    return stored_entries
  }
  override func generation() -> UInt64 {
    precondition(!Thread.isMainThread)
    return stored_generation
  }
  override func next() -> NativeEntryKey? {
    precondition(!Thread.isMainThread)
    return stored_next
  }
  override func scope() -> NativeScope {
    precondition(!Thread.isMainThread)
    return stored_scope
  }
}

final class FixtureNativeEnrollmentFailure: NativeEnrollmentFailure, @unchecked Sendable {
  let stored_crypto: NativeCryptoFailure?
  let stored_ioDiagnostic: String?
  let stored_kind: NativeEnrollmentFailureKind
  let stored_storage: NativePrivateStateFailure?
  let stored_wire: NativeWireFailure?
  let stored_worker: NativeWorkerFault?
  init(
    crypto: NativeCryptoFailure? = .pendingStorage,
    ioDiagnostic: String? = "  NativeEnrollmentFailure.ioDiagnostic  ",
    kind: NativeEnrollmentFailureKind = .workerFault,
    storage: NativePrivateStateFailure? = FixtureNativePrivateStateFailure(),
    wire: NativeWireFailure? = FixtureNativeWireFailure(), worker: NativeWorkerFault? = .cancelled
  ) {
    stored_crypto = crypto
    stored_ioDiagnostic = ioDiagnostic
    stored_kind = kind
    stored_storage = storage
    stored_wire = wire
    stored_worker = worker
    super.init(noHandle: .init())
  }
  required init(unsafeFromHandle handle: UInt64) { fatalError("fixture cannot be lowered") }
  override func crypto() -> NativeCryptoFailure? {
    precondition(!Thread.isMainThread)
    return stored_crypto
  }
  override func ioDiagnostic() -> String? {
    precondition(!Thread.isMainThread)
    return stored_ioDiagnostic
  }
  override func kind() -> NativeEnrollmentFailureKind {
    precondition(!Thread.isMainThread)
    return stored_kind
  }
  override func storage() -> NativePrivateStateFailure? {
    precondition(!Thread.isMainThread)
    return stored_storage
  }
  override func wire() -> NativeWireFailure? {
    precondition(!Thread.isMainThread)
    return stored_wire
  }
  override func worker() -> NativeWorkerFault? {
    precondition(!Thread.isMainThread)
    return stored_worker
  }
}

final class FixtureNativeEnrollmentReceipt: NativeEnrollmentReceipt, @unchecked Sendable {
  let stored_accessEpoch: UInt64?
  let stored_attemptFailure: NativeAttemptFailure?
  let stored_attemptState: NativeAttemptState?
  let stored_audience: String?
  let stored_credential: String?
  let stored_organization: String?
  let stored_phase: NativeEnrollmentPhase
  let stored_publicIntent: NativePublicIntent
  let stored_receiver: String?
  let stored_resource: String?
  let stored_terminalCause: NativeTerminalCause?
  init(
    accessEpoch: UInt64? = UInt64.max - 0,
    attemptFailure: NativeAttemptFailure? = .verifierUnavailable,
    attemptState: NativeAttemptState? = .superseded,
    audience: String? = "  NativeEnrollmentReceipt.audience  ",
    credential: String? = "  NativeEnrollmentReceipt.credential  ",
    organization: String? = "  NativeEnrollmentReceipt.organization  ",
    phase: NativeEnrollmentPhase = .terminal,
    publicIntent: NativePublicIntent = FixtureNativePublicIntent(),
    receiver: String? = "  NativeEnrollmentReceipt.receiver  ",
    resource: String? = "  NativeEnrollmentReceipt.resource  ",
    terminalCause: NativeTerminalCause? = .restarted
  ) {
    stored_accessEpoch = accessEpoch
    stored_attemptFailure = attemptFailure
    stored_attemptState = attemptState
    stored_audience = audience
    stored_credential = credential
    stored_organization = organization
    stored_phase = phase
    stored_publicIntent = publicIntent
    stored_receiver = receiver
    stored_resource = resource
    stored_terminalCause = terminalCause
    super.init(noHandle: .init())
  }
  required init(unsafeFromHandle handle: UInt64) { fatalError("fixture cannot be lowered") }
  override func accessEpoch() -> UInt64? {
    precondition(!Thread.isMainThread)
    return stored_accessEpoch
  }
  override func attemptFailure() -> NativeAttemptFailure? {
    precondition(!Thread.isMainThread)
    return stored_attemptFailure
  }
  override func attemptState() -> NativeAttemptState? {
    precondition(!Thread.isMainThread)
    return stored_attemptState
  }
  override func audience() -> String? {
    precondition(!Thread.isMainThread)
    return stored_audience
  }
  override func credential() -> String? {
    precondition(!Thread.isMainThread)
    return stored_credential
  }
  override func organization() -> String? {
    precondition(!Thread.isMainThread)
    return stored_organization
  }
  override func phase() -> NativeEnrollmentPhase {
    precondition(!Thread.isMainThread)
    return stored_phase
  }
  override func publicIntent() -> NativePublicIntent {
    precondition(!Thread.isMainThread)
    return stored_publicIntent
  }
  override func receiver() -> String? {
    precondition(!Thread.isMainThread)
    return stored_receiver
  }
  override func resource() -> String? {
    precondition(!Thread.isMainThread)
    return stored_resource
  }
  override func terminalCause() -> NativeTerminalCause? {
    precondition(!Thread.isMainThread)
    return stored_terminalCause
  }
}

final class FixtureNativeEntryKey: NativeEntryKey, @unchecked Sendable {
  let stored_creation: UInt64
  let stored_id: String
  init(creation: UInt64 = UInt64.max - 0, id: String = "  NativeEntryKey.id  ") {
    stored_creation = creation
    stored_id = id
    super.init(noHandle: .init())
  }
  required init(unsafeFromHandle handle: UInt64) { fatalError("fixture cannot be lowered") }
  override func creation() -> UInt64 {
    precondition(!Thread.isMainThread)
    return stored_creation
  }
  override func id() -> String {
    precondition(!Thread.isMainThread)
    return stored_id
  }
}

final class FixtureNativePrivateStateFailure: NativePrivateStateFailure, @unchecked Sendable {
  let stored_keyPublication: NativeKeyPublication?
  let stored_kind: NativePrivateStateKind
  let stored_publication: NativePublicationFailure?
  init(
    keyPublication: NativeKeyPublication? = .published, kind: NativePrivateStateKind = .uncertain,
    publication: NativePublicationFailure? = FixtureNativePublicationFailure()
  ) {
    stored_keyPublication = keyPublication
    stored_kind = kind
    stored_publication = publication
    super.init(noHandle: .init())
  }
  required init(unsafeFromHandle handle: UInt64) { fatalError("fixture cannot be lowered") }
  override func keyPublication() -> NativeKeyPublication? {
    precondition(!Thread.isMainThread)
    return stored_keyPublication
  }
  override func kind() -> NativePrivateStateKind {
    precondition(!Thread.isMainThread)
    return stored_kind
  }
  override func publication() -> NativePublicationFailure? {
    precondition(!Thread.isMainThread)
    return stored_publication
  }
}

final class FixtureNativePublicIntent: NativePublicIntent, @unchecked Sendable {
  let stored_attempt: Data
  let stored_consent: Data
  let stored_consentClass: NativeConsentClass
  let stored_expiryMs: UInt64
  let stored_generation: UInt64
  let stored_invitation: Data
  init(
    attempt: Data = Data(repeating: 1, count: 16), consent: Data = Data(repeating: 2, count: 16),
    consentClass: NativeConsentClass = .peerEnvironment, expiryMs: UInt64 = UInt64.max - 3,
    generation: UInt64 = UInt64.max - 4, invitation: Data = Data(repeating: 6, count: 16)
  ) {
    stored_attempt = attempt
    stored_consent = consent
    stored_consentClass = consentClass
    stored_expiryMs = expiryMs
    stored_generation = generation
    stored_invitation = invitation
    super.init(noHandle: .init())
  }
  required init(unsafeFromHandle handle: UInt64) { fatalError("fixture cannot be lowered") }
  override func attempt() -> Data {
    precondition(!Thread.isMainThread)
    return stored_attempt
  }
  override func consent() -> Data {
    precondition(!Thread.isMainThread)
    return stored_consent
  }
  override func consentClass() -> NativeConsentClass {
    precondition(!Thread.isMainThread)
    return stored_consentClass
  }
  override func expiryMs() -> UInt64 {
    precondition(!Thread.isMainThread)
    return stored_expiryMs
  }
  override func generation() -> UInt64 {
    precondition(!Thread.isMainThread)
    return stored_generation
  }
  override func invitation() -> Data {
    precondition(!Thread.isMainThread)
    return stored_invitation
  }
}

final class FixtureNativePublicationFailure: NativePublicationFailure, @unchecked Sendable {
  let stored_cleanup: NativeStorageFailure?
  let stored_effect: NativePublicationEffect
  let stored_primary: NativeStorageFailure
  let stored_reconciliation: NativeStorageFailure?
  let stored_step: NativePublicationStep
  init(
    cleanup: NativeStorageFailure? = .unavailable, effect: NativePublicationEffect = .published,
    primary: NativeStorageFailure = .unavailable,
    reconciliation: NativeStorageFailure? = .unavailable,
    step: NativePublicationStep = .syncDirectory
  ) {
    stored_cleanup = cleanup
    stored_effect = effect
    stored_primary = primary
    stored_reconciliation = reconciliation
    stored_step = step
    super.init(noHandle: .init())
  }
  required init(unsafeFromHandle handle: UInt64) { fatalError("fixture cannot be lowered") }
  override func cleanup() -> NativeStorageFailure? {
    precondition(!Thread.isMainThread)
    return stored_cleanup
  }
  override func effect() -> NativePublicationEffect {
    precondition(!Thread.isMainThread)
    return stored_effect
  }
  override func primary() -> NativeStorageFailure {
    precondition(!Thread.isMainThread)
    return stored_primary
  }
  override func reconciliation() -> NativeStorageFailure? {
    precondition(!Thread.isMainThread)
    return stored_reconciliation
  }
  override func step() -> NativePublicationStep {
    precondition(!Thread.isMainThread)
    return stored_step
  }
}

final class FixtureNativePurge: NativePurge, @unchecked Sendable {
  let stored_catalogueEntries: UInt64
  let stored_observedAtMs: UInt64
  let stored_receiver: String
  let stored_records: UInt64
  let stored_transcripts: UInt64
  init(
    catalogueEntries: UInt64 = UInt64.max - 0, observedAtMs: UInt64 = UInt64.max - 1,
    receiver: String = "  NativePurge.receiver  ", records: UInt64 = UInt64.max - 3,
    transcripts: UInt64 = UInt64.max - 4
  ) {
    stored_catalogueEntries = catalogueEntries
    stored_observedAtMs = observedAtMs
    stored_receiver = receiver
    stored_records = records
    stored_transcripts = transcripts
    super.init(noHandle: .init())
  }
  required init(unsafeFromHandle handle: UInt64) { fatalError("fixture cannot be lowered") }
  override func catalogueEntries() -> UInt64 {
    precondition(!Thread.isMainThread)
    return stored_catalogueEntries
  }
  override func observedAtMs() -> UInt64 {
    precondition(!Thread.isMainThread)
    return stored_observedAtMs
  }
  override func receiver() -> String {
    precondition(!Thread.isMainThread)
    return stored_receiver
  }
  override func records() -> UInt64 {
    precondition(!Thread.isMainThread)
    return stored_records
  }
  override func transcripts() -> UInt64 {
    precondition(!Thread.isMainThread)
    return stored_transcripts
  }
}

final class FixtureNativeRead: NativeRead, @unchecked Sendable {
  let stored_complete: Bool?
  let stored_conversations: UInt64?
  let stored_failure: NativeReadFailure?
  let stored_moved: Bool?
  let stored_withdrawn: [String]
  init(
    complete: Bool? = true, conversations: UInt64? = UInt64.max - 1,
    failure: NativeReadFailure? = .stopped, moved: Bool? = true,
    withdrawn: [String] = [" withdrawn-a ", "withdrawn-b"]
  ) {
    stored_complete = complete
    stored_conversations = conversations
    stored_failure = failure
    stored_moved = moved
    stored_withdrawn = withdrawn
    super.init(noHandle: .init())
  }
  required init(unsafeFromHandle handle: UInt64) { fatalError("fixture cannot be lowered") }
  override func complete() -> Bool? {
    precondition(!Thread.isMainThread)
    return stored_complete
  }
  override func conversations() -> UInt64? {
    precondition(!Thread.isMainThread)
    return stored_conversations
  }
  override func failure() -> NativeReadFailure? {
    precondition(!Thread.isMainThread)
    return stored_failure
  }
  override func moved() -> Bool? {
    precondition(!Thread.isMainThread)
    return stored_moved
  }
  override func withdrawn() -> [String] {
    precondition(!Thread.isMainThread)
    return stored_withdrawn
  }
}

final class FixtureNativeRefresh: NativeRefresh, @unchecked Sendable {
  let stored_initial: NativeStatus
  let stored_read: NativeRead?
  let stored_recheck: NativeStatus?
  let stored_selectionFailure: NativeEnrollmentFailure?
  init(
    initial: NativeStatus = FixtureNativeStatus(), read: NativeRead? = FixtureNativeRead(),
    recheck: NativeStatus? = FixtureNativeStatus(),
    selectionFailure: NativeEnrollmentFailure? = FixtureNativeEnrollmentFailure()
  ) {
    stored_initial = initial
    stored_read = read
    stored_recheck = recheck
    stored_selectionFailure = selectionFailure
    super.init(noHandle: .init())
  }
  required init(unsafeFromHandle handle: UInt64) { fatalError("fixture cannot be lowered") }
  override func initial() -> NativeStatus {
    precondition(!Thread.isMainThread)
    return stored_initial
  }
  override func read() -> NativeRead? {
    precondition(!Thread.isMainThread)
    return stored_read
  }
  override func recheck() -> NativeStatus? {
    precondition(!Thread.isMainThread)
    return stored_recheck
  }
  override func selectionFailure() -> NativeEnrollmentFailure? {
    precondition(!Thread.isMainThread)
    return stored_selectionFailure
  }
}

final class FixtureNativeRetry: NativeRetry, @unchecked Sendable {
  let stored_original: NativeEnrollmentReceipt
  let stored_retried: NativeEnrollmentReceipt
  init(
    original: NativeEnrollmentReceipt = FixtureNativeEnrollmentReceipt(),
    retried: NativeEnrollmentReceipt = FixtureNativeEnrollmentReceipt()
  ) {
    stored_original = original
    stored_retried = retried
    super.init(noHandle: .init())
  }
  required init(unsafeFromHandle handle: UInt64) { fatalError("fixture cannot be lowered") }
  override func original() -> NativeEnrollmentReceipt {
    precondition(!Thread.isMainThread)
    return stored_original
  }
  override func retried() -> NativeEnrollmentReceipt {
    precondition(!Thread.isMainThread)
    return stored_retried
  }
}

final class FixtureNativeScope: NativeScope, @unchecked Sendable {
  let stored_accessEpoch: String
  let stored_incarnation: String
  let stored_origin: String
  let stored_receiver: String
  let stored_schema: String
  let stored_stream: String
  init(
    accessEpoch: String = "  NativeScope.accessEpoch  ",
    incarnation: String = "  NativeScope.incarnation  ", origin: String = "  NativeScope.origin  ",
    receiver: String = "  NativeScope.receiver  ", schema: String = "  NativeScope.schema  ",
    stream: String = "  NativeScope.stream  "
  ) {
    stored_accessEpoch = accessEpoch
    stored_incarnation = incarnation
    stored_origin = origin
    stored_receiver = receiver
    stored_schema = schema
    stored_stream = stream
    super.init(noHandle: .init())
  }
  required init(unsafeFromHandle handle: UInt64) { fatalError("fixture cannot be lowered") }
  override func accessEpoch() -> String {
    precondition(!Thread.isMainThread)
    return stored_accessEpoch
  }
  override func incarnation() -> String {
    precondition(!Thread.isMainThread)
    return stored_incarnation
  }
  override func origin() -> String {
    precondition(!Thread.isMainThread)
    return stored_origin
  }
  override func receiver() -> String {
    precondition(!Thread.isMainThread)
    return stored_receiver
  }
  override func schema() -> String {
    precondition(!Thread.isMainThread)
    return stored_schema
  }
  override func stream() -> String {
    precondition(!Thread.isMainThread)
    return stored_stream
  }
}

final class FixtureNativeSessionFailure: NativeSessionFailure, @unchecked Sendable {
  let stored_cache: NativeReadFailure?
  let stored_enrollment: NativeEnrollmentFailure?
  let stored_kind: NativeSessionFailureKind
  let stored_privateState: NativePrivateStateFailure?
  let stored_runtimeDiagnostic: String?
  init(
    cache: NativeReadFailure? = .stopped,
    enrollment: NativeEnrollmentFailure? = FixtureNativeEnrollmentFailure(),
    kind: NativeSessionFailureKind = .stopped,
    privateState: NativePrivateStateFailure? = FixtureNativePrivateStateFailure(),
    runtimeDiagnostic: String? = "  NativeSessionFailure.runtimeDiagnostic  "
  ) {
    stored_cache = cache
    stored_enrollment = enrollment
    stored_kind = kind
    stored_privateState = privateState
    stored_runtimeDiagnostic = runtimeDiagnostic
    super.init(noHandle: .init())
  }
  required init(unsafeFromHandle handle: UInt64) { fatalError("fixture cannot be lowered") }
  override func cache() -> NativeReadFailure? {
    precondition(!Thread.isMainThread)
    return stored_cache
  }
  override func enrollment() -> NativeEnrollmentFailure? {
    precondition(!Thread.isMainThread)
    return stored_enrollment
  }
  override func kind() -> NativeSessionFailureKind {
    precondition(!Thread.isMainThread)
    return stored_kind
  }
  override func privateState() -> NativePrivateStateFailure? {
    precondition(!Thread.isMainThread)
    return stored_privateState
  }
  override func runtimeDiagnostic() -> String? {
    precondition(!Thread.isMainThread)
    return stored_runtimeDiagnostic
  }
}

final class FixtureNativeStatus: NativeStatus, @unchecked Sendable {
  let stored_completionCaptured: Bool
  let stored_failure: NativeEnrollmentFailure?
  let stored_purge: NativePurge?
  let stored_purgeAttempted: Bool
  let stored_purgeFailure: NativeReadFailure?
  let stored_receipt: NativeEnrollmentReceipt?
  init(
    completionCaptured: Bool = true,
    failure: NativeEnrollmentFailure? = FixtureNativeEnrollmentFailure(),
    purge: NativePurge? = FixtureNativePurge(), purgeAttempted: Bool = true,
    purgeFailure: NativeReadFailure? = .stopped,
    receipt: NativeEnrollmentReceipt? = FixtureNativeEnrollmentReceipt()
  ) {
    stored_completionCaptured = completionCaptured
    stored_failure = failure
    stored_purge = purge
    stored_purgeAttempted = purgeAttempted
    stored_purgeFailure = purgeFailure
    stored_receipt = receipt
    super.init(noHandle: .init())
  }
  required init(unsafeFromHandle handle: UInt64) { fatalError("fixture cannot be lowered") }
  override func completionCaptured() -> Bool {
    precondition(!Thread.isMainThread)
    return stored_completionCaptured
  }
  override func failure() -> NativeEnrollmentFailure? {
    precondition(!Thread.isMainThread)
    return stored_failure
  }
  override func purge() -> NativePurge? {
    precondition(!Thread.isMainThread)
    return stored_purge
  }
  override func purgeAttempted() -> Bool {
    precondition(!Thread.isMainThread)
    return stored_purgeAttempted
  }
  override func purgeFailure() -> NativeReadFailure? {
    precondition(!Thread.isMainThread)
    return stored_purgeFailure
  }
  override func receipt() -> NativeEnrollmentReceipt? {
    precondition(!Thread.isMainThread)
    return stored_receipt
  }
}

final class FixtureNativeTranscript: NativeTranscript, @unchecked Sendable {
  let stored_applied: UInt64?
  let stored_downloaded: UInt64?
  let stored_facts: UInt64?
  let stored_generation: UInt64?
  let stored_scope: NativeScope?
  let stored_state: NativeTranscriptState
  let json: Result<String?, NativeViewError>
  init(
    applied: UInt64? = UInt64.max - 0, downloaded: UInt64? = UInt64.max - 1,
    facts: UInt64? = UInt64.max - 2, generation: UInt64? = UInt64.max - 3,
    scope: NativeScope? = FixtureNativeScope(), state: NativeTranscriptState = .retained,
    json: Result<String?, NativeViewError> = .success(nil)
  ) {
    stored_applied = applied
    stored_downloaded = downloaded
    stored_facts = facts
    stored_generation = generation
    stored_scope = scope
    stored_state = state
    self.json = json
    super.init(noHandle: .init())
  }
  required init(unsafeFromHandle handle: UInt64) { fatalError("fixture cannot be lowered") }
  override func applied() -> UInt64? {
    precondition(!Thread.isMainThread)
    return stored_applied
  }
  override func downloaded() -> UInt64? {
    precondition(!Thread.isMainThread)
    return stored_downloaded
  }
  override func facts() -> UInt64? {
    precondition(!Thread.isMainThread)
    return stored_facts
  }
  override func generation() -> UInt64? {
    precondition(!Thread.isMainThread)
    return stored_generation
  }
  override func scope() -> NativeScope? {
    precondition(!Thread.isMainThread)
    return stored_scope
  }
  override func state() -> NativeTranscriptState {
    precondition(!Thread.isMainThread)
    return stored_state
  }
  override func viewJson() throws -> String? {
    precondition(!Thread.isMainThread)
    return try json.get()
  }
}

final class FixtureNativeWireFailure: NativeWireFailure, @unchecked Sendable {
  let stored_correlation: NativePairingFailure?
  let stored_kind: NativeWireFailureKind
  init(
    correlation: NativePairingFailure? = .staleGeneration,
    kind: NativeWireFailureKind = .correlation
  ) {
    stored_correlation = correlation
    stored_kind = kind
    super.init(noHandle: .init())
  }
  required init(unsafeFromHandle handle: UInt64) { fatalError("fixture cannot be lowered") }
  override func correlation() -> NativePairingFailure? {
    precondition(!Thread.isMainThread)
    return stored_correlation
  }
  override func kind() -> NativeWireFailureKind {
    precondition(!Thread.isMainThread)
    return stored_kind
  }
}
