import Foundation
import SwiftUI
#if canImport(FoundationModels)
import FoundationModels
#endif

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

private enum LLMLog {
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
    static let defaultCategories = [
        "kitchen items",
        "office items",
        "common animals",
        "tools",
        "fruits and vegetables",
        "toys",
        "electronics",
        "everyday carry"
    ]

    static let kitchenItems = ["toaster", "microwave", "blender", "frying pan", "pot", "spatula", "plate", "bowl", "cup", "mug", "cutting board", "kettle"]
    static let officeItems = ["laptop", "keyboard", "mouse", "monitor", "pen", "pencil", "notebook", "stapler", "tape dispenser", "scissors", "sticky notes", "desk lamp"]
    static let animalItems = ["cat", "dog", "horse", "cow", "chicken", "duck", "frog", "rabbit", "goldfish", "parrot"]
    static let toolItems = ["hammer", "screwdriver", "wrench", "pliers", "drill", "hand saw", "tape measure", "level", "paintbrush"]
    static let produceItems = ["apple", "banana", "orange", "carrot", "broccoli", "potato", "onion", "garlic", "bread loaf", "egg", "cheese"]
    static let toyItems = ["teddy bear", "soccer ball", "yo-yo", "kite", "doll", "puzzle", "toy car", "building blocks"]
    static let electronicItems = ["phone", "tablet", "remote control", "headphones", "flashlight", "camera", "smartwatch", "bluetooth speaker"]
    static let edcItems = ["backpack", "umbrella", "water bottle", "wallet", "sunglasses", "keychain"]

    static let defaultCanonicalItems: [String] = {
        kitchenItems + officeItems + animalItems + toolItems + produceItems + toyItems + electronicItems + edcItems
    }()

    private let fallbackQuestions = [
        "Is it electronic?",
        "Is it used in the kitchen?",
        "Is it an animal?",
        "Can it fit in a backpack?",
        "Is it mostly made of metal?",
        "Is it something you might find at an office?",
        "Is it used for eating or drinking?",
        "Does it require electricity to work?",
        "Is it alive?",
        "Is it bigger than a microwave?"
    ]

    private let client: LLMClient
    private let decoder = JSONDecoder()

    init(client: LLMClient = DefaultLLMClient.make()) {
        self.client = client
    }

    var isUsingFallback: Bool {
        client is FallbackLLMClient
    }

    func nextQuestion(context: PromptContext) async -> LLMAskResponse {
        let callStart = Date()
        LLMLog.log("nextQuestion start turn=\(context.turn) transcript=\(context.transcript.count) promptChars=\(PromptBuilder.askPrompt(context: context).count)")
        // If we're still using the stub client, rotate through canned questions so the UI advances.
        if client is FallbackLLMClient {
            let index = (context.turn - 1) % fallbackQuestions.count
            LLMLog.log("nextQuestion using fallback question index=\(index)")
            return LLMAskResponse(question: fallbackQuestions[index])
        }

        let prompt = PromptBuilder.askPrompt(context: context)
        do {
            let raw = try await client.complete(prompt: prompt)
            if let parsed: LLMAskResponse = try decode(jsonLike: raw) {
                LLMLog.log(String(format: "nextQuestion success in %.2fs", Date().timeIntervalSince(callStart)))
                return parsed
            }
        } catch {
            LLMLog.log("nextQuestion error: \(error)")
        }
        let index = (context.turn - 1) % fallbackQuestions.count
        LLMLog.log("nextQuestion falling back to canned question index=\(index)")
        return LLMAskResponse(question: fallbackQuestions[index])
    }

    func makeGuess(context: PromptContext) async -> LLMGuessResponse {
        // If we're still using the stub client, return a rotating fallback guess instead of the hardcoded toaster JSON.
        if client is FallbackLLMClient {
            let idx = max(0, min(context.canonicalItems.count - 1, (context.turn * 3) % context.canonicalItems.count))
            let guess = context.canonicalItems[idx]
            let confidence = min(0.9, 0.4 + Double(context.turn) * 0.05)
            let rationale = "Fallback guess while stub client is active."
            LLMLog.log("makeGuess using fallback guess idx=\(idx)")
            return LLMGuessResponse(guess: guess, confidence: confidence, rationale: rationale)
        }

        let prompt = PromptBuilder.guessPrompt(context: context)
        let callStart = Date()
        LLMLog.log("makeGuess start turn=\(context.turn) transcript=\(context.transcript.count) promptChars=\(prompt.count)")
        do {
            let raw = try await client.complete(prompt: prompt)
            if let parsed: LLMGuessResponse = try decode(jsonLike: raw) {
                LLMLog.log(String(format: "makeGuess success in %.2fs", Date().timeIntervalSince(callStart)))
                return LLMGuessResponse(
                    guess: parsed.guess,
                    confidence: clamp(parsed.confidence, min: 0, max: 1),
                    rationale: parsed.rationale
                )
            }
        } catch {
            LLMLog.log("makeGuess error: \(error)")
        }
        let idx = max(0, min(context.canonicalItems.count - 1, (context.turn * 3) % context.canonicalItems.count))
        let guess = context.canonicalItems[idx]
        let confidence = min(0.9, 0.4 + Double(context.turn) * 0.05)
        let rationale = "Placeholder guess based on the fallback engine. Plug in the real LLM for smarter results."
        LLMLog.log("makeGuess falling back to canned idx=\(idx)")
        return LLMGuessResponse(guess: guess, confidence: confidence, rationale: rationale)
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

/// Replace the implementation of `complete(prompt:)` with a call to the Foundation on-device model when available.
final class FallbackLLMClient: LLMClient {
    func complete(prompt: String) async throws -> String {
        if prompt.contains("\"guess\"") {
            return #"{"guess":"toaster","confidence":0.61,"rationale":"Common small kitchen appliance."}"#
        } else {
            return #"{"question":"Is it electronic?"}"#
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
