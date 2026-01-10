import Foundation

enum QuestionReliability {
    private static let config: SimPersonaConfig? = SimPersonaConfig.load()
    private static let tagWeights: [String: Double] = [
        "anatomy": 1.15,
        "appearance": 1.15,
        "taxonomy": 1.05,
        "ability": 1.0,
        "size": 1.0,
        "reproduction": 0.95,
        "habitat": 0.9,
        "behavior": 0.85,
        "diet": 0.85,
        "special": 0.9
    ]
    private static let averageTagConfidence: [String: Double] = {
        guard let config else { return [:] }
        var totals: [String: Double] = [:]
        var counts: [String: Double] = [:]
        for persona in config.personas.values {
            for (tag, value) in persona.questionTagConfidence {
                totals[tag, default: 0] += value
                counts[tag, default: 0] += 1
            }
        }
        var averages: [String: Double] = [:]
        for (tag, total) in totals {
            averages[tag] = total / (counts[tag] ?? 1)
        }
        return averages
    }()

    static func weight(questionId: QuestionId, turn: Int, unknownRate: Double, persona: SimPersonaConfig.Persona?) -> Double {
        let tags = tags(for: questionId)
        if tags.isEmpty { return 1.0 }

        let base = tags.map { tagWeights[$0] ?? 1.0 }.reduce(0, +) / Double(tags.count)
        let confidence = averageConfidence(for: tags, persona: persona)
        let confidenceWeight = confidence.map { 0.7 + (0.6 * $0) } ?? 1.0
        var weight = base * confidenceWeight

        let earlyFactor = earlyRoundFactor(turn: turn)
        weight = 1.0 + (weight - 1.0) * earlyFactor
        weight *= uncertaintyFactor(tags: tags, unknownRate: unknownRate)

        return clamp(weight, min: 0.6, max: 1.4)
    }

    private static func averageConfidence(for tags: [String], persona: SimPersonaConfig.Persona?) -> Double? {
        if let persona {
            let values = tags.compactMap { persona.questionTagConfidence[$0] }
            guard !values.isEmpty else { return nil }
            return values.reduce(0, +) / Double(values.count)
        }
        let values = tags.compactMap { averageTagConfidence[$0] }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private static func earlyRoundFactor(turn: Int) -> Double {
        let fadeTurns = 6
        let t = Double(fadeTurns - max(0, min(fadeTurns, turn - 1)))
        return max(0, min(1, t / Double(fadeTurns)))
    }

    private static func uncertaintyFactor(tags: [String], unknownRate: Double) -> Double {
        let scaled = (unknownRate - 0.15) / 0.35
        let intensity = max(0, min(1, scaled))
        guard intensity > 0 else { return 1.0 }

        var factor = 1.0
        if tags.contains("anatomy") || tags.contains("appearance") {
            factor *= 1.0 + (0.25 * intensity)
        }
        if tags.contains("diet") || tags.contains("behavior") || tags.contains("habitat") {
            factor *= 1.0 - (0.25 * intensity)
        }
        return factor
    }

    private static func tags(for questionId: QuestionId) -> [String] {
        if let tags = config?.questionTags[questionId], !tags.isEmpty {
            return tags
        }
        return inferredTags(for: questionId)
    }

    private static func inferredTags(for questionId: QuestionId) -> [String] {
        var tags: Set<String> = []

        let taxonomy: Set<String> = ["is_mammal", "is_bird", "is_reptile", "is_fish", "is_amphibian", "is_insect"]
        let diet: Set<String> = ["is_carnivore", "is_herbivore", "is_omnivore", "eats_insects", "is_scavenger", "is_predator", "eats_mostly_bamboo"]
        let behavior: Set<String> = [
            "is_nocturnal", "migrates_seasonally", "hibernates", "lives_in_groups", "rolls_into_ball", "is_flightless",
            "is_pet", "is_domesticated", "is_wild", "used_for_work_or_transport"
        ]
        let size: Set<String> = ["is_large", "is_tiny", "is_medium_sized", "is_bigger_than_sofa", "is_bigger_than_car"]
        let ability: Set<String> = ["can_fly"]
        let reproduction: Set<String> = ["lays_eggs"]
        let appearance: Set<String> = ["has_stripes", "has_spots", "is_brightly_colored", "has_long_neck", "has_wingspan_wide", "has_short_fur"]

        if taxonomy.contains(questionId) { tags.insert("taxonomy") }
        if diet.contains(questionId) { tags.insert("diet") }
        if behavior.contains(questionId) { tags.insert("behavior") }
        if size.contains(questionId) { tags.insert("size") }
        if ability.contains(questionId) { tags.insert("ability") }
        if reproduction.contains(questionId) { tags.insert("reproduction") }

        if questionId.hasPrefix("lives_in_") || questionId.hasPrefix("lives_on_") || questionId.hasPrefix("native_to_") {
            tags.insert("habitat")
        }

        if questionId.hasPrefix("has_") {
            if appearance.contains(questionId) {
                tags.insert("appearance")
            } else {
                tags.insert("anatomy")
            }
        } else if appearance.contains(questionId) {
            tags.insert("appearance")
        }

        return Array(tags)
    }

    private static func clamp(_ value: Double, min: Double, max: Double) -> Double {
        if value < min { return min }
        if value > max { return max }
        return value
    }
}
