import SwiftUI
import UIKit

@MainActor
struct GalleryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var store = GalleryStore()
    @State private var copiedMessage: String?

    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 16)]

    var body: some View {
        NavigationStack {
            ZStack {
                backgroundGradient
                    .ignoresSafeArea()
                content
            }
            .navigationTitle("Gallery")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .overlay(alignment: .top) {
                if let msg = copiedMessage {
                    Text(msg)
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(Color.black.opacity(0.8)))
                        .foregroundColor(.white)
                        .padding(.top, 12)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if store.items.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.largeTitle)
                    .foregroundColor(.secondary)
                Text("No avatars available.")
                    .font(.headline)
                Text("Add animal images to Assets to see them here.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .padding()
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("\(store.items.count) animals")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)

                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(store.items) { item in
                            card(for: item)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 24)
                }
            }
        }
    }

    @ViewBuilder
    private func card(for item: GalleryItem) -> some View {
        VStack(spacing: 8) {
            Text(item.name)
                .font(.headline)
                .multilineTextAlignment(.center)
                .foregroundColor(.primary)
            avatar(for: item)
                .frame(width: 88, height: 88)
                .contentShape(Rectangle())
                .onTapGesture {
                    copyAvatar(item)
                }
                .contextMenu {
                    Button {
                        copyAvatar(item)
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                    Button {
                        saveAvatar(item)
                    } label: {
                        Label("Save Image", systemImage: "square.and.arrow.down")
                    }
                }
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(cardFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                )
                .shadow(color: shadowColor.opacity(0.2), radius: 8, x: 0, y: 4)
        )
    }

    @ViewBuilder
    private func avatar(for item: GalleryItem) -> some View {
        if let asset = item.assetName, let image = UIImage(named: asset) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
                .shadow(color: shadowColor.opacity(0.2), radius: 6, x: 0, y: 3)
        } else {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(colorScheme == .dark ? 0.08 : 0.12))
                Image(systemName: "questionmark")
                    .font(.title2.weight(.bold))
                    .foregroundColor(.purple.opacity(0.9))
            }
        }
    }

    private var cardFill: Color {
        colorScheme == .dark ? Color(.secondarySystemBackground) : Color.white.opacity(0.95)
    }

    private var shadowColor: Color {
        colorScheme == .dark ? Color.black.opacity(0.5) : Color.black.opacity(0.12)
    }

    private var backgroundGradient: LinearGradient {
        if colorScheme == .dark {
            return LinearGradient(
                colors: [
                    Color(red: 0.1, green: 0.08, blue: 0.15),
                    Color(red: 0.15, green: 0.1, blue: 0.2),
                    Color(red: 0.2, green: 0.12, blue: 0.25)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            return LinearGradient(
                colors: [
                    Color(red: 0.98, green: 0.96, blue: 1.0),
                    Color(red: 0.96, green: 0.98, blue: 1.0),
                    Color(red: 0.94, green: 0.96, blue: 1.0)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private func copyAvatar(_ item: GalleryItem) {
        if let asset = item.assetName, let image = UIImage(named: asset) {
            UIPasteboard.general.image = image
            showCopied()
        }
    }

    private func saveAvatar(_ item: GalleryItem) {
        guard let asset = item.assetName, let image = UIImage(named: asset) else { return }
        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
        showCopied(message: "Saved")
    }

    private func showCopied(message: String = "Copied") {
        withAnimation(.easeInOut(duration: 0.2)) {
            copiedMessage = message
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            withAnimation(.easeInOut(duration: 0.2)) {
                copiedMessage = nil
            }
        }
    }
}
