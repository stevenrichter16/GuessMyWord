import Foundation

/// Persona simulation configuration for generating more realistic synthetic answers.
/// Loads from sim_personas.json in the main bundle.
struct SimPersonaConfig: Codable {
    struct Persona: Codable {
        let baseUnknown: Double
        let baseMistake: Double
        let yesBias: Double
        let riskiness: Double
        let questionTagConfidence: [String: Double]
        let tierMultiplier: [String: Double]
        let clusterBias: Bool
    }

    struct ConfusionCluster: Codable {
        let name: String
        let members: [String]
        let biasWrongToward: [String]
    }

    let questionTags: [String: [String]]
    let confusionClusters: [ConfusionCluster]
    let familiarityTiers: [String: [String]]
    let personas: [String: Persona]

    static func load(from bundle: Bundle = .main, resourceName: String = "sim_personas") -> SimPersonaConfig? {
        let candidates = [
            bundle.url(forResource: resourceName, withExtension: "json"),
            Bundle(for: LLMScaffolding.self).url(forResource: resourceName, withExtension: "json")
        ].compactMap { $0 }

        guard let url = candidates.first else { return nil }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(SimPersonaConfig.self, from: data)
        } catch {
            print("SimPersonaConfig: failed to load/parse \(resourceName).json:", error)
            return nil
        }
    }
}
