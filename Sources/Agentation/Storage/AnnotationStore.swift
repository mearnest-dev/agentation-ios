import Foundation

/// Keeps annotations in a JSON file in Application Support. Entries older than 7 days are dropped on load.
final class AnnotationStore {
    static let maxAge: TimeInterval = 7 * 24 * 60 * 60

    private(set) var annotations: [Annotation] = []
    let fileURL: URL

    init(fileURL: URL = AnnotationStore.defaultFileURL, now: Date = Date()) {
        self.fileURL = fileURL
        load(now: now)
    }

    static var defaultFileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("Agentation", isDirectory: true)
            .appendingPathComponent("annotations.json")
    }

    func annotation(id: String) -> Annotation? {
        annotations.first { $0.id == id }
    }

    func add(_ annotation: Annotation) {
        annotations.append(annotation)
        save()
    }

    func update(_ annotation: Annotation) {
        guard let index = annotations.firstIndex(where: { $0.id == annotation.id }) else { return }
        annotations[index] = annotation
        save()
    }

    func setServerId(_ serverId: String, for id: String) {
        guard let index = annotations.firstIndex(where: { $0.id == id }) else { return }
        annotations[index].serverId = serverId
        save()
    }

    func remove(id: String) {
        annotations.removeAll { $0.id == id }
        save()
    }

    func removeAll() {
        annotations.removeAll()
        save()
    }

    private func load(now: Date) {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([Annotation].self, from: data) else { return }
        let cutoff = now.timeIntervalSince1970 - Self.maxAge
        annotations = decoded.filter { $0.timestamp >= cutoff }
        if annotations.count != decoded.count { save() }
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(annotations).write(to: fileURL, options: .atomic)
        } catch {
            print("[Agentation] Could not save annotations: \(error)")
        }
    }
}
