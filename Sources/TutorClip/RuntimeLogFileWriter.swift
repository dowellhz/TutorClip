import Foundation

final class RuntimeLogFileWriter: @unchecked Sendable {
    private let lock = NSLock()
    private let fileURL: URL
    private let oldFileURL: URL
    private let maxFileSize: Int

    init(fileURL: URL, maxFileSize: Int) {
        self.fileURL = fileURL
        oldFileURL = fileURL.deletingLastPathComponent().appendingPathComponent("runtime.old.log")
        self.maxFileSize = maxFileSize
    }

    @discardableResult
    func append(_ text: String) -> Bool {
        guard let data = text.data(using: .utf8) else { return false }
        lock.lock()
        defer { lock.unlock() }

        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: fileURL.deletingLastPathComponent().path
            )
            try rotateIfNeeded(incomingByteCount: data.count)
            try append(data)
            return true
        } catch {
            return false
        }
    }

    private func rotateIfNeeded(incomingByteCount: Int) throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let currentSize = (attributes[.size] as? NSNumber)?.intValue ?? 0
        guard currentSize + incomingByteCount > maxFileSize else { return }
        if FileManager.default.fileExists(atPath: oldFileURL.path) {
            try FileManager.default.removeItem(at: oldFileURL)
        }
        try FileManager.default.moveItem(at: fileURL, to: oldFileURL)
    }

    private func append(_ data: Data) throws {
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try applyPrivatePermissions(to: fileURL)
            let handle = try FileHandle(forWritingTo: fileURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            return
        }

        try data.write(to: fileURL, options: [.atomic])
        do {
            try applyPrivatePermissions(to: fileURL)
        } catch {
            try? FileManager.default.removeItem(at: fileURL)
            throw error
        }
    }

    private func applyPrivatePermissions(to url: URL) throws {
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
