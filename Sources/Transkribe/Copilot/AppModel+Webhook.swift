import Foundation
import TranskribeCore

extension AppModel {
    func sendWebhook(_ type: WebhookEvent.EventType, for transcript: Transcript,
                     intent: WebhookEvent.Intent? = nil) {
        guard let endpoint = copilotSettings.webhook else { return }
        let event = WebhookEvent(type: type, conversationId: transcript.id, title: transcript.title,
            startedAt: transcript.createdAt, intent: intent)
        Task.detached(priority: .utility) {
            _ = await WebhookClient().send(event, to: endpoint)
        }
    }
}
