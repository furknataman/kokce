import Foundation

/// Katalogu okuyan ve uzaktan güncelleyen tek nokta.
///
/// Dosya ve ağ işi actor içinde tutulur; arayüz `@MainActor` tarafta kalır.
/// Yazıcı yalnızca uygulamadır, widget aynı dosyayı yalnızca okur.
public actor WordRepository {

    /// Uzak dosyanın durumu. Test, ağa çıkmadan bu iki durumu üretir.
    public enum RemoteResponse: Sendable, Equatable {
        case notModified
        case updated(data: Data, etag: String?)
    }

    public typealias Fetch = @Sendable (_ url: URL, _ etag: String?) async throws -> RemoteResponse

    public enum RefreshError: Error, Equatable {
        case tooLarge(Int)
        case notNewer(remote: Int, current: Int)
        case badResponse(Int)
        case noCacheDirectory
    }

    /// Uzak katalog. Depo adı değişirse yalnızca burası güncellenir.
    public static let remoteURL = URL(string: "https://raw.githubusercontent.com/solvyapp/koken/main/Resources/Content/words.json")!
    public static let maximumBytes = 2 * 1024 * 1024
    public static let timeout: TimeInterval = 10
    /// İki kontrol arası en az bir gün.
    public static let checkInterval: TimeInterval = 24 * 60 * 60

    static let lastCheckKey = "content.lastCheckAt"
    static let etagKey = "content.etag"

    private let bundleURL: URL
    private let cacheURL: URL?
    private let defaults: UserDefaults?
    private let remoteURL: URL
    private let fetch: Fetch
    private var loaded: WordCatalog?
    /// Diskteki önbellek dosyası okunabilir mi? ETag yalnızca bu dosya
    /// duruyorsa anlamlıdır.
    private var hasValidCache = false
    /// Süren güncelleme. Örtüşen çağrılar yeni istek açmaz, buna katılır.
    private var refreshTask: Task<Bool, Error>?

    /// - Parameters:
    ///   - bundleURL: Gömülü `words.json`. Enjekte edilir; `Bundle.main` widget
    ///     içinde uzantının bundle'ıdır ve testte hiç yoktur.
    ///   - cacheURL: App Group içindeki önbellek dosyası; `nil` ise güncelleme
    ///     kapalıdır, yalnızca bundle okunur.
    ///   - defaultsSuiteName: ETag ve son kontrol zamanının yazıldığı bölme.
    ///     `UserDefaults` `Sendable` olmadığı için örnek değil ad geçirilir;
    ///     actor kendi örneğini kurar.
    ///   - fetch: Ağ katmanı. Testler kendi sahtesini verir.
    public init(bundleURL: URL,
                cacheURL: URL? = AppGroup.cacheURL,
                defaultsSuiteName: String? = AppGroup.identifier,
                remoteURL: URL = WordRepository.remoteURL,
                fetch: @escaping Fetch = WordRepository.download) {
        self.bundleURL = bundleURL
        self.cacheURL = cacheURL
        self.defaults = defaultsSuiteName.flatMap { UserDefaults(suiteName: $0) }
        self.remoteURL = remoteURL
        self.fetch = fetch
    }

    /// Bellekte tutulan katalog; ilk çağrıda diskten yüklenir.
    ///
    /// Bozuk önbellek dosyası burada silinir: yükleyici salt okunurdur, silme
    /// yetkisi yalnızca tek yazıcıda, yani bu actor'dadır.
    public func catalog() throws -> WordCatalog {
        if let loaded { return loaded }
        let result = try CatalogLoader.loadResult(bundleURL: bundleURL, cacheURL: cacheURL)
        if result.cacheStatus == .invalid, let cacheURL {
            try? FileManager.default.removeItem(at: cacheURL)
            defaults?.removeObject(forKey: Self.etagKey)
        }
        hasValidCache = result.cacheStatus == .valid
        loaded = result.catalog
        return result.catalog
    }

    /// Günde bir kez uzak dosyayı yoklar. Katalog değiştiyse `true`.
    ///
    /// Ağ hatası yutulur: içerik güncellemesi uygulamanın çalışması için
    /// gerekli değildir. Kontrol zamanı, hata durumunda da yazılır ki her
    /// açılışta yeniden denenmesin.
    @discardableResult
    public func refreshIfNeeded(now: Date = .now) async -> Bool {
        let last = defaults?.object(forKey: Self.lastCheckKey) as? Date
        if let last, now.timeIntervalSince(last) < Self.checkInterval { return false }
        defaults?.set(now, forKey: Self.lastCheckKey)
        return (try? await refresh()) ?? false
    }

    /// Zamanlamayı yok sayıp uzak dosyayı indirir ve doğrularsa yazar.
    ///
    /// Aynı anda gelen ikinci çağrı yeni istek açmaz, sürenin sonucunu bekler.
    @discardableResult
    public func refresh() async throws -> Bool {
        if let refreshTask { return try await refreshTask.value }
        let task = Task<Bool, Error> { try await self.performRefresh() }
        refreshTask = task
        defer { refreshTask = nil }
        return try await task.value
    }

    private func performRefresh() async throws -> Bool {
        guard let cacheURL else { throw RefreshError.noCacheDirectory }
        _ = try catalog()
        // ETag yalnızca elimizdeki önbellek dosyasını tanımlar. Dosya yoksa ya
        // da bozuk çıkıp silindiyse koşulsuz GET yapılır, yoksa sunucu 304 der
        // ve elimizde hiç içerik kalmaz.
        let etag = hasValidCache ? defaults?.string(forKey: Self.etagKey) : nil
        let response = try await fetch(remoteURL, etag)
        guard case let .updated(data, newETag) = response else { return false }
        guard data.count <= Self.maximumBytes else { throw RefreshError.tooLarge(data.count) }

        // Önce tam çözüm + doğrulama, sonra yazım: yarım dosya asla diske inmez.
        let remote = try CatalogLoader.decode(data)
        // Ağı beklerken başka bir güncelleme tamamlanmış olabilir; sürüm
        // karşılaştırması yazımdan hemen önce, güncel değerle yapılır.
        let current = try catalog()
        guard remote.contentVersion > current.contentVersion else {
            throw RefreshError.notNewer(remote: remote.contentVersion, current: current.contentVersion)
        }
        try write(data, to: cacheURL)
        defaults?.set(newETag, forKey: Self.etagKey)
        hasValidCache = true
        loaded = remote
        return true
    }

    /// Atomik yazım: geçici dosyaya yazılıp yerine taşınır, böylece widget
    /// yarım dosya okumaz.
    private func write(_ data: Data, to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    /// Varsayılan ağ katmanı: ETag'li koşullu GET.
    ///
    /// `URLCache` kapalıdır; açık olsaydı 304 sessizce 200'e çevrilip
    /// önbellekten yanıtlanır ve "değişmedi" durumu hiç görülmezdi.
    ///
    /// Gövde akış hâlinde okunur ve sayılır: 2 MB sınırı aşıldığı anda döngüden
    /// çıkılır, akış iptal olur. Sınır, tüm dosya belleğe alındıktan sonra değil
    /// indirme sırasında uygulanır.
    public static let download: Fetch = { url, etag in
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }

        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        if let etag { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }

        let (stream, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { return .notModified }
        switch http.statusCode {
        case 304:
            return .notModified
        case 200:
            // Sunucu boyutu bildiriyorsa tek bayt indirmeden reddet.
            if http.expectedContentLength > Int64(maximumBytes) {
                throw RefreshError.tooLarge(Int(clamping: http.expectedContentLength))
            }
            var data = Data()
            data.reserveCapacity(64 * 1024)
            for try await byte in stream {
                data.append(byte)
                if data.count > maximumBytes { throw RefreshError.tooLarge(data.count) }
            }
            return .updated(data: data, etag: http.value(forHTTPHeaderField: "ETag"))
        default:
            throw RefreshError.badResponse(http.statusCode)
        }
    }
}
