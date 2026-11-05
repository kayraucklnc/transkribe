import Foundation
import TranskribeCore

extension AppModel {
    func receiveIntentSegments(id: UUID, track: String, committed: [Segment], startedAt: Date, committedAt: Date) {
        guard copilotSettings.intents, let ai = intentAI else { return }
        if liveIntents?.meetingID != id {
            liveIntents?.pause()
            liveIntents = LiveIntentController(meetingID: id, startedAt: startedAt, model: self, ai: ai)
        }
        liveIntents?.receive(track: track, committed: committed, at: committedAt)
    }

    func finishLiveIntents(id: UUID) {
        guard let controller = liveIntents, controller.meetingID == id else { return }
        Task { await controller.finish() }
    }
}
