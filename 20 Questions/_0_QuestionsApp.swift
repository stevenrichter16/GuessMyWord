import SwiftUI
import AVKit
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
            TabView {
                if useLlamaMascotUI {
                    LlamaMascotContentView()
                        .tabItem {
                            Label("Game", systemImage: "sparkles")
                        }
                }
                BearVideoView()
                    .tabItem {
                        Label("Videos", systemImage: "film.stack")
                    }
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

private struct VideoClip: Identifiable {
    let id: String
    let url: URL
}

private struct BearVideoView: View {
    @State private var clips: [VideoClip] = []
    @State private var players: [String: AVPlayer] = [:]
    @State private var error: String?
    private let columns = [GridItem(.adaptive(minimum: 90), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Animal Videos")
                    .font(.title2.weight(.bold))

                if !clips.isEmpty {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                        ForEach(clips) { clip in
                            VStack(spacing: 6) {
                                if let player = players[clip.id] {
                                    VideoPlayer(player: player)
                                        .frame(width: 90, height: 90)
                                        .cornerRadius(8)
                                        .clipped()
                                        .allowsHitTesting(false)
                                        .onAppear { player.play() }
                                        .onDisappear { player.pause() }
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                                        )
                                } else {
                                    ProgressView()
                                        .frame(width: 50, height: 50)
                                }

                                Text(displayName(for: clip.id))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                } else if let error {
                    Text(error)
                        .foregroundStyle(.secondary)
                } else {
                    ProgressView("Loading videos…")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .onAppear { loadClipsIfNeeded() }
        .onDisappear { pauseAll() }
    }

    private func loadClipsIfNeeded() {
        guard clips.isEmpty else { return }
        guard let urls = Bundle.main.urls(forResourcesWithExtension: "mp4", subdirectory: nil) else {
            error = "No videos found in the bundle."
            return
        }

        let discovered = urls
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .map { VideoClip(id: $0.deletingPathExtension().lastPathComponent, url: $0) }

        clips = discovered
        if discovered.isEmpty {
            error = "No videos found in the bundle."
        } else {
            error = nil
        }

        discovered.forEach { clip in
            let player = makePlayer(for: clip)
            players[clip.id] = player
        }
    }

    private func makePlayer(for clip: VideoClip) -> AVPlayer {
        let player = AVPlayer(url: clip.url)
        player.actionAtItemEnd = .none
        player.isMuted = true
        NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: player.currentItem, queue: .main) { _ in
            player.seek(to: .zero)
            player.play()
        }
        return player
    }

    private func displayName(for id: String) -> String {
        id
            .replacingOccurrences(of: "_compressed", with: "")
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .capitalized
    }

    private func pauseAll() {
        players.values.forEach { $0.pause() }
    }
}

#if DEBUG
private struct AppRootPreview: View {
    private let useLlamaMascotUI = true

    var body: some View {
        TabView {
            if useLlamaMascotUI {
                LlamaMascotContentView()
                    .tabItem {
                        Label("Game", systemImage: "sparkles")
                    }
            }
            BearVideoView()
                .tabItem {
                    Label("Videos", systemImage: "film.stack")
                }
        }
    }
}

struct _0_QuestionsApp_Previews: PreviewProvider {
    static var previews: some View {
        AppRootPreview()
    }
}

struct BearVideoView_Previews: PreviewProvider {
    static var previews: some View {
        BearVideoView()
    }
}
#endif
