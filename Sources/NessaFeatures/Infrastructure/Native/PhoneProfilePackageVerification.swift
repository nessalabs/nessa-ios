#if DEBUG
  import Foundation

  /// Uses only the explicitly requested disposable probe root and its own profile Keychain item.
  enum PhoneProfilePackageVerification {
    enum Failure: Error { case missingSelectedProfile, credentialChanged, wrongPhase, localRecord }
    static func run(root: String) async throws {
      let directory = URL(fileURLWithPath: root).appendingPathComponent(
        "ProfileProbe", isDirectory: true)
      let profiles = PhoneProfileStore(
        root: directory.appendingPathComponent("Metadata", isDirectory: true))
      let saved = try await profiles.load()
      let profile: PhoneProfile
      if let saved {
        guard let selected = saved.profiles.first(where: { $0.id == saved.selected }) else {
          throw Failure.missingSelectedProfile
        }
        profile = selected
      } else {
        profile = PhoneProfile(
          id: UUID(), productAddress: "ws://127.0.0.1:9/session", instance: "disposable-probe",
          nativeAddress: "127.0.0.1:9",
          identity: .init(
            gatewayID: "fixture", principalID: "fixture", organizationID: "fixture",
            membershipID: "fixture", credentialID: "fixture", audienceID: "fixture"))
      }
      let credentials = PhoneProfileCredentials()
      let ready = try await PhoneProfilePreparation(profiles: profiles, credentials: credentials)
        .prepare(profile, credential: "disposable-profile-probe", replacing: saved)
      guard ready.profiles.first(where: { $0.id == profile.id })?.phase == .prepared else {
        throw Failure.wrongPhase
      }
      guard
        try await credentials.load(reference: profile.credentialReference)
          == "disposable-profile-probe"
      else {
        throw Failure.credentialChanged
      }
      let location = try await PhoneNativeLocations(root: directory).prepare(profile)
      let native = try await NativeRetainedSessionFactory().open(location)
      do {
        guard try await native.localEnrollment() == nil else { throw Failure.localRecord }
        try await native.close()
      } catch {
        try? await native.close()
        throw error
      }
      print("NESSA_NATIVE_PROFILE_PASS preparation/keychain/relative-root/reopen")
    }
  }
#endif
