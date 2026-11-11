#if os(iOS)
import Foundation

extension ExactPhoneSession {
  /// Detail-only data stays out of the live transcript projection and its streaming updates.
  func agentDetails(for chat: String) -> [String: Any] {
    let view = messages.views[chat]
    let agent = view?.runtime?.agent ?? messages.agentID(for: chat)
    let profile = messages.agentProfiles.first { $0.id == agent }
    let model = profile?.defaultModel.map { id in profile?.models.first { $0.id == id }?.displayName ?? id }
    let access = (profile?.grantedAccess ?? []).enumerated().map { index, label in
      ["index": index, "label": label] as [String: Any]
    }
    let artifacts = ConversationArtifact.collect(from: view?.messages ?? []).map { artifact -> [String: Any] in
      switch artifact.content {
      case .image: return ["id": artifact.id, "image": true, "name": "", "mime": ""]
      case .file(let file): return ["id": artifact.id, "image": false, "name": file.name, "mime": file.mimeType]
      }
    }
    var activity: [[String: Any]] = (view?.permissions ?? []).map {
      ["id": "review:" + $0.review, "title": $0.title, "status": AgentActivityState.requested.label,
       "detail": "", "failed": false]
    }
    for turn in (view?.messages ?? []).reversed() {
      let state = AgentActivityState(status: turn.status, failed: turn.error != nil)
      activity.append(["id": "turn:" + turn.id, "title": turn.userText.isEmpty ? "Conversation turn" : turn.userText,
        "status": state.label, "detail": turn.error ?? turn.bubbles.last ?? "", "failed": state == .failed])
    }
    let prompt = profile?.prompt ?? ""
    return ["chat": chat, "name": messages.agentName(for: chat), "description": profile?.description ?? "",
      "model": model ?? "", "working": view?.messages.contains { $0.status == "running" } == true,
      "prompt": prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : prompt,
      "accessReported": profile?.grantedAccess != nil, "access": access, "recent": view?.truncated ?? false,
      "loaded": view != nil, "error": view?.interactionViewError ?? "", "artifacts": artifacts, "activity": activity]
  }
}
#endif
