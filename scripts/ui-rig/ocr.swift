// Reads the words in a picture (Apple's Vision, on the Mac itself). Kept running by ios_driver.py: each line on
// stdin is a picture's path, each line on stdout a JSON list of [text, x, y, width, height], all 0 to 1 from the
// top left. Used to tell what is really on screen from what is only in the app's accessibility tree.
import Foundation
import ImageIO
import Vision

func words(in path: String) -> [[Any]] {
    let url = URL(fileURLWithPath: path) as CFURL
    guard let source = CGImageSourceCreateWithURL(url, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return [] }
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .fast
    request.usesLanguageCorrection = false
    request.minimumTextHeight = 0.006
    request.usesCPUOnly = true
    try? VNImageRequestHandler(cgImage: image).perform([request])
    return (request.results ?? []).compactMap { found in
        guard let best = found.topCandidates(1).first else { return nil }
        let box = found.boundingBox
        return [best.string, box.minX, 1 - box.maxY, box.width, box.height]
    }
}

while let path = readLine() {
    let data = try? JSONSerialization.data(withJSONObject: words(in: path))
    print(data.flatMap { String(data: $0, encoding: .utf8) } ?? "[]")
    fflush(stdout)
}
