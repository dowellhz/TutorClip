import Foundation

@MainActor
final class OCRRequestLifecycle {
    private var task: Task<Void, Never>?
    private var activeSessionID: UUID?

    func start(
        sessionID: UUID,
        operation: @escaping () async -> OCRDocument,
        onResult: @escaping (OCRDocument) -> Void
    ) {
        cancel(reason: "replaced")
        activeSessionID = sessionID
        task = Task { [weak self] in
            let document = await operation()
            guard let self,
                  !Task.isCancelled,
                  self.activeSessionID == sessionID else {
                RuntimeLog.write("ocr-result-discarded session=\(sessionID.uuidString)")
                return
            }
            self.activeSessionID = nil
            self.task = nil
            onResult(document)
        }
    }

    func cancel(reason: String) {
        guard task != nil || activeSessionID != nil else { return }
        RuntimeLog.write("ocr-request-cancel reason=\(reason)")
        activeSessionID = nil
        task?.cancel()
        task = nil
    }
}
