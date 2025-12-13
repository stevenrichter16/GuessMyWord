import Foundation

/// Provides non-repeating fun fact selection across multiple games in a session.
final class FunFactPicker {
    private let facts: [String: [String]]
    private var usedByAnimal: [String: Set<Int>] = [:]
    private var recent: [FactKey] = []
    private let recencyLimit: Int

    struct FactKey: Hashable {
        let animalId: String
        let index: Int
    }

    init(facts: [String: [String]], recencyLimit: Int = 5) {
        self.facts = facts
        self.recencyLimit = recencyLimit
    }

    convenience init?(bundle: Bundle = .main, resourceName: String = "fun_facts") {
        guard let url = bundle.url(forResource: resourceName, withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: [String]] else {
            return nil
        }
        self.init(facts: dict)
    }

    func nextFact() -> (animal: String, fact: String)? {
        let animals = Array(facts.keys)
        guard !animals.isEmpty else { return nil }

        // Prefer animals with unused facts; if none, allow reset within loop.
        let shuffled = animals.shuffled()
        for animal in shuffled {
            if let selection = pickFact(for: animal, allowReset: false) {
                return selection
            }
        }
        // If all exhausted, allow reset and try again.
        for animal in shuffled {
            if let selection = pickFact(for: animal, allowReset: true) {
                return selection
            }
        }
        return nil
    }

    func resetAll() {
        usedByAnimal.removeAll()
        recent.removeAll()
    }

    func resetAnimal(_ id: String) {
        usedByAnimal[id] = []
        recent.removeAll { $0.animalId == id }
    }

    private func pickFact(for animal: String, allowReset: Bool) -> (animal: String, fact: String)? {
        guard let list = facts[animal], !list.isEmpty else { return nil }
        let used = usedByAnimal[animal] ?? []
        let availableIndices = Array(list.indices).filter { !used.contains($0) && !isRecent(animal: animal, index: $0) }

        if let idx = availableIndices.randomElement() {
            return record(animal: animal, index: idx, fact: list[idx])
        }

        if allowReset {
            resetAnimal(animal)
            guard let idx = Array(list.indices).randomElement() else { return nil }
            return record(animal: animal, index: idx, fact: list[idx])
        }

        return nil
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
}
