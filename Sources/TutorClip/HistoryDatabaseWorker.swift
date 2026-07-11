import Foundation
import SQLite3
struct HistorySavePayload {
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
    var learningJSON: String

    init?(session: TutorSession) {
        guard let ocrData = try? JSONEncoder.tutorClip.encode(session.ocrDocument),
              let messagesData = try? JSONEncoder.tutorClip.encode(session.messages),
              let vocabularyData = try? JSONEncoder.tutorClip.encode(session.vocabularyCards),
              let learningData = try? JSONEncoder.tutorClip.encode(session.learningMetadata),
              let ocrJSON = String(data: ocrData, encoding: .utf8),
              let messagesJSON = String(data: messagesData, encoding: .utf8),
              let vocabularyJSON = String(data: vocabularyData, encoding: .utf8),
              let learningJSON = String(data: learningData, encoding: .utf8) else {
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
        self.learningJSON = learningJSON
    }
}

struct HistorySaveResult {
    var success: Bool
    var sessions: [TutorSession]
}

struct HistoryMutationResult {
    var success: Bool
    var sessions: [TutorSession]
}

final class HistoryDatabaseWorker {
    private let queue = DispatchQueue(label: "TutorClip.HistoryDatabase")
    private var db: OpaquePointer?
    private let dbURL: URL

    init(baseDirectory: URL? = nil) {
        let base = baseDirectory ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".tutorclip", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        dbURL = base.appendingPathComponent("history.sqlite")
    }

    func open(completion: @escaping ([TutorSession], Set<String>) -> Void) {
        queue.async { [weak self] in
            guard let self else { return }
            guard sqlite3_open(self.dbURL.path, &self.db) == SQLITE_OK else {
                RuntimeLog.write("history-open-failed \(self.databaseErrorMessage())")
                completion([], [])
                return
            }
            guard self.createSchemaIfNeeded(), self.migrateSchema(), self.seedSATKnowledgeCatalog() else {
                RuntimeLog.write("history-schema-setup-failed \(self.databaseErrorMessage())")
                sqlite3_close(self.db)
                self.db = nil
                completion([], [])
                return
            }
            completion(self.loadSessions(), self.loadManuallyMasteredKnowledgePoints())
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

    func setKnowledgePoint(_ id: String, mastered: Bool, completion: @escaping (Bool, Set<String>) -> Void) {
        queue.async { [weak self] in
            guard let self else { return }
            let sql = mastered
                ? "INSERT OR REPLACE INTO sat_knowledge_mastery (knowledge_point_id, manually_mastered, updated_at) VALUES (?, 1, ?);"
                : "DELETE FROM sat_knowledge_mastery WHERE knowledge_point_id = ?;"
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(self.db, sql, -1, &statement, nil) == SQLITE_OK else {
                completion(false, self.loadManuallyMasteredKnowledgePoints()); return
            }
            defer { sqlite3_finalize(statement) }
            sqlite3_bind_text(statement, 1, id, -1, SQLITE_TRANSIENT)
            if mastered { sqlite3_bind_double(statement, 2, Date().timeIntervalSince1970) }
            completion(sqlite3_step(statement) == SQLITE_DONE, self.loadManuallyMasteredKnowledgePoints())
        }
    }

    private func createSchemaIfNeeded() -> Bool {
        guard execute("""
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
            ,learning_json TEXT NOT NULL DEFAULT '{}'
        );
        """) else { return false }
        return execute("""
        CREATE TABLE IF NOT EXISTS sat_question_types (
            id TEXT PRIMARY KEY, domain TEXT NOT NULL, skill TEXT NOT NULL,
            title_zh TEXT NOT NULL, title_en TEXT NOT NULL, catalog_version INTEGER NOT NULL
        );
        CREATE TABLE IF NOT EXISTS sat_knowledge_points (
            id TEXT PRIMARY KEY, question_type_id TEXT NOT NULL,
            title_zh TEXT NOT NULL, title_en TEXT NOT NULL, catalog_version INTEGER NOT NULL,
            FOREIGN KEY(question_type_id) REFERENCES sat_question_types(id)
        );
        CREATE TABLE IF NOT EXISTS sat_question_type_knowledge_points (
            question_type_id TEXT NOT NULL, knowledge_point_id TEXT NOT NULL,
            PRIMARY KEY(question_type_id, knowledge_point_id)
        );
        CREATE TABLE IF NOT EXISTS sat_knowledge_mastery (
            knowledge_point_id TEXT PRIMARY KEY, manually_mastered INTEGER NOT NULL DEFAULT 0,
            updated_at REAL NOT NULL
        );
        """)
    }

    private func loadManuallyMasteredKnowledgePoints() -> Set<String> {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT knowledge_point_id FROM sat_knowledge_mastery WHERE manually_mastered = 1;", -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }
        var ids: Set<String> = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let id = columnText(statement, 0) { ids.insert(id) }
        }
        return ids
    }

    private func seedSATKnowledgeCatalog() -> Bool {
        guard execute("BEGIN IMMEDIATE TRANSACTION;") else { return false }
        for item in SATKnowledgeCatalog.questionTypes {
            guard upsertQuestionType(item) else { execute("ROLLBACK;"); return false }
        }
        for item in SATKnowledgeCatalog.knowledgePoints {
            guard upsertKnowledgePoint(item) else { execute("ROLLBACK;"); return false }
        }
        return execute("COMMIT;")
    }

    private func upsertQuestionType(_ item: SATQuestionTypeDefinition) -> Bool {
        let sql = "INSERT OR REPLACE INTO sat_question_types (id, domain, skill, title_zh, title_en, catalog_version) VALUES (?, ?, ?, ?, ?, ?);"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return false }
        defer { sqlite3_finalize(statement) }
        [item.id, item.domain, item.skill, item.titleZH, item.titleEN].enumerated().forEach {
            sqlite3_bind_text(statement, Int32($0.offset + 1), $0.element, -1, SQLITE_TRANSIENT)
        }
        sqlite3_bind_int(statement, 6, Int32(SATKnowledgeCatalog.version))
        return sqlite3_step(statement) == SQLITE_DONE
    }

    private func upsertKnowledgePoint(_ item: SATKnowledgePointDefinition) -> Bool {
        let sql = "INSERT OR REPLACE INTO sat_knowledge_points (id, question_type_id, title_zh, title_en, catalog_version) VALUES (?, ?, ?, ?, ?);"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return false }
        defer { sqlite3_finalize(statement) }
        [item.id, item.questionTypeID, item.titleZH, item.titleEN].enumerated().forEach {
            sqlite3_bind_text(statement, Int32($0.offset + 1), $0.element, -1, SQLITE_TRANSIENT)
        }
        sqlite3_bind_int(statement, 5, Int32(SATKnowledgeCatalog.version))
        guard sqlite3_step(statement) == SQLITE_DONE else { return false }
        return execute("INSERT OR IGNORE INTO sat_question_type_knowledge_points (question_type_id, knowledge_point_id) VALUES ('\(item.questionTypeID)', '\(item.id)');")
    }

    private func insertOrReplace(_ payload: HistorySavePayload) -> Bool {
        let sql = """
        INSERT OR REPLACE INTO sessions
        (id, title, created_at, updated_at, category, study_status, selected_answer, correct_answer, vocabulary_json, ocr_json, messages_json, learning_json)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
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
        sqlite3_bind_text(statement, 12, payload.learningJSON, -1, SQLITE_TRANSIENT)
        return sqlite3_step(statement) == SQLITE_DONE
    }

    private func loadSessions() -> [TutorSession] {
        var loaded: [TutorSession] = []
        var statement: OpaquePointer?
        let sql = """
        SELECT id, title, created_at, updated_at, category, study_status, selected_answer, correct_answer, vocabulary_json, ocr_json, messages_json, learning_json
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
              let learningJSON = columnText(statement, 11),
              let vocabularyData = vocabularyJSON.data(using: .utf8),
              let ocrData = ocrJSON.data(using: .utf8),
              let messagesData = messagesJSON.data(using: .utf8),
              let learningData = learningJSON.data(using: .utf8),
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
            vocabularyCards: vocabularyCards,
            learningMetadata: (try? JSONDecoder.tutorClip.decode(SATLearningMetadata.self, from: learningData)) ?? SATLearningMetadata()
        )
    }

    private func migrateSchema() -> Bool {
        guard let existingColumns = sessionColumnNames() else { return false }
        let migrations = [
            ("study_status", "ALTER TABLE sessions ADD COLUMN study_status TEXT NOT NULL DEFAULT 'unreviewed';"),
            ("selected_answer", "ALTER TABLE sessions ADD COLUMN selected_answer TEXT;"),
            ("correct_answer", "ALTER TABLE sessions ADD COLUMN correct_answer TEXT;"),
            ("vocabulary_json", "ALTER TABLE sessions ADD COLUMN vocabulary_json TEXT NOT NULL DEFAULT '[]';"),
            ("learning_json", "ALTER TABLE sessions ADD COLUMN learning_json TEXT NOT NULL DEFAULT '{}';")
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

