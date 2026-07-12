import AppKit
import XCTest
@testable import TutorClip

final class QuestionRenderingBehaviorTests: XCTestCase {
    func testTableCellIntegrityRejectsShiftedOrRewrittenHeaders() {
        let source = OCRTable(
            id: UUID(),
            boundingBox: CodableRect(.zero),
            rows: [
                [tableCell("Language", row: 0, column: 0),
                 tableCell("Rate of speech (syllables per second)", row: 0, column: 1),
                 tableCell("Rate of information conveyed (bits per second)", row: 0, column: 2)],
                [tableCell("Serbian", row: 1, column: 0), tableCell("7.2", row: 1, column: 1), tableCell("39.1", row: 1, column: 2)]
            ]
        )
        let correct = QuestionMarkdownTable(
            header: ["Language", "Rate of speech (syllables per second)", "Rate of information conveyed (bits per second)"],
            rows: [["Serbian", "7.2", "39.1"]], markdown: ""
        )
        let corrupted = QuestionMarkdownTable(
            header: ["Language", "(syllables per second)", "Rate of speech Rate of information conveyed"],
            rows: [["Serbian", "7.2", "39.1"]], markdown: ""
        )

        XCTAssertTrue(TableCellIntegrityValidator.preserves([source], in: [correct]))
        XCTAssertFalse(TableCellIntegrityValidator.preserves([source], in: [corrupted]))
    }

    private func tableCell(_ text: String, row: Int, column: Int) -> OCRTableCell {
        OCRTableCell(id: UUID(), text: text, rowStart: row, rowEnd: row, columnStart: column, columnEnd: column, boundingBox: CodableRect(.zero))
    }

    private func underlinedDocument(lines: [String], underlinedLineIndexes: Set<Int>) -> OCRDocument {
        var tokens: [OCRToken] = []
        let ocrLines = lines.enumerated().map { lineIndex, text -> OCRLine in
            let lineTokens = text.compactMap { character -> OCRToken? in
                guard !character.isWhitespace else { return nil }
                return OCRToken(
                    id: UUID(), text: String(character), boundingBox: CodableRect(.zero),
                    confidence: 1, isLikelyUnderlined: underlinedLineIndexes.contains(lineIndex)
                )
            }
            tokens.append(contentsOf: lineTokens)
            return OCRLine(
                id: UUID(), text: text, boundingBox: CodableRect(.zero), confidence: 1,
                tokenIds: lineTokens.map(\.id)
            )
        }
        let text = lines.joined(separator: "\n")
        return OCRDocument(
            id: UUID(), fullText: text, editedText: text, detectedLanguage: "en", createdAt: Date(),
            blocks: [], lines: ocrLines, tokens: tokens, tables: []
        )
    }

    func testUnderlinePolicyFiltersStructuredRegionsAndRepeatedText() {
        XCTAssertTrue(OCRVisualCuePolicy.shouldSuppressUnderlineDetection(detectedCount: 40, totalCount: 80))
        XCTAssertFalse(OCRVisualCuePolicy.shouldSuppressUnderlineDetection(detectedCount: 5, totalCount: 10))
        XCTAssertFalse(OCRVisualCuePolicy.shouldSuppressUnderlineDetection(detectedCount: 8, totalCount: 100))
        XCTAssertTrue(OCRVisualCuePolicy.substantiallyContains(
            CGRect(x: 0.2, y: 0.2, width: 0.1, height: 0.05),
            region: CGRect(x: 0.1, y: 0.1, width: 0.4, height: 0.3)
        ))
        XCTAssertNil(UnderlineTextMatcher.uniqueRange(of: "languages", in: "languages and languages"))
        XCTAssertNotNil(UnderlineTextMatcher.uniqueRange(of: "Serbian", in: "Serbian and Spanish"))
        XCTAssertFalse(OCRVisualCuePolicy.occursUniquely("conveyed", in: "information conveyed; information conveyed"))
        XCTAssertTrue(OCRVisualCuePolicy.occursUniquely("Serbian", in: "Serbian and Spanish"))
    }

    func testUnderlineSpansPreserveMultilineSentenceWithRepeatedWords() {
        let firstLine = "Using data from the companies"
        let secondLine = "to compare the companies."
        let document = underlinedDocument(
            lines: [
                "A study introduces the research context before the evidence.",
                firstLine,
                secondLine,
                "The question asks about the function of the underlined sentence."
            ],
            underlinedLineIndexes: [1, 2]
        )

        XCTAssertEqual(
            OCRVisualCuePolicy.underlinedTextSpans(in: document),
            ["Using data from the companies to compare the companies."]
        )
        XCTAssertNotNil(UnderlineTextMatcher.range(
            of: "Using data from the companies to compare the companies.",
            in: "Using data from the companies\nto compare the companies."
        ))
    }

    func testUploadedUnderlinedSentenceFixtureRestoresFullSentenceSpan() async throws {
        let fixtureURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/underlined_sentence_multiline.png")
        let image = try XCTUnwrap(NSImage(contentsOf: fixtureURL))

        let document = await OCRService().recognize(image: image, language: .english)
        let spans = OCRVisualCuePolicy.underlinedTextSpans(in: document)
        let normalizedSpans = spans.map { $0.split(whereSeparator: \.isWhitespace).joined(separator: " ") }

        XCTAssertTrue(normalizedSpans.contains {
            $0.contains("Using data spanning from 1994") && $0.contains("those companies.")
        }, "Expected the fixture's full underlined sentence, got: \(spans)")
        XCTAssertTrue(PromptBuilder().formatOCRPrompt(document: document).last?.content.contains(
            "<u>Using data spanning from 1994"
        ) == true)
    }

    func testSelectableQuestionRendererPartiallyRendersMalformedInlineMarkdown() {
        let rendered = SelectableQuestionTextRenderer.attributedString(
            from: "A readable sentence with **an unfinished emphasis marker."
        )
        XCTAssertTrue(rendered.string.contains("A readable sentence"))
        XCTAssertTrue(rendered.length > 0)
    }

    func testQuestionRendererAndTitleDoNotExposeBlockOrEmphasisMarkers() {
        let question = "Passage from *Scientific American*\n\n> Quoted stimulus text."
        let rendered = SelectableQuestionTextRenderer.attributedString(from: question).string

        XCTAssertEqual(rendered, "Passage from Scientific American\n\nQuoted stimulus text.")
        XCTAssertEqual(SessionTitle.make(from: question), "Passage from Scientific American Quoted stimulus text.")
        XCTAssertFalse(SessionTitle.make(from: "A <u>marked</u> phrase").contains("<u>"))
    }

    func testGeneratedUnderlineMarkupRendersWithoutShowingProtocolTags() {
        let target = "following nearly identical routes each year"
        let rendered = SelectableQuestionTextRenderer.attributedString(
            from: "The whales migrated, <u>\(target)</u>."
        )
        let range = (rendered.string as NSString).range(of: target)

        XCTAssertFalse(rendered.string.contains("<u>"))
        XCTAssertNotEqual(range.location, NSNotFound)
        XCTAssertEqual(
            rendered.attribute(.underlineStyle, at: range.location, effectiveRange: nil) as? Int,
            NSUnderlineStyle.single.rawValue
        )
    }

    func testUnderlineMarkupPreservesSurroundingMarkdownEmphasis() {
        for source in ["The evidence **<u>documents</u>** the event.", "The evidence <u>**documents**</u> the event."] {
            let rendered = SelectableQuestionTextRenderer.attributedString(from: source)
            let range = (rendered.string as NSString).range(of: "documents")

            XCTAssertEqual(rendered.string, "The evidence documents the event.")
            XCTAssertEqual(
                rendered.attribute(.underlineStyle, at: range.location, effectiveRange: nil) as? Int,
                NSUnderlineStyle.single.rawValue
            )
        }
    }

    func testUnderlineReferenceContractRequiresVisibleTargetMarkup() {
        XCTAssertFalse(QuestionUnderlineMarkup.satisfiesReferenceContract(
            "Which choice describes the function of the underlined portion?"
        ))
        XCTAssertTrue(QuestionUnderlineMarkup.satisfiesReferenceContract(
            "The whales <u>followed the same route</u>. Which choice describes the function of the underlined portion?"
        ))
    }

    @MainActor
    func testPracticeValidationRejectsMissingUnderlineBeforeNetworkReview() async throws {
        let question = GeneratedQuestion(
            question: "A sentence presents evidence.\n\nWhich choice describes the underlined portion?\n\nA) One\nB) Two\nC) Three\nD) Four",
            answer: "A",
            category: .reading,
            learningMetadata: SATLearningMetadata(isAIGenerated: true),
            contract: GeneratedQuestionContract(
                teachingPurpose: "diagnostic", prerequisites: "none",
                distractors: ["correct", "x", "y", "z"], explanationBasis: "synthetic"
            )
        )

        let result = try await PracticeQuestionValidator(client: FailingQuestionReviewStreamer()).validate(question)
        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.reason.contains("<u>"))
    }

    func testPracticePromptRequiresExplicitUnderlineProtocol() {
        let promptBuilder = PromptBuilder()
        XCTAssertTrue(promptBuilder.practiceSimilarInstruction(language: .chinese).contains("<u>"))
        XCTAssertTrue(promptBuilder.practiceSimilarInstruction(language: .english).contains("<u>"))
        XCTAssertTrue(promptBuilder.practiceSimilarInstruction(language: .english).contains("exactly one question"))
        XCTAssertTrue(promptBuilder.practiceSimilarInstruction(language: .english).contains("current Digital SAT"))
        XCTAssertTrue(promptBuilder.practiceSimilarInstruction(language: .chinese).contains("Text 1/Text 2"))
    }

    func testGeneratedQuestionStructureRejectsPairedQuestions() {
        XCTAssertFalse(GeneratedQuestionStructure.containsExactlyOneQuestion(
            "Questions 1-2 are based on the following passage.\n\n1. First question\nA) A\nB) B\nC) C\nD) D\n\n2. Second question"
        ))
        XCTAssertTrue(GeneratedQuestionStructure.containsExactlyOneQuestion(
            "A passage.\n\nWhich choice is best?\nA) A\nB) B\nC) C\nD) D"
        ))
    }

    @MainActor
    func testApplicationEditMenuProvidesStandardKeyboardCommands() {
        let items = ApplicationEditMenuItems.make(language: .english)
        XCTAssertTrue(items.contains { $0.keyEquivalent == "z" })
        XCTAssertTrue(items.contains { $0.keyEquivalent == "x" })
        XCTAssertTrue(items.contains { $0.keyEquivalent == "c" })
        XCTAssertTrue(items.contains { $0.keyEquivalent == "v" })
        XCTAssertTrue(items.contains { $0.keyEquivalent == "a" })
    }

    func testAnswerChoicesRecognizeMarkdownListWithoutTreatingProseAsLoneA() {
        let question = """
        A historian compared two sources before reaching a conclusion.

        Which choice best describes the method?

        - (A) First choice
        - (B) Second choice
        - (C) Third choice
        - (D) Fourth choice
        """
        XCTAssertEqual(TutorQuestionParsing.answerChoices(from: question), ["A", "B", "C", "D"])
        XCTAssertEqual(
            TutorQuestionParsing.answerChoices(from: "**A)** One\n**B)** Two\n**C)** Three\n**D)** Four"),
            ["A", "B", "C", "D"]
        )
        XCTAssertEqual(TutorQuestionParsing.answerChoices(from: "A historian compared two sources."), [])
    }

    func testLegacyVocabularyCardDecodesAsDueNewCard() throws {
        let payload = """
        {"id":"\(UUID().uuidString)","term":"hybrid","meaning":"杂交体","note":"混合体","source":"plant-animal hybrids"}
        """
        let card = try JSONDecoder.tutorClip.decode(VocabularyCard.self, from: Data(payload.utf8))
        XCTAssertEqual(card.learningState, .new)
        XCTAssertEqual(card.reviewCount, 0)
        XCTAssertTrue(card.isDue)
    }

    func testVocabularyReviewUsesFastMasteryAndAdaptiveRetryIntervals() {
        let now = Date(timeIntervalSince1970: 10_000)
        var known = VocabularyCard(id: UUID(), term: "hybrid", meaning: "杂交体", note: "", example: nil, source: "")
        known.applyReview(.known, now: now)
        XCTAssertEqual(known.learningState, .mastered)
        XCTAssertEqual(known.correctStreak, 1)
        XCTAssertEqual(known.nextReviewAt, now.addingTimeInterval(7 * 24 * 60 * 60))

        var missed = known
        missed.applyReview(.unknown, now: now)
        XCTAssertEqual(missed.learningState, .learning)
        XCTAssertEqual(missed.correctStreak, 0)
        XCTAssertEqual(missed.nextReviewAt, now.addingTimeInterval(10 * 60))
    }

    func testVocabularySearchDoesNotMatchHiddenSourceText() {
        let card = VocabularyCard(
            id: UUID(), term: "flee", meaning: "逃离", note: "迅速离开",
            example: "Many families fled the conflict zone.", source: "Susie Taylor escaped slavery."
        )
        XCTAssertTrue(VocabularyCardSearch.matches(card, query: "flee"))
        XCTAssertTrue(VocabularyCardSearch.matches(card, query: "逃离"))
        XCTAssertFalse(VocabularyCardSearch.matches(card, query: "Susie"))
    }

    @MainActor
    func testPracticeValidationRejectsIncompleteDisplayedChoicesBeforeNetworkReview() async throws {
        let question = GeneratedQuestion(
            question: "Which choice?\n\nA. Only one displayed choice",
            answer: "A",
            category: .reading,
            learningMetadata: SATLearningMetadata(isAIGenerated: true),
            contract: GeneratedQuestionContract(
                teachingPurpose: "diagnostic",
                prerequisites: "none",
                distractors: ["a", "b", "c", "d"],
                explanationBasis: "synthetic"
            )
        )

        let result = try await PracticeQuestionValidator(client: FailingQuestionReviewStreamer())
            .validate(question)

        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.reason.contains("A/B/C/D"))
    }

    func testMicroCheckRejectsIncompleteChoiceProtocol() {
        let raw = """
        MICRO_CHECK
        Question: Which choice?
        A. One
        B. Two
        C. Three
        Answer: B
        END_MICRO_CHECK
        """
        XCTAssertNil(SATMicroCheck.extract(from: raw).check)
    }

    @MainActor
    func testMathQuestionIsRejectedWithoutReplacingOCRText() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let original = "Which expression is equivalent to garbled formula?"
        let session = TutorSession.newSession(screenshot: NSImage(size: NSSize(width: 8, height: 8)))
        session.ocrDocument.editedText = original
        let viewModel = TutorViewModel(
            session: session, isLoadingOCR: false,
            settingsStore: SettingsStore(baseDirectory: root.appendingPathComponent("settings")),
            historyStore: HistoryStore(baseDirectory: root.appendingPathComponent("history")),
            deepSeekClient: MathQuestionStreamer(), promptBuilder: PromptBuilder(),
            onRecapture: {}, onSettings: {}, onClose: {}
        )
        viewModel.formatOCR()
        for _ in 0..<30 where viewModel.ocrFormatState == .formatting { await Task.yield() }

        XCTAssertTrue(viewModel.ocrFormatState.isError)
        XCTAssertEqual(viewModel.session.ocrDocument.editedText, original)
        XCTAssertNil(viewModel.session.correctAnswer)
        XCTAssertEqual(viewModel.session.category, .math)
    }
}

@MainActor
private final class FailingQuestionReviewStreamer: DeepSeekStreaming {
    func stream(messages: [DeepSeekMessage], onToken: @escaping @MainActor (String) -> Void) async throws {
        XCTFail("Incomplete choices must be rejected before network validation")
    }
}

@MainActor
private final class MathQuestionStreamer: DeepSeekStreaming {
    func stream(messages: [DeepSeekMessage], onToken: @escaping @MainActor (String) -> Void) async throws {
        onToken("""
        FORMATTED_QUESTION
        Which expression is equivalent to $6x^8y^2$?
        END_FORMATTED_QUESTION
        QUESTION_METADATA
        Answer: C
        Type: math
        Confidence: 1
        END_QUESTION_METADATA
        """)
    }
}
