import Foundation
import SQLite3

@MainActor
final class HistoryStore: ObservableObject {
    @Published private(set) var sessions: [TutorSession] = []
    @Published private(set) var manuallyMasteredKnowledgePointIDs: Set<String> = []

    private let worker: HistoryDatabaseWorker

    init(baseDirectory: URL? = nil) {
        worker = HistoryDatabaseWorker(baseDirectory: baseDirectory)
    }

    func open() {
        worker.open { [weak self] sessions, masteredIDs in
            Task { @MainActor in
                self?.sessions = sessions
                self?.manuallyMasteredKnowledgePointIDs = masteredIDs
            }
        }
    }

    func close() {
        worker.close()
    }

    func save(session: TutorSession, enabled: Bool, completion: ((Bool) -> Void)? = nil) {
        guard enabled else {
            completion?(true)
            return
        }
        guard let payload = HistorySavePayload(session: session) else {
            completion?(false)
            return
        }
        worker.save(payload: payload) { [weak self] result in
            Task { @MainActor in
                self?.sessions = result.sessions
                completion?(result.success)
            }
        }
    }

    func delete(sessionID: UUID, completion: ((Bool) -> Void)? = nil) {
        worker.delete(sessionID: sessionID) { [weak self] result in
            Task { @MainActor in
                self?.sessions = result.sessions
                completion?(result.success)
            }
        }
    }

    func clear(completion: ((Bool) -> Void)? = nil) {
        worker.clear { [weak self] result in
            Task { @MainActor in
                self?.sessions = result.sessions
                completion?(result.success)
            }
        }
    }

    func setKnowledgePoint(_ id: String, mastered: Bool, completion: ((Bool) -> Void)? = nil) {
        guard SATKnowledgeCatalog.knowledgePoint(id: id) != nil else { completion?(false); return }
        worker.setKnowledgePoint(id, mastered: mastered) { [weak self] success, ids in
            Task { @MainActor in
                self?.manuallyMasteredKnowledgePointIDs = ids
                completion?(success)
            }
        }
    }

    func search(_ query: String) -> [TutorSession] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return sessions }
        return sessions.filter {
            $0.title.localizedCaseInsensitiveContains(trimmed)
            || $0.ocrDocument.editedText.localizedCaseInsensitiveContains(trimmed)
            || $0.messages.contains { $0.content.localizedCaseInsensitiveContains(trimmed) }
        }
    }
}

