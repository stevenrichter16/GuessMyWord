import Foundation

struct GalleryItem: Identifiable {
    let id: String
    let name: String
    let assetName: String?
}

@MainActor
final class GalleryStore: ObservableObject {
    @Published private(set) var items: [GalleryItem] = []

    init() {
        load()
    }

    private func load() {
        guard let ann = ANNDataStore(resourceName: "animals_ann") else {
            items = []
            return
        }
        let resolver = FunFactAssetResolver.self
        let mapped: [GalleryItem] = ann.config.animals.map { def in
            let asset = resolver.resolve(def.name)
            return GalleryItem(id: def.id, name: def.name, assetName: asset)
        }
        items = mapped.sorted { $0.name < $1.name }
    }
}
