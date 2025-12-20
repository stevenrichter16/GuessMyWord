import Foundation

/// Provides non-repeating fun fact selection across multiple games in a session.
final class FunFactPicker {
    private let facts: [String: [String]]
    private let animals: [String]
    private var usedByAnimal: [String: Set<Int>] = [:]
    private var usedAnimals: [String] = []
    private var recent: [FactKey] = []
    private let recencyLimit: Int

    struct FactKey: Hashable {
        let animalId: String
        let index: Int
    }

    init(facts: [String: [String]], animals: [String], recencyLimit: Int = 5) {
        self.facts = facts
        self.animals = animals
        self.recencyLimit = recencyLimit
    }

    convenience init?(bundle: Bundle = .main, resourceName: String = "fun_facts") {
        guard let url = bundle.url(forResource: resourceName, withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: [String]] else {
            return nil
        }
        guard let ann = ANNDataStore(resourceName: "animals_ann") else {
            return nil
        }
        // Normalize animal names to lowercase so lookups match fun_facts keys.
        let names = ann.config.animals.map { $0.name.lowercased() }
        self.init(facts: dict, animals: names)
    }

    func nextFact() -> (animal: String, fact: String)? {
        guard !animals.isEmpty else { return nil }

        // Build a candidate list that prefers animals not used recently.
        let shuffled = animals.shuffled()
        let fresh = shuffled.filter { !usedAnimals.contains($0) }
        let candidates = fresh.isEmpty ? shuffled : fresh

        // First pass: only unused facts, honoring recency.
        for animal in candidates {
            if let selection = pickFact(for: animal, allowReset: false) {
                noteAnimalUse(animal)
                return selection
            }
        }
        // Second pass: allow reset of per-animal fact usage, still honoring recency order.
        for animal in candidates {
            if let selection = pickFact(for: animal, allowReset: true) {
                noteAnimalUse(animal)
                return selection
            }
        }
        return nil
    }

    func resetAll() {
        usedByAnimal.removeAll()
        usedAnimals.removeAll()
        recent.removeAll()
    }

    func resetAnimal(_ id: String) {
        usedByAnimal[id] = []
        recent.removeAll { $0.animalId == id }
    }

    private func pickFact(for animal: String, allowReset: Bool) -> (animal: String, fact: String)? {
        let key = animal.lowercased()
        guard let list = facts[key], !list.isEmpty else { return nil }
        let used = usedByAnimal[key] ?? []
        let availableIndices = Array(list.indices).filter { !used.contains($0) && !isRecent(animal: animal, index: $0) }

        if let idx = availableIndices.randomElement() {
            return record(animal: key, index: idx, fact: list[idx])
        }

        if allowReset {
            resetAnimal(key)
            guard let idx = Array(list.indices).randomElement() else { return nil }
            return record(animal: key, index: idx, fact: list[idx])
        }

        return nil
    }


    // at start of game, create empty list of animal's whose facts have been used
    // as fun fact is picked, check if animal name is in list
    // if animal name is in list, pick a different animal
    // if animal name is not in list, insertAt(0) animal name to list
    // if animal list is of length 10, remove last animal from list
    // call pickFact for animal at start of list (the animal that was just added to list)
    private func pickAnimal(recencyLimit: Int = 10) -> String {
        let shuffled = animals.shuffled()
        for animal in shuffled {
            if !usedAnimals.contains(animal) {
                usedAnimals.insert(animal, at: 0)
                if usedAnimals.count > recencyLimit {
                    usedAnimals.removeLast()
                }
                return animal
            }
        }
        return usedAnimals.first ?? animals.randomElement()!
    }

    private func record(animal: String, index: Int, fact: String) -> (animal: String, fact: String) {
        var used = usedByAnimal[animal] ?? []
        used.insert(index)
        usedByAnimal[animal] = used

        recent.append(FactKey(animalId: animal, index: index))
        if recent.count > recencyLimit {
            recent.removeFirst(recent.count - recencyLimit)
        }
        return (animal, fact)
    }

    private func isRecent(animal: String, index: Int) -> Bool {
        recent.contains(FactKey(animalId: animal, index: index))
    }

    private func noteAnimalUse(_ animal: String, limit: Int = 10) {
        usedAnimals.removeAll { $0 == animal }
        usedAnimals.insert(animal, at: 0)
        if usedAnimals.count > limit {
            usedAnimals.removeLast(usedAnimals.count - limit)
        }
    }
}
