import SwiftUI

struct FunFactsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var store = FunFactsStore()

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
            }
            Divider()
                .opacity(0.35)
            VStack(alignment: .leading, spacing: 8) {
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
}

#if DEBUG
struct FunFactsView_Previews: PreviewProvider {
    static var previews: some View {
        FunFactsView()
    }
}
#endif
