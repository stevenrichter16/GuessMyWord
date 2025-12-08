import Foundation
import SwiftUI
import CoreML
#if canImport(FoundationModels)
import FoundationModels
#endif

// ANN config models for the local weights matrix.
typealias AnimalId = String
typealias QuestionId = String

struct AnimalsANNConfig: Codable {
    let version: Int
    let answerWeights: [String: Int]
    let animals: [AnimalDef]
    let questions: [QuestionDef]
    let weights: [AnimalId: [QuestionId: Int]]
}

struct AnimalDef: Codable {
    let id: AnimalId
    let name: String
}

struct QuestionDef: Codable {
    let id: QuestionId
    let text: String
}

final class ANNDataStore {
    let config: AnimalsANNConfig
    private(set) var weights: [AnimalId: [QuestionId: Int]]

    init(config: AnimalsANNConfig) {
        self.config = config
        self.weights = config.weights
    }

    convenience init?(resourceName: String = "animals_ann",
                      bundle: Bundle = .main) {
        let possible = [
            bundle.url(forResource: resourceName, withExtension: "json"),
            Bundle(for: LLMScaffolding.self).url(forResource: resourceName, withExtension: "json")
        ].compactMap { $0 }

        guard let url = possible.first else {
            print("ANNDataStore: could not find \(resourceName).json in bundle")
            return nil
        }
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            let config = try decoder.decode(AnimalsANNConfig.self, from: data)
            self.init(config: config)
        } catch {
            print("ANNDataStore: failed to load/parse JSON:", error)
            return nil
        }
    }

    func weight(for animalId: AnimalId, questionId: QuestionId) -> Int {
        weights[animalId]?[questionId] ?? 0
    }

    func setWeight(_ newValue: Int, for animalId: AnimalId, questionId: QuestionId) {
        var perAnimal = weights[animalId] ?? [:]
        perAnimal[questionId] = newValue
        weights[animalId] = perAnimal
    }

    func addToWeight(_ delta: Int, for animalId: AnimalId, questionId: QuestionId) {
        let current = weight(for: animalId, questionId: questionId)
        setWeight(current + delta, for: animalId, questionId: questionId)
    }
}

enum GamePhase: Equatable {
    case idle
    case asking
    case guessing
    case finished
}

enum Answer: String, CaseIterable, Identifiable {
    case yes = "Yes"
    case no = "No"
    case maybe = "Maybe"
    case notSure = "Not sure"

    var id: String { rawValue }

    var displayLabel: String { rawValue }

    var tint: Color {
        switch self {
        case .yes: return .green
        case .no: return .red
        case .maybe: return .orange
        case .notSure: return .blue
        }
    }
}

struct QAEntry: Identifiable {
    let id = UUID()
    let turn: Int
    let question: String
    let answer: Answer
}

struct PromptContext {
    let turn: Int
    let maxTurns: Int
    let transcript: [QAEntry]
    let allowedCategories: [String]
    let canonicalItems: [String]
    let hint: String?
}

struct LLMAskResponse: Codable {
    let question: String
}

struct LLMGuessResponse: Codable {
    let guess: String
    let confidence: Double
    let rationale: String
}

enum LLMLog {
    private static let enabled = true
    static func log(_ message: String) {
        guard enabled else { return }
        let ts = ISO8601DateFormatter.string(from: Date(), timeZone: .current, formatOptions: [.withInternetDateTime, .withFractionalSeconds])
        print("[LLM] \(ts) \(message)")
    }
}

struct PromptBuilder {
    static func askPrompt(context: PromptContext) -> String {
        """
        You are a 20-questions guesser. Allowed domains: \(context.allowedCategories.joined(separator: ", ")). Canonical items: \(context.canonicalItems.joined(separator: ", ")).
        Ask exactly one concise yes/no/maybe question under 80 chars. Do not include guesses inside the question. Avoid multiple questions.
        Turn \(context.turn) of \(context.maxTurns).
        Recent Q/A: \(formattedTranscript(context.transcript)).
        \(hintLine(from: context.hint))
        Output JSON only: {"question":"..."}
        """
    }

    static func guessPrompt(context: PromptContext) -> String {
        """
        You are a 20-questions guesser. Allowed domains: \(context.allowedCategories.joined(separator: ", ")). Canonical items: \(context.canonicalItems.joined(separator: ", ")).
        Provide your single best guess with confidence 0-1 and one-sentence rationale. Do not ask questions here.
        Turn \(context.turn) of \(context.maxTurns).
        Recent Q/A: \(formattedTranscript(context.transcript)).
        \(hintLine(from: context.hint))
        Output JSON only: {"guess":"item","confidence":0.72,"rationale":"..."}
        """
    }

    private static func formattedTranscript(_ transcript: [QAEntry]) -> String {
        transcript.suffix(6).map { "#\($0.turn) Q:\($0.question) A:\($0.answer.displayLabel)" }.joined(separator: " | ")
    }

    private static func hintLine(from hint: String?) -> String {
        guard let hint, !hint.isEmpty else { return "No extra hint." }
        return "Player hint: \(hint)"
    }
}

enum LLMOutputError: Error {
    case decodingFailed
}

protocol LLMClient {
    func complete(prompt: String) async throws -> String
}

/// Replace `FallbackLLMClient` with your Foundation model client (e.g., using `FoundationModels`).
final class LLMScaffolding {
    /// The animal dataset and feature metadata parsed from animals_20q.csv
    static let animalDataset = AnimalDataset.loadFromBundle()
    /// ANN weights/config seeded from animals_ann.json (patent-inspired ANN path).
    static let annStore = ANNDataStore(resourceName: "animals_ann")

    static let defaultCategories = ["animals"]

    static let defaultCanonicalItems: [String] = {
        if let dataset = animalDataset { return dataset.animals }
        if let ann = annStore { return ann.config.animals.map { $0.name } }
        return []
    }()

    private let fallbackQuestions = [
        // These map directly to the feature keys in animals_20q.csv
        "Is it a mammal?",
        "Is it commonly kept as a household pet?",
        "Is it mostly found in the wild (not usually living with humans)?",
        "Is it larger than an average adult human?",
        "Does it mainly eat meat?",
        "Does it mainly eat plants?",
        "Is it in the dog family (a type of canine)?",
        "Is it in the cat family (a type of feline)?",
        "Does it have obvious stripes on its body?",
        "Does it have a noticeably long neck compared to most animals?",
        "Is it a marsupial (carries its young in a pouch)?",
        "Does it mainly eat bamboo?",
        "Is it native to Australia?",
        "Does it spend most of its time in trees?",
        "Can it naturally fly?",
        "Does it live mostly in water?",
        "Is it a bird?",
        "Is it a reptile (like a snake, lizard, crocodile or turtle)?",
        "Does it have fur or hair?",
        "Does it have hooves instead of paws or claws?",
        "Has it been domesticated by humans (kept or bred by people)? Set this to 1 only for species that are fully domesticated; leave it 0 for wild species that are merely kept as pets or in captivity.",
        "Is it mostly active at night?",
        "Is it an amphibian (like a frog, toad or salamander)?",
        "Is it a fish?",
        "Does it usually lay eggs?",
        "Does it have a tail?",
        "Does it have noticeable spots on its body?",
        "Does it have horns or antlers?",
        "Does it have a hard shell covering part of its body?",
        "Does it have fins or flippers instead of legs?",
        "Does it eat both plants and animals?",
        "Does it eat insects as a major part of its diet?",
        "Does it often eat animals that are already dead (scavenge)?",
        "Is it a predator that hunts other animals?",
        "Is it mainly found in forests or jungles?",
        "Is it mainly found in open grasslands or savannas?",
        "Is it adapted to live in the desert or very dry areas?",
        "Is it typically found in cold or icy climates?",
        "Is it commonly found on farms as livestock or poultry?",
        "Does it usually live in groups, herds, packs or flocks?",
        "Does it migrate long distances during certain seasons?",
        "Does it hibernate or sleep for long periods in winter?",
        "Is it venomous (can inject venom through fangs, stingers, etc.)?",
        "Is it commonly used by humans for work or transport (like riding or carrying loads)?"
    ]

    private let client: LLMClient
    private let decoder = JSONDecoder()
    private let animalEngine: AnimalQuestionEngine?

    init(client: LLMClient = DefaultLLMClient.make()) {
        self.client = client
        if let dataset = LLMScaffolding.animalDataset {
            animalEngine = AnimalQuestionEngine(dataset: dataset)
        } else {
            animalEngine = nil
        }
    }

    var isUsingFallback: Bool {
        if animalEngine != nil { return false }
        return client is FallbackLLMClient
    }

    func nextQuestion(context: PromptContext) async -> LLMAskResponse {
        if let engine = animalEngine {
            let question = engine.nextQuestion(transcript: context.transcript)
            LLMLog.log("Q: \(question)")
            return LLMAskResponse(question: question)
        }

        let callStart = Date()
        LLMLog.log("nextQuestion start turn=\(context.turn) transcript=\(context.transcript.count) promptChars=\(PromptBuilder.askPrompt(context: context).count)")
        // If we're still using the stub client, rotate through canned questions so the UI advances.
        if client is FallbackLLMClient {
            let index = (context.turn - 1) % fallbackQuestions.count
            LLMLog.log("nextQuestion using fallback question index=\(index)")
            let q = fallbackQuestions[index]
            LLMLog.log("Q: \(q)")
            return LLMAskResponse(question: q)
        }

        let prompt = PromptBuilder.askPrompt(context: context)
        do {
            let raw = try await client.complete(prompt: prompt)
            if let parsed: LLMAskResponse = try decode(jsonLike: raw) {
                LLMLog.log(String(format: "nextQuestion success in %.2fs", Date().timeIntervalSince(callStart)))
                LLMLog.log("Q: \(parsed.question)")
                return parsed
            }
        } catch {
            LLMLog.log("nextQuestion error: \(error)")
        }
        let index = (context.turn - 1) % fallbackQuestions.count
        LLMLog.log("nextQuestion falling back to canned question index=\(index)")
        let q = fallbackQuestions[index]
        LLMLog.log("Q: \(q)")
        return LLMAskResponse(question: q)
    }

    func makeGuess(context: PromptContext) async -> LLMGuessResponse {
        if let engine = animalEngine {
            let guess = engine.makeGuess(transcript: context.transcript)
            LLMLog.log("Guess: \(guess.guess) (\(Int(guess.confidence * 100))%) \(guess.rationale)")
            return guess
        }

        // If we're still using the stub client, return a rotating fallback guess instead of the hardcoded toaster JSON.
        if client is FallbackLLMClient {
            let idx = max(0, min(context.canonicalItems.count - 1, (context.turn * 3) % context.canonicalItems.count))
            let guess = context.canonicalItems[idx]
            let confidence = min(0.9, 0.4 + Double(context.turn) * 0.05)
            let rationale = "Fallback guess while stub client is active."
            LLMLog.log("makeGuess using fallback guess idx=\(idx)")
            let response = LLMGuessResponse(guess: guess, confidence: confidence, rationale: rationale)
            LLMLog.log("Guess: \(response.guess) (\(Int(response.confidence * 100))%) \(response.rationale)")
            return response
        }

        let prompt = PromptBuilder.guessPrompt(context: context)
        let callStart = Date()
        LLMLog.log("makeGuess start turn=\(context.turn) transcript=\(context.transcript.count) promptChars=\(prompt.count)")
        do {
            let raw = try await client.complete(prompt: prompt)
            if let parsed: LLMGuessResponse = try decode(jsonLike: raw) {
                LLMLog.log(String(format: "makeGuess success in %.2fs", Date().timeIntervalSince(callStart)))
                let response = LLMGuessResponse(
                    guess: parsed.guess,
                    confidence: clamp(parsed.confidence, min: 0, max: 1),
                    rationale: parsed.rationale
                )
                LLMLog.log("Guess: \(response.guess) (\(Int(response.confidence * 100))%) \(response.rationale)")
                return response
            }
        } catch {
            LLMLog.log("makeGuess error: \(error)")
        }
        let idx = max(0, min(context.canonicalItems.count - 1, (context.turn * 3) % context.canonicalItems.count))
        let guess = context.canonicalItems[idx]
        let confidence = min(0.9, 0.4 + Double(context.turn) * 0.05)
        let rationale = "Placeholder guess based on the fallback engine. Plug in the real LLM for smarter results."
        LLMLog.log("makeGuess falling back to canned idx=\(idx)")
        let response = LLMGuessResponse(guess: guess, confidence: confidence, rationale: rationale)
        LLMLog.log("Guess: \(response.guess) (\(Int(response.confidence * 100))%) \(response.rationale)")
        return response
    }

    func buildAskPrompt(context: PromptContext) -> String {
        PromptBuilder.askPrompt(context: context)
    }

    func buildGuessPrompt(context: PromptContext) -> String {
        PromptBuilder.guessPrompt(context: context)
    }

    private func decode<T: Decodable>(jsonLike: String) throws -> T? {
        // Try direct decode first.
        if let data = jsonLike.data(using: .utf8), let decoded = try? decoder.decode(T.self, from: data) {
            return decoded
        }
        // Try to extract the first JSON object from the string.
        guard let json = extractJSONObject(from: jsonLike), let data = json.data(using: .utf8) else {
            LLMLog.log("decode failed to extract JSON from: \(jsonLike.prefix(200))")
            throw LLMOutputError.decodingFailed
        }
        LLMLog.log("decode attempting parsed JSON fragment length \(json.count)")
        return try decoder.decode(T.self, from: data)
    }

    private func extractJSONObject(from text: String) -> String? {
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}") else { return nil }
        let jsonSubstring = text[start...end]
        return String(jsonSubstring)
    }

    private func clamp(_ value: Double, min: Double, max: Double) -> Double {
        Swift.max(min, Swift.min(max, value))
    }
}

private extension Collection {
    var only: Element? { count == 1 ? first : nil }
}

/// Replace the implementation of `complete(prompt:)` with a call to the Foundation on-device model when available.
final class FallbackLLMClient: LLMClient {
    func complete(prompt: String) async throws -> String {
        if prompt.contains("\"guess\"") {
            return #"{"guess":"dog","confidence":0.42,"rationale":"Common, high-prior animal guess."}"#
        } else {
            return #"{"question":"Is it a mammal?"}"#
        }
    }
}

private enum DefaultLLMClient {
    static func make() -> LLMClient {
        #if targetEnvironment(simulator)
        let client: LLMClient = FoundationModelClient()
        LLMLog.log("Using client: FoundationModels (simulator)")
        return client
        #else
        #if canImport(FoundationModels)
        let availability = SystemLanguageModel.default.availability
        LLMLog.log("FoundationModels availability: \(availability)")
        if case .available = availability {
            let client = FoundationModelClient()
            LLMLog.log("Using client: FoundationModels")
            return client
        }
        LLMLog.log("FoundationModels unavailable: \(availability)")
        #endif
        let client: LLMClient = FoundationModelClient()
        LLMLog.log("Forcing FoundationModels client even when unavailable; expect errors if model cannot load.")
        return client
        #endif
    }
}

#if canImport(FoundationModels)
/// Foundation model client using the FoundationModels package.
/// Adjust generation parameters to fit your app and device constraints.
final class FoundationModelClient: LLMClient {
    private let session: LanguageModelSession
    private let prewarmTask: Task<Void, Never>

    init(model: SystemLanguageModel = .default, options: GenerationOptions = .init()) {
        LLMLog.log("Creating FoundationModelClient; availability=\(model.availability)")
        self.session = LanguageModelSession(model: model, instructions: nil)
        self.options = options
        self.prewarmTask = Task { [session] in
            LLMLog.log("Prewarm start")
            let start = Date()
            do {
                try await session.prewarm()
                LLMLog.log(String(format: "Prewarm finished in %.2fs", Date().timeIntervalSince(start)))
            } catch {
                LLMLog.log(String(format: "Prewarm failed in %.2fs error: %@", Date().timeIntervalSince(start), String(describing: error)))
            }
        }
    }

    private let options: GenerationOptions

    func complete(prompt: String) async throws -> String {
        LLMLog.log("Respond start; prompt length \(prompt.count)")
        _ = await prewarmTask.result
        let start = Date()
        let response = try await session.respond(to: prompt, options: options)
        LLMLog.log(String(format: "Respond finished in %.2fs; content length %d", Date().timeIntervalSince(start), response.content.count))
        return response.content
    }
}
#endif

// MARK: - Animal dataset + Core ML integration

public struct AnimalFeature {
    let key: String
    let question: String
}

struct AnimalDataset {
    let features: [AnimalFeature]
    let featureOrder: [String]
    let animals: [String]
    let rows: [String: [String: Double]]

    static let featureQuestions: [String: String] = [
        "is_mammal": "Is it a mammal?",
        "is_pet": "Is it commonly kept as a household pet?",
        "is_wild": "Is it mostly found in the wild (not usually living with humans)?",
        "is_large": "Is it larger than an average adult human?",
        "is_carnivore": "Does it mainly eat meat?",
        "is_herbivore": "Does it mainly eat plants?",
        "is_canine": "Is it in the dog family (a type of canine)?",
        "is_feline": "Is it in the cat family (a type of feline)?",
        "has_stripes": "Does it have obvious stripes on its body?",
        "has_long_neck": "Does it have a noticeably long neck compared to most animals?",
        "is_marsupial": "Is it a marsupial (carries its young in a pouch)?",
        "eats_mostly_bamboo": "Does it mainly eat bamboo?",
        "native_to_australia": "Is it native to Australia?",
        "lives_in_trees": "Does it spend most of its time in trees?",
        "can_fly": "Can it naturally fly?",
        "lives_in_water": "Does it live mostly in water?",
        "is_bird": "Is it a bird?",
        "is_reptile": "Is it a reptile (like a snake, lizard, crocodile or turtle)?",
        "has_fur_or_hair": "Does it have fur or hair?",
        "has_hooves": "Does it have hooves instead of paws or claws?",
        "is_domesticated": "Has it been domesticated by humans (kept or bred by people)? Set this to 1 only for species that are fully domesticated; leave it 0 for wild species that are merely kept as pets or in captivity.",
        "is_nocturnal": "Is it mostly active at night?",
        "is_amphibian": "Is it an amphibian (like a frog, toad or salamander)?",
        "is_fish": "Is it a fish?",
        "lays_eggs": "Does it usually lay eggs?",
        "has_tail": "Does it have a tail?",
        "has_spots": "Does it have noticeable spots on its body?",
        "has_horns_or_antlers": "Does it have horns or antlers?",
        "has_shell": "Does it have a hard shell covering part of its body?",
        "has_fins_or_flippers": "Does it have fins or flippers instead of legs?",
        "is_omnivore": "Does it eat both plants and animals?",
        "eats_insects": "Does it eat insects as a major part of its diet?",
        "is_scavenger": "Does it often eat animals that are already dead (scavenge)?",
        "is_predator": "Is it a predator that hunts other animals?",
        "lives_in_forest_or_jungle": "Is it mainly found in forests or jungles?",
        "lives_in_grassland_or_savanna": "Is it mainly found in open grasslands or savannas?",
        "lives_in_desert": "Is it adapted to live in the desert or very dry areas?",
        "lives_in_cold_climate": "Is it typically found in cold or icy climates?",
        "lives_on_farm": "Is it commonly found on farms as livestock or poultry?",
        "lives_in_groups": "Does it usually live in groups, herds, packs or flocks?",
        "migrates_seasonally": "Does it migrate long distances during certain seasons?",
        "hibernates": "Does it hibernate or sleep for long periods in winter?",
        "is_venomous": "Is it venomous (can inject venom through fangs, stingers, etc.)?",
        "used_for_work_or_transport": "Is it commonly used by humans for work or transport (like riding or carrying loads)?"
    ]

    static func loadFromBundle() -> AnimalDataset? {
        let bundle = Bundle.main
        let possibleURLs = [
            bundle.url(forResource: "animals_20q", withExtension: "csv"),
            Bundle(for: LLMScaffolding.self).url(forResource: "animals_20q", withExtension: "csv"),
            URL(fileURLWithPath: "animals_20q.csv", relativeTo: URL(fileURLWithPath: #file).deletingLastPathComponent())
        ].compactMap { $0 }

        guard let url = possibleURLs.first(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
            print("[AnimalDataset] animals_20q.csv not found in bundle or adjacent to code.")
            return nil
        }

        do {
            let raw = try String(contentsOf: url)
            let lines = raw.split(whereSeparator: \.isNewline).map(String.init).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            guard let headerLine = lines.first else { return nil }
            let headers = headerLine.split(separator: ",").map(String.init)
            guard headers.first == "Animal" else {
                print("[AnimalDataset] First column must be Animal")
                return nil
            }
            let featureOrder = Array(headers.dropFirst())

            let features: [AnimalFeature] = featureOrder.map { key in
                let q = featureQuestions[key] ?? key
                return AnimalFeature(key: key, question: q)
            }

            var rows: [String: [String: Double]] = [:]
            var animals: [String] = []
            for line in lines.dropFirst() {
                let cols = line.split(separator: ",").map(String.init)
                guard cols.count == headers.count else { continue }
                let name = cols[0]
                animals.append(name)
                var values: [String: Double] = [:]
                for (idx, key) in featureOrder.enumerated() {
                    values[key] = Double(cols[idx + 1]) ?? 0
                }
                rows[name] = values
            }

            return AnimalDataset(features: features, featureOrder: featureOrder, animals: animals, rows: rows)
        } catch {
            print("[AnimalDataset] Failed to read animals_20q.csv: \(error)")
            return nil
        }
    }

    func answer(for animal: String, featureKey: String) -> Answer? {
        guard let values = rows[animal], let val = values[featureKey] else { return nil }
        if val == 1 { return .yes }
        if val == 0 { return .no }
        return .maybe
    }
}

private final class AnimalModelWrapper {
    static let shared = AnimalModelWrapper()

    private(set) var model: MLModel?

    private init() {
        let config = MLModelConfiguration()
        let bundle = Bundle.main
        let candidates = [
            bundle.url(forResource: "Animal20Q", withExtension: "mlmodelc"),
            bundle.url(forResource: "Animal20Q", withExtension: "mlmodel"),
            Bundle(for: LLMScaffolding.self).url(forResource: "Animal20Q", withExtension: "mlmodelc"),
            Bundle(for: LLMScaffolding.self).url(forResource: "Animal20Q", withExtension: "mlmodel")
        ].compactMap { $0 }

        for url in candidates {
            if let loaded = try? MLModel(contentsOf: url, configuration: config) {
                model = loaded
                return
            }
        }
        print("[AnimalModelWrapper] Could not load Animal20Q.mlmodel from bundle.")
    }

    func predict(features: [String: Double], featureOrder: [String]) -> (label: String, probabilities: [String: Double])? {
        guard let model else { return nil }
        let dict = Dictionary(uniqueKeysWithValues: featureOrder.map { key in
            (key, MLFeatureValue(double: features[key] ?? 0))
        })
        guard let provider = try? MLDictionaryFeatureProvider(dictionary: dict),
              let output = try? model.prediction(from: provider) else {
            return nil
        }

        let label = output.featureValue(for: "classLabel")?.stringValue
            ?? output.featureValue(for: "label")?.stringValue
            ?? ""

        var probs: [String: Double] = [:]
        if let dict = output.featureValue(for: "classProbability")?.dictionaryValue as? [String: NSNumber] {
            probs = dict.mapValues { $0.doubleValue }
        } else if let dict = output.featureValue(for: "classScores")?.dictionaryValue as? [String: NSNumber] {
            probs = dict.mapValues { $0.doubleValue }
        }

        return (label: label, probabilities: probs)
    }
}

struct AnimalQuestionEngine {
    struct AnswerIndex {
        let yes: Set<String>
        let no: Set<String>
        let unknown: Set<String>
    }

    struct QuestionScore {
        let feature: AnimalFeature
        let infoGain: Double
        let yesCount: Int
        let noCount: Int
        let unknownCount: Int
    }

    let dataset: AnimalDataset
    private let featureLookup: [String: AnimalFeature]
    private let featureAnswerIndex: [String: AnswerIndex]

    init(dataset: AnimalDataset) {
        self.dataset = dataset
        self.featureLookup = Dictionary(uniqueKeysWithValues: dataset.features.map { ($0.question.lowercased(), $0) })
        var index: [String: AnswerIndex] = [:]
        for feature in dataset.features {
            var yes = Set<String>()
            var no = Set<String>()
            var unknown = Set<String>()
            for animal in dataset.animals {
                if let ans = dataset.answer(for: animal, featureKey: feature.key) {
                    switch ans {
                    case .yes: yes.insert(animal)
                    case .no: no.insert(animal)
                    default: unknown.insert(animal)
                    }
                } else {
                    unknown.insert(animal)
                }
            }
            index[feature.key] = AnswerIndex(yes: yes, no: no, unknown: unknown)
        }
        self.featureAnswerIndex = index
    }

    func nextQuestion(transcript: [QAEntry]) -> String {
        let askedKeys = Set(transcript.compactMap { featureKey(for: $0.question) })
        // Allow a small amount of contradiction in the transcript so we don't drop the true animal
        // after a single misclick or mistaken answer.
        let candidates = tolerantCandidates(from: transcript)
        let candidateSet = Set(candidates)

        var bestFeature: AnimalFeature?
        var bestScore: Int = Int.max
        var bestSpecificity: Double = -Double.infinity

        for feature in dataset.features where !askedKeys.contains(feature.key) {
            let counts = counts(for: feature.key, candidates: candidates, candidateSet: candidateSet)
            let yes = counts.yes
            let no = counts.no
            let total = yes + no
            // Skip attributes that cannot split the remaining candidates (all yes or all no).
            if total == 0 || yes == 0 || no == 0 { continue }
            let splitScore = abs(yes - no)
            let specificity = variance(of: [Double(yes), Double(no), Double(counts.unknown)])
            if splitScore < bestScore || (splitScore == bestScore && specificity > bestSpecificity) {
                bestScore = splitScore
                bestFeature = feature
                bestSpecificity = specificity
            }
        }

        if let feature = bestFeature {
            return feature.question
        }
        return dataset.features.first(where: { !askedKeys.contains($0.key) })?.question ?? "Out of questions."
    }

    func makeGuess(transcript: [QAEntry]) -> LLMGuessResponse {
        let askedKeys = Set(transcript.compactMap { featureKey(for: $0.question) })
        var candidates = candidatePool(from: transcript)

        // If only one candidate remains, guess it immediately.
        if let sole = candidates.only {
            let rationale = "Only one candidate fits all answered attributes."
            return LLMGuessResponse(guess: sole, confidence: 1.0, rationale: rationale)
        }

        var featureValues: [String: Double] = [:]
        for feature in dataset.features {
            let ans = transcript.last(where: { featureKey(for: $0.question) == feature.key })?.answer
            switch ans {
            case .some(.yes):
                featureValues[feature.key] = 1
            case .some(.no):
                featureValues[feature.key] = 0
            default:
                // Unknown/not sure/unanswered: use neutral 0.5 so we don't force a no.
                featureValues[feature.key] = 0.5
            }
        }

        if let prediction = AnimalModelWrapper.shared.predict(features: featureValues, featureOrder: dataset.featureOrder) {
            let top = prediction.label.isEmpty ? (candidates.first ?? "unknown") : prediction.label
            // Enforce candidate filtering: choose the top-probability label within remaining candidates.
            let candidateProbs = candidates.compactMap { name -> (String, Double)? in
                guard let p = prediction.probabilities[name] else { return nil }
                return (name, p)
            }
            // Log top candidates and their probabilities
            let sorted = candidateProbs.sorted { $0.1 > $1.1 }
            let preview = sorted.prefix(5).map { "\($0.0): \(String(format: "%.2f", $0.1))" }.joined(separator: ", ")
            if !preview.isEmpty {
                LLMLog.log("Candidate scores: \(preview)")
            }

            let filtered = sorted.first
            let chosen = filtered?.0 ?? (candidates.contains(top) ? top : candidates.first ?? top)
            var confidence = filtered?.1 ?? (prediction.probabilities[chosen] ?? 0.0)
            // If all probabilities are zero/missing, fall back to a uniform-ish confidence.
            if confidence == 0, !candidates.isEmpty {
                confidence = 1.0 / Double(candidates.count)
            }
            let rationale = "Core ML decision tree based on answered attributes (\(askedKeys.count) answered)."
            return LLMGuessResponse(guess: chosen, confidence: confidence, rationale: rationale)
        }

        let guess = candidates.first ?? "unknown"
        return LLMGuessResponse(guess: guess, confidence: 0.25, rationale: "Guess based on remaining candidates.")
    }

    func featureKey(for question: String) -> String? {
        featureLookup[question.lowercased()]?.key
    }

    private func candidateScores(from transcript: [QAEntry]) -> [(animal: String, mismatches: Int)] {
        dataset.animals.compactMap { animal in
            guard let facts = dataset.rows[animal] else { return nil }
            var mismatches = 0
            for entry in transcript {
                guard let key = featureKey(for: entry.question), let value = facts[key] else { continue }
                switch entry.answer {
                case .yes:
                    if value < 0.5 { mismatches += 1 }
                case .no:
                    if value > 0.5 { mismatches += 1 }
                default:
                    continue
                }
            }
            return (animal: animal, mismatches: mismatches)
        }
        .sorted { $0.mismatches < $1.mismatches }
    }

    private func candidatePool(from transcript: [QAEntry]) -> [String] {
        let scores = candidateScores(from: transcript)
        guard let best = scores.first?.mismatches else { return dataset.animals }
        let maxMismatch = best + 1 // allow at most one contradiction compared to the leading candidates
        var candidates = scores.filter { $0.mismatches <= maxMismatch }.map { $0.animal }

        // Hard constraints first: drop non-flyers (and then non-furry flyers if applicable).
        if let flyAnswer = transcript.first(where: { featureKey(for: $0.question) == "can_fly" })?.answer, flyAnswer == .yes {
            let flyers = candidates.filter { dataset.rows[$0]?["can_fly"] == 1 }
            if !flyers.isEmpty { candidates = flyers }
            if let furAnswer = transcript.first(where: { featureKey(for: $0.question) == "has_fur_or_hair" })?.answer, furAnswer == .yes {
                let furryFlyers = candidates.filter { dataset.rows[$0]?["has_fur_or_hair"] == 1 }
                if !furryFlyers.isEmpty { candidates = furryFlyers }
            }
        }

        // If contradictions emptied the candidate list, fall back to all animals (or flyers if required).
        if candidates.isEmpty {
            if let flyAnswer = transcript.first(where: { featureKey(for: $0.question) == "can_fly" })?.answer, flyAnswer == .yes {
                let flyers = dataset.animals.filter { dataset.rows[$0]?["can_fly"] == 1 }
                candidates = flyers.isEmpty ? dataset.animals : flyers
            } else {
                candidates = dataset.animals
            }
        }

        return candidates
    }

    private func tolerantCandidates(from transcript: [QAEntry]) -> [String] {
        candidatePool(from: transcript)
    }

    /// Score each unasked question by expected information gain over the remaining candidates.
    func scoreQuestions(transcript: [QAEntry]) -> [QuestionScore] {
        let askedKeys = Set(transcript.compactMap { featureKey(for: $0.question) })
        let candidates = tolerantCandidates(from: transcript)
        let candidateSet = Set(candidates)
        let total = Double(candidates.count)
        guard total > 0 else { return [] }
        let baseEntropy = total <= 1 ? 0 : log2(total)

        var scores: [QuestionScore] = []
        for feature in dataset.features where !askedKeys.contains(feature.key) {
            let counts = counts(for: feature.key, candidates: candidates, candidateSet: candidateSet)
            let yes = counts.yes
            let no = counts.no
            let unknown = counts.unknown

            let branches = [yes, no, unknown]
            let expectedEntropy = branches.reduce(0.0) { partial, count in
                if count == 0 { return partial }
                let p = Double(count) / total
                let branchEntropy = count <= 1 ? 0 : log2(Double(count))
                return partial + p * branchEntropy
            }

            let gain = max(0, baseEntropy - expectedEntropy)
            scores.append(QuestionScore(feature: feature, infoGain: gain, yesCount: yes, noCount: no, unknownCount: unknown))
        }

        return scores.sorted { $0.infoGain > $1.infoGain }
    }

    private func counts(for featureKey: String, candidates: [String], candidateSet: Set<String>? = nil) -> (yes: Int, no: Int, unknown: Int) {
        guard let idx = featureAnswerIndex[featureKey] else { return (0, 0, 0) }
        let candidatesSet = candidateSet ?? Set(candidates)
        let yes = idx.yes.reduce(0) { $0 + (candidatesSet.contains($1) ? 1 : 0) }
        let no = idx.no.reduce(0) { $0 + (candidatesSet.contains($1) ? 1 : 0) }
        let unknown = idx.unknown.reduce(0) { $0 + (candidatesSet.contains($1) ? 1 : 0) }
        return (yes, no, unknown)
    }

    private func variance(of values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.reduce(0) { $0 + pow($1 - mean, 2) } / Double(values.count)
        return variance
    }
}
