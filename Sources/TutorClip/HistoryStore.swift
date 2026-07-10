import Foundation
import SQLite3

@MainActor
final class HistoryStore: ObservableObject {
    @Published private(set) var sessions: [TutorSession] = []

    private let worker: HistoryDatabaseWorker

    init(baseDirectory: URL? = nil) {
        worker = HistoryDatabaseWorker(baseDirectory: baseDirectory)
    }

    func open() {
        worker.open { [weak self] sessions in
            Task { @MainActor in
                self?.sessions = sessions
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

private struct HistorySavePayload {
    var id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date
    var category: SessionCategory
    var studyStatus: StudyStatus
    var selectedAnswer: String?
    var correctAnswer: String?
    var vocabularyJSON: String
    var ocrJSON: String
    var messagesJSON: String

    init?(session: TutorSession) {
        guard let ocrData = try? JSONEncoder.tutorClip.encode(session.ocrDocument),
              let messagesData = try? JSONEncoder.tutorClip.encode(session.messages),
              let vocabularyData = try? JSONEncoder.tutorClip.encode(session.vocabularyCards),
              let ocrJSON = String(data: ocrData, encoding: .utf8),
              let messagesJSON = String(data: messagesData, encoding: .utf8),
              let vocabularyJSON = String(data: vocabularyData, encoding: .utf8) else {
            return nil
        }
        id = session.id
        title = session.title
        createdAt = session.createdAt
        updatedAt = session.updatedAt
        category = session.category
        studyStatus = session.studyStatus
        selectedAnswer = session.selectedAnswer
        correctAnswer = session.correctAnswer
        self.vocabularyJSON = vocabularyJSON
        self.ocrJSON = ocrJSON
        self.messagesJSON = messagesJSON
    }
}

private struct HistorySaveResult {
    var success: Bool
    var sessions: [TutorSession]
}

private struct HistoryMutationResult {
    var success: Bool
    var sessions: [TutorSession]
}

private final class HistoryDatabaseWorker {
    private let queue = DispatchQueue(label: "TutorClip.HistoryDatabase")
    private var db: OpaquePointer?
    private let dbURL: URL

    init(baseDirectory: URL? = nil) {
        let base = baseDirectory ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".tutorclip", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        dbURL = base.appendingPathComponent("history.sqlite")
    }

    func open(completion: @escaping ([TutorSession]) -> Void) {
        queue.async { [weak self] in
            guard let self else { return }
            guard sqlite3_open(self.dbURL.path, &self.db) == SQLITE_OK else {
                RuntimeLog.write("history-open-failed \(self.databaseErrorMessage())")
                completion([])
                return
            }
            guard self.createSchemaIfNeeded(), self.migrateSchema() else {
                RuntimeLog.write("history-schema-setup-failed \(self.databaseErrorMessage())")
                sqlite3_close(self.db)
                self.db = nil
                completion([])
                return
            }
            completion(self.loadSessions())
        }
    }

    func close() {
        queue.async { [weak self] in
            guard let self else { return }
            sqlite3_close(self.db)
            self.db = nil
        }
    }

    func save(payload: HistorySavePayload, completion: @escaping (HistorySaveResult) -> Void) {
        queue.async { [weak self] in
            guard let self else { return }
            let success = self.insertOrReplace(payload)
            completion(HistorySaveResult(success: success, sessions: self.loadSessions()))
        }
    }

    func delete(sessionID: UUID, completion: @escaping (HistoryMutationResult) -> Void) {
        queue.async { [weak self] in
            guard let self else { return }
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(self.db, "DELETE FROM sessions WHERE id = ?;", -1, &statement, nil) == SQLITE_OK else {
                RuntimeLog.write("history-delete-prepare-failed \(self.databaseErrorMessage())")
                completion(HistoryMutationResult(success: false, sessions: self.loadSessions()))
                return
            }
            defer { sqlite3_finalize(statement) }
            sqlite3_bind_text(statement, 1, sessionID.uuidString, -1, SQLITE_TRANSIENT)
            let success = sqlite3_step(statement) == SQLITE_DONE
            if !success {
                RuntimeLog.write("history-delete-failed \(self.databaseErrorMessage())")
            }
            completion(HistoryMutationResult(success: success, sessions: self.loadSessions()))
        }
    }

    func clear(completion: @escaping (HistoryMutationResult) -> Void) {
        queue.async { [weak self] in
            guard let self else { return }
            let success = self.execute("DELETE FROM sessions;")
            completion(HistoryMutationResult(success: success, sessions: self.loadSessions()))
        }
    }

    private func createSchemaIfNeeded() -> Bool {
        execute("""
        CREATE TABLE IF NOT EXISTS sessions (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL,
            category TEXT NOT NULL,
            study_status TEXT NOT NULL DEFAULT 'unreviewed',
            selected_answer TEXT,
            correct_answer TEXT,
            vocabulary_json TEXT NOT NULL DEFAULT '[]',
            ocr_json TEXT NOT NULL,
            messages_json TEXT NOT NULL
        );
        """)
    }

    private func insertOrReplace(_ payload: HistorySavePayload) -> Bool {
        let sql = """
        INSERT OR REPLACE INTO sessions
        (id, title, created_at, updated_at, category, study_status, selected_answer, correct_answer, vocabulary_json, ocr_json, messages_json)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return false }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, payload.id.uuidString, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 2, payload.title, -1, SQLITE_TRANSIENT)
        sqlite3_bind_double(statement, 3, payload.createdAt.timeIntervalSince1970)
        sqlite3_bind_double(statement, 4, payload.updatedAt.timeIntervalSince1970)
        sqlite3_bind_text(statement, 5, payload.category.rawValue, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 6, payload.studyStatus.rawValue, -1, SQLITE_TRANSIENT)
        bindOptionalText(statement, index: 7, value: payload.selectedAnswer)
        bindOptionalText(statement, index: 8, value: payload.correctAnswer)
        sqlite3_bind_text(statement, 9, payload.vocabularyJSON, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 10, payload.ocrJSON, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 11, payload.messagesJSON, -1, SQLITE_TRANSIENT)
        return sqlite3_step(statement) == SQLITE_DONE
    }

    private func loadSessions() -> [TutorSession] {
        var loaded: [TutorSession] = []
        var statement: OpaquePointer?
        let sql = """
        SELECT id, title, created_at, updated_at, category, study_status, selected_answer, correct_answer, vocabulary_json, ocr_json, messages_json
        FROM sessions ORDER BY updated_at DESC;
        """
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return loaded }
        defer { sqlite3_finalize(statement) }

        while sqlite3_step(statement) == SQLITE_ROW {
            guard let session = decodeSession(from: statement) else { continue }
            loaded.append(session)
        }
        return loaded
    }

    private func decodeSession(from statement: OpaquePointer?) -> TutorSession? {
        guard let idString = columnText(statement, 0),
              let id = UUID(uuidString: idString),
              let title = columnText(statement, 1),
              let categoryRaw = columnText(statement, 4),
              let studyStatusRaw = columnText(statement, 5),
              let vocabularyJSON = columnText(statement, 8),
              let ocrJSON = columnText(statement, 9),
              let messagesJSON = columnText(statement, 10),
              let vocabularyData = vocabularyJSON.data(using: .utf8),
              let ocrData = ocrJSON.data(using: .utf8),
              let messagesData = messagesJSON.data(using: .utf8),
              let vocabularyCards = try? JSONDecoder.tutorClip.decode([VocabularyCard].self, from: vocabularyData),
              let ocr = try? JSONDecoder.tutorClip.decode(OCRDocument.self, from: ocrData),
              let messages = try? JSONDecoder.tutorClip.decode([ChatMessage].self, from: messagesData) else {
            return nil
        }
        let created = Date(timeIntervalSince1970: sqlite3_column_double(statement, 2))
        let updated = Date(timeIntervalSince1970: sqlite3_column_double(statement, 3))
        return TutorSession(
            id: id,
            title: title,
            createdAt: created,
            updatedAt: updated,
            ocrDocument: ocr,
            messages: messages,
            screenshotInMemory: nil,
            category: SessionCategory(rawValue: categoryRaw) ?? .unknown,
            studyStatus: StudyStatus(rawValue: studyStatusRaw) ?? .unreviewed,
            selectedAnswer: columnText(statement, 6),
            correctAnswer: columnText(statement, 7),
            vocabularyCards: vocabularyCards
        )
    }

    private func migrateSchema() -> Bool {
        guard let existingColumns = sessionColumnNames() else { return false }
        let migrations = [
            ("study_status", "ALTER TABLE sessions ADD COLUMN study_status TEXT NOT NULL DEFAULT 'unreviewed';"),
            ("selected_answer", "ALTER TABLE sessions ADD COLUMN selected_answer TEXT;"),
            ("correct_answer", "ALTER TABLE sessions ADD COLUMN correct_answer TEXT;"),
            ("vocabulary_json", "ALTER TABLE sessions ADD COLUMN vocabulary_json TEXT NOT NULL DEFAULT '[]';")
        ]
        for (column, sql) in migrations where !existingColumns.contains(column) {
            guard execute(sql) else { return false }
            RuntimeLog.write("history-schema-added-column \(column)")
        }
        return true
    }

    private func sessionColumnNames() -> Set<String>? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "PRAGMA table_info(sessions);", -1, &statement, nil) == SQLITE_OK else {
            return nil
        }
        defer { sqlite3_finalize(statement) }
        var columns: Set<String> = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let name = columnText(statement, 1) else { continue }
            columns.insert(name)
        }
        return columns
    }

    @discardableResult
    private func execute(_ sql: String) -> Bool {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            RuntimeLog.write("history-sql-failed \(databaseErrorMessage())")
            return false
        }
        return true
    }

    private func databaseErrorMessage() -> String {
        guard let db, let message = sqlite3_errmsg(db) else { return "unknown" }
        return String(cString: message)
    }

    private func columnText(_ statement: OpaquePointer?, _ index: Int32) -> String? {
        guard let pointer = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: pointer)
    }

    private func bindOptionalText(_ statement: OpaquePointer?, index: Int32, value: String?) {
        guard let value else {
            sqlite3_bind_null(statement, index)
            return
        }
        sqlite3_bind_text(statement, index, value, -1, SQLITE_TRANSIENT)
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
