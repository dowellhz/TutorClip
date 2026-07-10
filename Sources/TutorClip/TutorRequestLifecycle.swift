import Foundation

@MainActor
extension TutorViewModel {
    func beginRequest() -> UUID {
        let requestID = UUID()
        activeRequestID = requestID
        isStreaming = true
        return requestID
    }

    func finishRequest(_ requestID: UUID) {
        guard activeRequestID == requestID else { return }
        activeRequestID = nil
        inFlightTask = nil
        isStreaming = false
    }

    func isCurrentRequest(_ requestID: UUID) -> Bool {
        activeRequestID == requestID && !Task.isCancelled
    }

    func cancelInFlightRequest(reason: String) {
        guard inFlightTask != nil || activeRequestID != nil else { return }
        RuntimeLog.write("request-cancel reason=\(reason)")
        activeRequestID = nil
        inFlightTask?.cancel()
        inFlightTask = nil
        isStreaming = false
    }
}
