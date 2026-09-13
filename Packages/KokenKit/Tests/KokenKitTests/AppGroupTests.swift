import Foundation
import Testing
@testable import KokenKit

@Suite("App Group")
struct AppGroupTests {

    /// İmzasız derlemede grup konteyneri yoktur; yine de yazılabilir bir
    /// önbellek yolu dönmeli, yoksa uzaktan güncelleme kod yolu hiç çalışmaz.
    @Test("Grup konteyneri yoksa yerel dizine düşülür")
    func fallsBackToApplicationSupport() throws {
        let url = try #require(AppGroup.cacheURL)
        #expect(url.lastPathComponent == "words.json")
        if AppGroup.containerURL == nil {
            #expect(url.deletingLastPathComponent().lastPathComponent == "Kokce")
        }
    }

    @Test("Yedek dizin yazılabilir")
    func fallbackDirectoryIsUsable() throws {
        let directory = try #require(AppGroup.fallbackDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let probe = directory.appendingPathComponent("probe-\(UUID().uuidString)")
        try Data("deneme".utf8).write(to: probe)
        defer { try? FileManager.default.removeItem(at: probe) }
        #expect(FileManager.default.fileExists(atPath: probe.path))
    }
}
