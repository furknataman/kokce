import Foundation

/// Katalog dosyalarını çözen ve doğrulayan **salt okunur** yardımcı.
///
/// Hem `WordRepository` hem de widget bunu kullanır: widget'ın zaman çizelgesi
/// eşzamanlı üretildiği için yükleme mantığının actor'dan bağımsız olması
/// gerekir. Yükleyici hiçbir şey silmez veya yazmaz — bozuk önbelleği temizlemek
/// tek yazıcının, yani uygulamadaki `WordRepository`'nin işidir. Widget'ın
/// dosya silmesi, uygulama tam o sırada yazarken yarışa yol açardı.
public enum CatalogLoader {

    public enum LoadError: Error, Equatable {
        /// Şema sürümü uygulamanın desteklediğinden farklı.
        case unsupportedSchema(Int)
        case empty
        case duplicateIDs
        /// `schedule.ids` içinde katalogda olmayan kimlik var.
        case unknownScheduleID(String)
        /// `schedule.start` "yyyy-MM-dd" değil veya takvimde olmayan bir gün.
        case invalidScheduleStart(String)
    }

    /// Önbelleğin okunabilirliği. `WordRepository` buna bakarak bozuk dosyayı
    /// siler ve ETag gönderip göndermeyeceğine karar verir.
    public enum CacheStatus: Sendable, Equatable {
        /// Önbellek dosyası yok (veya önbellek hiç yapılandırılmamış).
        case absent
        /// Dosya var ama çözülemedi ya da doğrulamadan geçmedi.
        case invalid
        /// Dosya geçerli. Bundle daha yeni olsa bile dosyanın kendisi sağlamdır.
        case valid
    }

    public struct LoadResult: Sendable {
        public let catalog: WordCatalog
        public let cacheStatus: CacheStatus
    }

    /// Okunacak kataloğu seçer.
    ///
    /// Öncelik: geçerli önbellek **ve** `contentVersion` bundle'dakinden
    /// büyükse önbellek; aksi hâlde bundle.
    public static func load(bundleURL: URL, cacheURL: URL?) throws -> WordCatalog {
        try loadResult(bundleURL: bundleURL, cacheURL: cacheURL).catalog
    }

    /// `load` ile aynı seçim, ayrıca önbelleğin durumu.
    public static func loadResult(bundleURL: URL, cacheURL: URL?) throws -> LoadResult {
        let bundled = try decode(Data(contentsOf: bundleURL))
        guard let cacheURL, FileManager.default.fileExists(atPath: cacheURL.path) else {
            return LoadResult(catalog: bundled, cacheStatus: .absent)
        }
        do {
            let cached = try decode(Data(contentsOf: cacheURL))
            let newer = cached.contentVersion > bundled.contentVersion
            return LoadResult(catalog: newer ? cached : bundled, cacheStatus: .valid)
        } catch {
            return LoadResult(catalog: bundled, cacheStatus: .invalid)
        }
    }

    /// JSON'u çözer ve temel tutarlılığı doğrular.
    public static func decode(_ data: Data) throws -> WordCatalog {
        let catalog = try JSONDecoder().decode(WordCatalog.self, from: data)
        try validate(catalog)
        return catalog
    }

    /// Uzaktan gelen dosyada da uygulanan asgari kurallar.
    public static func validate(_ catalog: WordCatalog) throws {
        guard catalog.schemaVersion == WordCatalog.supportedSchemaVersion else {
            throw LoadError.unsupportedSchema(catalog.schemaVersion)
        }
        guard !catalog.words.isEmpty, !catalog.schedule.ids.isEmpty else { throw LoadError.empty }
        guard WordOfDay.day(from: catalog.schedule.start) != nil else {
            throw LoadError.invalidScheduleStart(catalog.schedule.start)
        }
        let ids = Set(catalog.words.map(\.id))
        guard ids.count == catalog.words.count else { throw LoadError.duplicateIDs }
        for id in catalog.schedule.ids where !ids.contains(id) {
            throw LoadError.unknownScheduleID(id)
        }
    }
}
