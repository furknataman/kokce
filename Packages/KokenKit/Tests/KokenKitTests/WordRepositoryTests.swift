import Foundation
import Testing
import KokenKit

@Suite("Katalog deposu")
struct WordRepositoryTests {

    /// Her test kendi geçici klasörü ve kendi `UserDefaults` bölmesiyle çalışır.
    struct Sandbox {
        let directory: URL
        let bundleURL: URL
        let cacheURL: URL
        let defaults: UserDefaults
        let suiteName: String

        init(bundleVersion: Int = 1) throws {
            directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("koken-tests-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            bundleURL = directory.appendingPathComponent("bundle.json")
            cacheURL = directory.appendingPathComponent("cache/words.json")
            try Fixtures.encoded(Fixtures.catalog(contentVersion: bundleVersion)).write(to: bundleURL)
            suiteName = "koken.tests.\(UUID().uuidString)"
            defaults = UserDefaults(suiteName: suiteName)!
        }

        func writeCache(_ data: Data) throws {
            try FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try data.write(to: cacheURL)
        }

        func tearDown() {
            UserDefaults.standard.removeSuite(named: suiteName)
            try? FileManager.default.removeItem(at: directory)
        }
    }

    @Test("Önbellek sürümü büyükse önbellek okunur")
    func prefersNewerCache() async throws {
        let sandbox = try Sandbox(bundleVersion: 1)
        defer { sandbox.tearDown() }
        try sandbox.writeCache(Fixtures.encoded(Fixtures.catalog(contentVersion: 2, ids: ["yelken"])))

        let repository = WordRepository(bundleURL: sandbox.bundleURL,
                                        cacheURL: sandbox.cacheURL,
                                        defaultsSuiteName: sandbox.suiteName,
                                        fetch: { _, _ in .notModified })
        let catalog = try await repository.catalog()
        #expect(catalog.contentVersion == 2)
        #expect(catalog.schedule.ids == ["yelken"])
    }

    @Test("Önbellek sürümü büyük değilse bundle okunur")
    func ignoresStaleCache() async throws {
        let sandbox = try Sandbox(bundleVersion: 3)
        defer { sandbox.tearDown() }
        try sandbox.writeCache(Fixtures.encoded(Fixtures.catalog(contentVersion: 3, ids: ["yelken"])))

        let repository = WordRepository(bundleURL: sandbox.bundleURL,
                                        cacheURL: sandbox.cacheURL,
                                        defaultsSuiteName: sandbox.suiteName,
                                        fetch: { _, _ in .notModified })
        let catalog = try await repository.catalog()
        #expect(catalog.contentVersion == 3)
        #expect(catalog.schedule.ids == ["kalem", "pencere", "çay"])
    }

    @Test("Bozuk önbellek silinir, bundle okunur")
    func dropsCorruptCache() async throws {
        let sandbox = try Sandbox(bundleVersion: 1)
        defer { sandbox.tearDown() }
        try sandbox.writeCache(Data("{ bu json değil".utf8))

        let repository = WordRepository(bundleURL: sandbox.bundleURL,
                                        cacheURL: sandbox.cacheURL,
                                        defaultsSuiteName: sandbox.suiteName,
                                        fetch: { _, _ in .notModified })
        let catalog = try await repository.catalog()
        #expect(catalog.contentVersion == 1)
        #expect(FileManager.default.fileExists(atPath: sandbox.cacheURL.path) == false)
    }

    @Test("Yeni sürüm indirilince atomik yazılır ve bellek tazelenir")
    func writesNewerRemoteCatalog() async throws {
        let sandbox = try Sandbox(bundleVersion: 1)
        defer { sandbox.tearDown() }
        let remote = Fixtures.encoded(Fixtures.catalog(contentVersion: 5, ids: ["yelken"]))

        let repository = WordRepository(bundleURL: sandbox.bundleURL,
                                        cacheURL: sandbox.cacheURL,
                                        defaultsSuiteName: sandbox.suiteName,
                                        fetch: { _, _ in .updated(data: remote, etag: "\"abc\"") })
        let updated = try await repository.refresh()
        #expect(updated)
        #expect(try await repository.catalog().schedule.ids == ["yelken"])
        #expect(FileManager.default.fileExists(atPath: sandbox.cacheURL.path))
        #expect(sandbox.defaults.string(forKey: "content.etag") == "\"abc\"")
    }

    @Test("Eski veya aynı sürüm yazılmaz")
    func rejectsOlderRemoteCatalog() async throws {
        let sandbox = try Sandbox(bundleVersion: 4)
        defer { sandbox.tearDown() }
        let remote = Fixtures.encoded(Fixtures.catalog(contentVersion: 4, ids: ["yelken"]))

        let repository = WordRepository(bundleURL: sandbox.bundleURL,
                                        cacheURL: sandbox.cacheURL,
                                        defaultsSuiteName: sandbox.suiteName,
                                        fetch: { _, _ in .updated(data: remote, etag: nil) })
        await #expect(throws: WordRepository.RefreshError.notNewer(remote: 4, current: 4)) {
            try await repository.refresh()
        }
        #expect(FileManager.default.fileExists(atPath: sandbox.cacheURL.path) == false)
    }

    @Test("2 MB üstü dosya reddedilir")
    func rejectsOversizedDownload() async throws {
        let sandbox = try Sandbox()
        defer { sandbox.tearDown() }
        let huge = Data(repeating: 0x20, count: WordRepository.maximumBytes + 1)

        let repository = WordRepository(bundleURL: sandbox.bundleURL,
                                        cacheURL: sandbox.cacheURL,
                                        defaultsSuiteName: sandbox.suiteName,
                                        fetch: { _, _ in .updated(data: huge, etag: nil) })
        await #expect(throws: WordRepository.RefreshError.tooLarge(huge.count)) {
            try await repository.refresh()
        }
    }

    @Test("Günde bir kez yoklanır, ETag gönderilir")
    func checksOnceADay() async throws {
        let sandbox = try Sandbox(bundleVersion: 1)
        defer { sandbox.tearDown() }
        sandbox.defaults.set("\"onceki\"", forKey: "content.etag")

        let calls = Counter()
        let repository = WordRepository(bundleURL: sandbox.bundleURL,
                                        cacheURL: sandbox.cacheURL,
                                        defaultsSuiteName: sandbox.suiteName,
                                        fetch: { _, etag in
                                            await calls.record(etag)
                                            return .notModified
                                        })
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        _ = await repository.refreshIfNeeded(now: now)
        _ = await repository.refreshIfNeeded(now: now.addingTimeInterval(3600))
        #expect(await calls.count == 1)
        #expect(await calls.lastETag == "\"onceki\"")

        _ = await repository.refreshIfNeeded(now: now.addingTimeInterval(25 * 3600))
        #expect(await calls.count == 2)
    }

    actor Counter {
        private(set) var count = 0
        private(set) var lastETag: String?

        func record(_ etag: String?) {
            count += 1
            lastETag = etag
        }
    }
}
