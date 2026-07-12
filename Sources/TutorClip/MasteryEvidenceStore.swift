import Foundation
import SQLite3

private let MASTERY_SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

struct SATMasteryEvidence: Codable, Equatable, Identifiable {
    let id: UUID
    let sessionID: UUID
    var knowledgePointIDs: [String]
    var knowledgePointWeights: [String: Double]? = nil
    let difficulty: SATDifficulty
    let teachingPurpose: SATTeachingPurpose?
    let answeredAt: Date
    let wasCorrect: Bool
    let usedHint: Bool
    let countsTowardMastery: Bool
    let errorReason: SATErrorReason?
    let nextReviewAt: Date?
    var studyStatus: StudyStatus? = nil
    var masteryState: SATMasteryState? = nil
    // Optional so evidence written by versions before state snapshots existed
    // remains decodable. Treat a missing value as a regular attempt.
    var isStateSnapshot: Bool? = nil
    var variationKey: String? = nil

    func strength(for knowledgePointID: String) -> Double {
        if let explicit = knowledgePointWeights?[knowledgePointID] { return explicit }
        return knowledgePointIDs.first == knowledgePointID ? 1 : 0.25
    }
}

@MainActor
final class MasteryEvidenceStore: ObservableObject {
    @Published private(set) var evidence: [SATMasteryEvidence] = []
    @Published private(set) var vocabularyCards: [VocabularyCard] = []

    private let worker: MasteryEvidenceDatabaseWorker

    init(baseDirectory: URL? = nil) {
        worker = MasteryEvidenceDatabaseWorker(baseDirectory: baseDirectory)
    }

    func open(completion: (() -> Void)? = nil) {
        worker.open { [weak self] evidence, cards in
            Task { @MainActor in
                self?.evidence = evidence
                self?.vocabularyCards = cards
                completion?()
            }
        }
    }

    func close(completion: (() -> Void)? = nil) {
        worker.close {
            Task { @MainActor in completion?() }
        }
    }

    func closeAndWait() {
        worker.closeAndWait()
    }

    func record(session: TutorSession, enabled: Bool, completion: ((Bool) -> Void)? = nil) {
        guard enabled else {
            completion?(true)
            return
        }
        let metadata = session.learningMetadata
        let weights = Dictionary(uniqueKeysWithValues: metadata.knowledgePointIDs.enumerated().map {
            ($0.element, $0.offset == 0 ? 1.0 : 0.25)
        })
        let variationKey = [metadata.variationTopic, metadata.variationStructure]
            .filter { !$0.isEmpty }.joined(separator: "|")
        var records = metadata.attempts.map { attempt in
            SATMasteryEvidence(
                id: attempt.id,
                sessionID: session.id,
                knowledgePointIDs: metadata.knowledgePointIDs,
                knowledgePointWeights: weights,
                difficulty: metadata.difficulty,
                teachingPurpose: metadata.teachingPurpose,
                answeredAt: attempt.answeredAt,
                wasCorrect: attempt.wasCorrect,
                usedHint: attempt.usedHint,
                countsTowardMastery: attempt.countsTowardMastery,
                errorReason: metadata.errorReason,
                nextReviewAt: metadata.nextReviewAt,
                studyStatus: session.studyStatus,
                masteryState: metadata.masteryState,
                variationKey: variationKey.isEmpty ? nil : variationKey
            )
        }
        if !metadata.knowledgePointIDs.isEmpty,
           !metadata.attempts.isEmpty || session.studyStatus != .unreviewed || metadata.nextReviewAt != nil {
            records.append(SATMasteryEvidence(
                id: session.id,
                sessionID: session.id,
                knowledgePointIDs: metadata.knowledgePointIDs,
                knowledgePointWeights: weights,
                difficulty: metadata.difficulty,
                teachingPurpose: metadata.teachingPurpose,
                answeredAt: session.updatedAt,
                wasCorrect: false,
                usedHint: true,
                countsTowardMastery: false,
                errorReason: metadata.errorReason,
                nextReviewAt: metadata.nextReviewAt,
                studyStatus: session.studyStatus,
                masteryState: metadata.masteryState,
                isStateSnapshot: true,
                variationKey: variationKey.isEmpty ? nil : variationKey
            ))
        }
        guard !records.isEmpty || !session.vocabularyCards.isEmpty else {
            completion?(true)
            return
        }
        worker.insert(records, vocabularyCards: session.vocabularyCards) { [weak self] success, evidence, cards in
            Task { @MainActor in
                self?.evidence = evidence
                self?.vocabularyCards = cards
                completion?(success)
            }
        }
    }

    func clear(completion: ((Bool) -> Void)? = nil) {
        worker.clear { [weak self] success in
            Task { @MainActor in
                if success {
                    self?.evidence = []
                    self?.vocabularyCards = []
                }
                completion?(success)
            }
        }
    }

    func saveVocabularyCard(_ card: VocabularyCard, completion: ((Bool) -> Void)? = nil) {
        worker.saveVocabularyCard(card) { [weak self] success, cards in
            Task { @MainActor in
                if success { self?.vocabularyCards = cards }
                completion?(success)
            }
        }
    }

    func deleteVocabularyCard(id: UUID, completion: ((Bool) -> Void)? = nil) {
        worker.deleteVocabularyCard(id: id) { [weak self] success, cards in
            Task { @MainActor in
                if success { self?.vocabularyCards = cards }
                completion?(success)
            }
        }
    }

    func resetKnowledgePoints(_ knowledgePointIDs: Set<String>, completion: ((Bool) -> Void)? = nil) {
        guard !knowledgePointIDs.isEmpty else {
            completion?(true)
            return
        }
        worker.deleteEvidence(overlapping: knowledgePointIDs) { [weak self] success, evidence in
            Task { @MainActor in
                if success { self?.evidence = evidence }
                completion?(success)
            }
        }
    }
}

private final class MasteryEvidenceDatabaseWorker {
    private let queue = DispatchQueue(label: "TutorClip.MasteryEvidenceDatabase")
    private let databaseURL: URL
    private var database: OpaquePointer?

    init(baseDirectory: URL?) {
        let base = baseDirectory ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".tutorclip", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: base.path)
        databaseURL = base.appendingPathComponent("mastery.sqlite")
    }

    func open(completion: @escaping ([SATMasteryEvidence], [VocabularyCard]) -> Void) {
        queue.async { [weak self] in
            guard let self else { return }
            guard sqlite3_open(databaseURL.path, &database) == SQLITE_OK,
                  execute("CREATE TABLE IF NOT EXISTS evidence (id TEXT PRIMARY KEY, payload TEXT NOT NULL, answered_at REAL NOT NULL);"),
                  execute("CREATE TABLE IF NOT EXISTS vocabulary (term TEXT PRIMARY KEY COLLATE NOCASE, payload TEXT NOT NULL, updated_at REAL NOT NULL);"),
                  execute("CREATE TABLE IF NOT EXISTS vocabulary_cards (id TEXT PRIMARY KEY, payload TEXT NOT NULL, updated_at REAL NOT NULL);") else {
                RuntimeLog.write("mastery-store-open-failed")
                completion([], [])
                return
            }
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: databaseURL.path)
            migrateLegacyVocabularyIfNeeded()
            completion(load(), loadVocabulary())
        }
    }

    func close(completion: @escaping () -> Void) {
        queue.async { [weak self] in
            guard let self else { completion(); return }
            sqlite3_close(database)
            database = nil
            completion()
        }
    }

    func closeAndWait() {
        queue.sync {
            sqlite3_close(database)
            database = nil
        }
    }

    func insert(_ records: [SATMasteryEvidence], vocabularyCards: [VocabularyCard], completion: @escaping (Bool, [SATMasteryEvidence], [VocabularyCard]) -> Void) {
        queue.async { [weak self] in
            guard let self else { return }
            var success = execute("BEGIN IMMEDIATE TRANSACTION;")
            for record in records where success {
                if record.isStateSnapshot == true {
                    success = deleteOverlappingStateSnapshots(for: record.knowledgePointIDs)
                }
                guard success else { break }
                success = insert(record)
            }
            for card in vocabularyCards where success {
                success = insert(card)
            }
            success = success ? execute("COMMIT;") : (execute("ROLLBACK;") && false)
            completion(success, load(), loadVocabulary())
        }
    }

    func clear(completion: @escaping (Bool) -> Void) {
        queue.async { [weak self] in
            guard let self else { completion(false); return }
            let success = execute("BEGIN IMMEDIATE TRANSACTION;")
                && execute("DELETE FROM evidence;")
                && execute("DELETE FROM vocabulary;")
                && execute("DELETE FROM vocabulary_cards;")
                && execute("COMMIT;")
            completion(success)
        }
    }

    func saveVocabularyCard(_ card: VocabularyCard, completion: @escaping (Bool, [VocabularyCard]) -> Void) {
        queue.async { [weak self] in
            guard let self else { completion(false, []); return }
            let success = insert(card)
            completion(success, loadVocabulary())
        }
    }

    func deleteVocabularyCard(id: UUID, completion: @escaping (Bool, [VocabularyCard]) -> Void) {
        queue.async { [weak self] in
            guard let self else { completion(false, []); return }
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(database, "DELETE FROM vocabulary_cards WHERE id = ?;", -1, &statement, nil) == SQLITE_OK else {
                completion(false, loadVocabulary())
                return
            }
            defer { sqlite3_finalize(statement) }
            sqlite3_bind_text(statement, 1, id.uuidString, -1, MASTERY_SQLITE_TRANSIENT)
            completion(sqlite3_step(statement) == SQLITE_DONE, loadVocabulary())
        }
    }

    func deleteEvidence(overlapping knowledgePointIDs: Set<String>, completion: @escaping (Bool, [SATMasteryEvidence]) -> Void) {
        queue.async { [weak self] in
            guard let self else { completion(false, []); return }
            let affected = load().filter {
                !knowledgePointIDs.isDisjoint(with: $0.knowledgePointIDs)
            }
            var success = execute("BEGIN IMMEDIATE TRANSACTION;")
            for var record in affected where success {
                let remaining = record.knowledgePointIDs.filter { !knowledgePointIDs.contains($0) }
                if remaining.isEmpty {
                    success = deleteEvidence(id: record.id)
                    continue
                }
                record.knowledgePointWeights = Dictionary(uniqueKeysWithValues: remaining.map {
                    ($0, record.strength(for: $0))
                })
                record.knowledgePointIDs = remaining
                success = insert(record)
            }
            success = success ? execute("COMMIT;") : (execute("ROLLBACK;") && false)
            completion(success, load())
        }
    }

    private func insert(_ evidence: SATMasteryEvidence) -> Bool {
        guard let data = try? JSONEncoder.tutorClip.encode(evidence),
              let payload = String(data: data, encoding: .utf8) else { return false }
        var statement: OpaquePointer?
        let sql = "INSERT OR REPLACE INTO evidence (id, payload, answered_at) VALUES (?, ?, ?);"
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { return false }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, evidence.id.uuidString, -1, MASTERY_SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 2, payload, -1, MASTERY_SQLITE_TRANSIENT)
        sqlite3_bind_double(statement, 3, evidence.answeredAt.timeIntervalSince1970)
        return sqlite3_step(statement) == SQLITE_DONE
    }

    private func deleteOverlappingStateSnapshots(for knowledgePointIDs: [String]) -> Bool {
        let targetIDs = Set(knowledgePointIDs)
        let obsoleteIDs = load().filter {
            $0.isStateSnapshot == true && !targetIDs.isDisjoint(with: $0.knowledgePointIDs)
        }.map(\.id)
        for id in obsoleteIDs where !deleteEvidence(id: id) { return false }
        return true
    }

    private func deleteEvidence(id: UUID) -> Bool {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "DELETE FROM evidence WHERE id = ?;", -1, &statement, nil) == SQLITE_OK else {
            return false
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, id.uuidString, -1, MASTERY_SQLITE_TRANSIENT)
        return sqlite3_step(statement) == SQLITE_DONE
    }

    private func load() -> [SATMasteryEvidence] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "SELECT payload FROM evidence ORDER BY answered_at DESC;", -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }
        var result: [SATMasteryEvidence] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let bytes = sqlite3_column_text(statement, 0) else { continue }
            let payload = String(cString: bytes)
            if let value = try? JSONDecoder.tutorClip.decode(SATMasteryEvidence.self, from: Data(payload.utf8)) {
                result.append(value)
            }
        }
        return result
    }

    private func insert(_ incoming: VocabularyCard) -> Bool {
        var card = incoming
        if let existing = loadVocabulary().first(where: {
            $0.id != incoming.id
                && $0.term.compare(incoming.term, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
                && $0.meaning.compare(incoming.meaning, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }) {
            card.id = existing.id
            card.learningState = existing.learningState
            card.createdAt = existing.createdAt
            card.nextReviewAt = existing.nextReviewAt
            card.lastReviewedAt = existing.lastReviewedAt
            card.reviewCount = existing.reviewCount
            card.correctStreak = existing.correctStreak
            card.lapseCount = existing.lapseCount
        }
        card.updatedAt = Date()
        guard let data = try? JSONEncoder.tutorClip.encode(card),
              let payload = String(data: data, encoding: .utf8) else { return false }
        var statement: OpaquePointer?
        let sql = "INSERT OR REPLACE INTO vocabulary_cards (id, payload, updated_at) VALUES (?, ?, ?);"
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { return false }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, card.id.uuidString, -1, MASTERY_SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 2, payload, -1, MASTERY_SQLITE_TRANSIENT)
        sqlite3_bind_double(statement, 3, Date().timeIntervalSince1970)
        return sqlite3_step(statement) == SQLITE_DONE
    }

    private func loadVocabulary() -> [VocabularyCard] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "SELECT payload FROM vocabulary_cards ORDER BY updated_at DESC;", -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }
        var result: [VocabularyCard] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let bytes = sqlite3_column_text(statement, 0),
                  let card = try? JSONDecoder.tutorClip.decode(VocabularyCard.self, from: Data(String(cString: bytes).utf8)) else { continue }
            result.append(card)
        }
        return result
    }

    private func migrateLegacyVocabularyIfNeeded() {
        guard loadVocabulary().isEmpty else { return }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "SELECT payload FROM vocabulary ORDER BY updated_at ASC;", -1, &statement, nil) == SQLITE_OK else { return }
        var cards: [VocabularyCard] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let bytes = sqlite3_column_text(statement, 0),
                  let card = try? JSONDecoder.tutorClip.decode(
                    VocabularyCard.self,
                    from: Data(String(cString: bytes).utf8)
                  ) else { continue }
            cards.append(card)
        }
        sqlite3_finalize(statement)
        guard cards.allSatisfy(insert) else { return }
        _ = execute("DELETE FROM vocabulary;")
    }

    private func execute(_ sql: String) -> Bool {
        sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK
    }
}
