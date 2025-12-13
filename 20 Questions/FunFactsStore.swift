import Foundation
import SwiftUI
import UIKit

struct FunFactsAnimal: Identifiable {
    let id: String
    let name: String
    let facts: [String]
    let assetName: String?
}

enum FunFactAssetResolver {
    static func resolve(_ animalName: String) -> String? {
        let normalized = animalName
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        var candidates: [String] = [
            normalized,
            normalized.replacingOccurrences(of: " ", with: "_"),
            normalized.replacingOccurrences(of: "-", with: "_")
        ]
        let aliases: [String: String] = [
            "hippopotamus": "hippo",
            "hippo": "hippo"
        ]
        if let mapped = aliases[normalized] {
            candidates.insert(mapped, at: 0)
        }
        for name in candidates {
            if UIImage(named: name) != nil {
                return name
            }
        }
        return nil
    }
}

@MainActor
final class FunFactsStore: ObservableObject {
    @Published private(set) var animals: [FunFactsAnimal] = []

    init() {
        load()
    }

    private func load() {
        guard let url = Bundle.main.url(forResource: "fun_facts", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: [String]] else {
            animals = []
            return
        }

        let names = loadAnimalNames()
        let entries: [FunFactsAnimal] = dict.compactMap { key, facts in
            let cleanedFacts = facts
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            guard !cleanedFacts.isEmpty else { return nil }
            let displayName = names[key.lowercased()] ?? names[key] ?? key.replacingOccurrences(of: "_", with: " ").capitalized
            let asset = FunFactAssetResolver.resolve(displayName)
            return FunFactsAnimal(id: key, name: displayName, facts: cleanedFacts, assetName: asset)
        }
        .sorted { $0.name < $1.name }

        animals = entries
    }

    private func loadAnimalNames() -> [String: String] {
        guard let store = ANNDataStore(resourceName: "animals_ann") else { return [:] }
        var map: [String: String] = [:]
        for animal in store.config.animals {
            map[animal.id.lowercased()] = animal.name
            map[animal.name.lowercased()] = animal.name
        }
        return map
    }
}
