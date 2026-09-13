import Foundation
import Testing
import KokenKit

/// Uygulama hedefinin duman testi: alan mantığı testleri `swift test` ile
/// KokenKit'te koşar, burada yalnızca gömülü kaynağın bundle'a gerçekten
/// kopyalandığı ve çözüldüğü doğrulanır.
@Suite("Gömülü katalog")
struct BundledCatalogTests {

    @Test("words.json uygulama bundle'ında ve çözülüyor")
    func bundledCatalogDecodes() throws {
        let url = try #require(AppGroup.bundledCatalogURL(in: .main))
        let catalog = try CatalogLoader.decode(Data(contentsOf: url))
        #expect(catalog.words.isEmpty == false)
        let today = WordOfDay.word(for: .now, in: catalog)
        #expect(today != nil)
    }
}
