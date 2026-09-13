import Foundation
import SwiftUI
import Testing
import WidgetKit
import KokenKit

/// Dört widget ailesinin görünümünü gerçek nokta boyutlarında render eder ve
/// PNG olarak yazar. Simülatörün widget galerisine widget eklemenin `simctl`
/// karşılığı yok; görsel doğrulama bu yüzden görünümlerin kendisinden alınır.
@Suite("Widget anlık görüntüleri")
@MainActor
struct WidgetSnapshotTests {

    @Test("Dört aile açık ve koyu modda render edilir")
    func rendersEveryFamily() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("kokce-widget-snapshots", isDirectory: true)
        try? FileManager.default.removeItem(at: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let entry = KokcePreview.entry
        let word = try #require(entry.word)

        for scheme in [ColorScheme.light, .dark] {
            let suffix = scheme == .dark ? "-dark" : ""
            try render(KokceSmallView(entry: entry, word: word), size: CGSize(width: 170, height: 170),
                       scheme: scheme, to: directory.appendingPathComponent("widget-small\(suffix).png"))
            try render(KokceMediumView(entry: entry, word: word), size: CGSize(width: 364, height: 170),
                       scheme: scheme, to: directory.appendingPathComponent("widget-medium\(suffix).png"))
            try render(KokceLargeView(entry: entry, word: word), size: CGSize(width: 364, height: 382),
                       scheme: scheme, to: directory.appendingPathComponent("widget-large\(suffix).png"))
            try render(KokceAccessoryView(word: word), size: CGSize(width: 172, height: 76),
                       scheme: scheme, accessory: true,
                       to: directory.appendingPathComponent("widget-lock\(suffix).png"))
        }

        print("SNAPSHOT_DIR=\(directory.path)")
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).count == 8)
    }

    /// Kilit ekranı ailesi sistemin zemininde beyaz çizilir; diğerleri parşömen
    /// zemin üstünde.
    private func render(_ view: some View,
                        size: CGSize,
                        scheme: ColorScheme,
                        accessory: Bool = false,
                        to url: URL) throws {
        let content = view
            .padding(accessory ? 4 : 14)
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .foregroundStyle(accessory ? Color.white : Color.primary)
            .background(accessory ? AnyShapeStyle(Color.black) : AnyShapeStyle(Theme.parchment))
            .clipShape(RoundedRectangle(cornerRadius: accessory ? 12 : 22))
            .environment(\.colorScheme, scheme)

        let renderer = ImageRenderer(content: content)
        renderer.scale = 3
        let image = try #require(renderer.uiImage)
        try #require(image.pngData()).write(to: url)
    }
}
