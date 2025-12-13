import SwiftUI
import UIKit

@MainActor
struct FunFactsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var store: FunFactsStore
    @State private var collapsedIds: Set<String> = []
    @State private var copiedMessage: String?

    @MainActor
    init(store: FunFactsStore? = nil) {
        if let store {
            _store = StateObject(wrappedValue: store)
        } else {
            _store = StateObject(wrappedValue: FunFactsStore())
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                backgroundGradient
                    .ignoresSafeArea()
                content
            }
            .navigationTitle("Fun Facts")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .onAppear {
                seedCollapsed()
            }
            .onChange(of: store.animals.map(\.id)) { ids in
                seedCollapsed(with: ids)
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
        if store.animals.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "lightbulb.slash")
                    .font(.largeTitle)
                    .foregroundColor(.secondary)
                Text("No fun facts available.")
                    .font(.headline)
                Text("Add entries to fun_facts.json to see them here.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .padding()
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(store.animals.count) animals")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        HStack(spacing: 8) {
                            Button("Expand all") { withAnimation(.spring()) { expandAll() } }
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Capsule().fill(Color.primary.opacity(0.08)))
                            Button("Collapse all") { withAnimation(.spring()) { collapseAll() } }
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Capsule().fill(Color.primary.opacity(0.08)))
                        }
                    }
                    .padding(.horizontal)

                    LazyVStack(spacing: 14, pinnedViews: []) {
                        ForEach(store.animals) { animal in
                            card(for: animal)
                                .padding(.horizontal)
                        }
                    }
                    .padding(.bottom, 24)
                }
            }
        }
    }

    @ViewBuilder
    private func card(for animal: FunFactsAnimal) -> some View {
        let isCollapsed = collapsedIds.contains(animal.id)
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                avatar(for: animal)
                VStack(alignment: .leading, spacing: 2) {
                    Text(animal.name)
                        .font(.headline)
                    Text("\(animal.facts.count) fun fact\(animal.facts.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button {
                    withAnimation(.spring()) {
                        toggleCollapse(for: animal.id)
                    }
                } label: {
                    Image(systemName: isCollapsed ? "chevron.down" : "chevron.up")
                        .font(.headline.weight(.bold))
                        .foregroundColor(.secondary)
                        .padding(8)
                        .background(
                            Circle()
                                .fill(Color.primary.opacity(0.07))
                        )
                }
                .accessibilityLabel(isCollapsed ? "Expand \(animal.name)" : "Collapse \(animal.name)")
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.spring()) {
                    toggleCollapse(for: animal.id)
                }
            }
            if !isCollapsed {
                Divider()
                    .opacity(0.35)
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(animal.facts.enumerated()), id: \.offset) { index, fact in
                        HStack(alignment: .top, spacing: 8) {
                            Text("•")
                                .font(.headline)
                                .foregroundColor(.purple.opacity(0.8))
                                .accessibilityHidden(true)
                            Text(fact)
                                .font(.body)
                                .foregroundColor(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityLabel("Fun fact \(index + 1) about \(animal.name). \(fact)")
                        }
                        .contextMenu {
                            Button {
                                UIPasteboard.general.string = fact
                                showCopied()
                            } label: {
                                Label("Copy", systemImage: "doc.on.doc")
                            }
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(cardFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                )
                .shadow(color: shadowColor.opacity(0.25), radius: 10, x: 0, y: 6)
        )
    }

    @ViewBuilder
    private func avatar(for animal: FunFactsAnimal) -> some View {
        if let asset = animal.assetName {
            Image(asset)
                .resizable()
                .scaledToFit()
                .frame(width: 54, height: 54)
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
                .shadow(color: shadowColor.opacity(0.2), radius: 6, x: 0, y: 3)
                .accessibilityHidden(true)
        } else {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(colorScheme == .dark ? 0.08 : 0.15))
                    .frame(width: 54, height: 54)
                Image(systemName: "sparkles")
                    .font(.title3.weight(.semibold))
                    .foregroundColor(.purple.opacity(0.9))
            }
            .accessibilityHidden(true)
        }
    }

    private var cardFill: Color {
        colorScheme == .dark ? Color(.secondarySystemBackground) : Color.white.opacity(0.94)
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

    private func toggleCollapse(for id: String) {
        if collapsedIds.contains(id) {
            collapsedIds.remove(id)
        } else {
            collapsedIds.insert(id)
        }
    }

    private func collapseAll() {
        collapsedIds = Set(store.animals.map(\.id))
    }

    private func expandAll() {
        collapsedIds.removeAll()
    }

    private func seedCollapsed(with ids: [String]? = nil) {
        guard collapsedIds.isEmpty else { return }
        let allIds = ids ?? store.animals.map(\.id)
        collapsedIds = Set(allIds)
    }

    private func showCopied() {
        withAnimation(.easeInOut(duration: 0.2)) {
            copiedMessage = "Copied"
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            withAnimation(.easeInOut(duration: 0.2)) {
                copiedMessage = nil
            }
        }
    }
}
