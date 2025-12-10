import SwiftUI
#if canImport(FoundationModels)
import FoundationModels
#endif

@main
struct _0_QuestionsApp: App {
    /// Set to true to use the Llama mascot UI variation
    private let useLlamaMascotUI = true

    init() {
        logModelStatus()
    }

    var body: some Scene {
        WindowGroup {
            if useLlamaMascotUI {
                LlamaMascotContentView()
            } else {
                ContentView()
            }
        }
    }

    private func logModelStatus() {
        #if canImport(FoundationModels)
        if case .available = SystemLanguageModel.default.availability {
            return
        }
        print("[LLM] FoundationModels present but on-device model is unavailable; using fallback stub.")
        #else
        print("[LLM] FoundationModels framework not available in this build (likely simulator SDK). Using fallback stub.")
        #endif
    }
}
