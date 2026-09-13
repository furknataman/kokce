import Foundation

/// Katalog dosyalarını çözen ve doğrulayan saf yardımcı.
///
/// Hem `WordRepository` hem de widget bunu kullanır: widget'ın zaman çizelgesi
/// eşzamanlı üretildiği için yükleme mantığının actor'dan bağımsız olması
/// gerekir.
public enum CatalogLoader {

    public enum LoadError: Error, Equatable {
        /// Şema sürümü uygulamanın desteklediğinden farklı.
        case unsupportedSchema(Int)
        case empty
        case duplicateIDs
        /// `schedule.ids` içinde katalogda olmayan kimlik var.
        case unknownScheduleID(String)
    }

    /// Bundle ve (varsa) önbellek dosyasından uygun olanı seçer.
    ///
    /// Öncelik: geçerli önbellek **ve** `contentVersion` bundle'dakinden
    /// büyükse önbellek; aksi hâlde bundle. Bozuk veya geçersiz önbellek
    /// dosyası silinir, böylece bir daha denenmez.
    public static func load(bundleURL: URL, cacheURL: URL?) throws -> WordCatalog {
        let bundled = try decode(Data(contentsOf: bundleURL))
        guard let cacheURL, FileManager.default.fileExists(atPath: cacheURL.path) else { return bundled }
        do {
            let cached = try decode(Data(contentsOf: cacheURL))
            guard cached.contentVersion > bundled.contentVersion else { return bundled }
            return cached
        } catch {
            try? FileManager.default.removeItem(at: cacheURL)
            return bundled
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
        let ids = Set(catalog.words.map(\.id))
        guard ids.count == catalog.words.count else { throw LoadError.duplicateIDs }
        for id in catalog.schedule.ids where !ids.contains(id) {
            throw LoadError.unknownScheduleID(id)
        }
    }
}
