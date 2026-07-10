import Vision

let request = VNRecognizeTextRequest()

do {
    let languages = try request.supportedRecognitionLanguages()
    let required = ["en-US", "zh-Hans"]
    let missing = required.filter { !languages.contains($0) }
    guard missing.isEmpty else {
        fputs("Vision text recognition is missing required languages: \(missing.joined(separator: ", "))\n", stderr)
        exit(1)
    }
    print("Vision OCR support verification passed: \(required.joined(separator: ", "))")
} catch {
    fputs("Vision OCR support verification failed: \(error)\n", stderr)
    exit(1)
}
