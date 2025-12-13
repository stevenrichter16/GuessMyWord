import SwiftUI

struct FunFactsView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var store = FunFactsStore()

    var body: some View {
        NavigationStack {
            Group {
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
                    List {
                        ForEach(store.animals) { animal in
                            Section(header: sectionHeader(for: animal)) {
                                ForEach(Array(animal.facts.enumerated()), id: \.offset) { _, fact in
                                    Text(fact)
                                        .font(.body)
                                        .foregroundColor(.primary)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .accessibilityLabel("Fun fact about \(animal.name). \(fact)")
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
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
    private func sectionHeader(for animal: FunFactsAnimal) -> some View {
        HStack(spacing: 12) {
            if let asset = animal.assetName {
                Image(asset)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 50, height: 50)
                    .clipShape(Circle())
                    .accessibilityHidden(true)
            } else {
                ZStack {
                    Circle()
                        .fill(Color.primary.opacity(0.08))
                        .frame(width: 50, height: 50)
                    Image(systemName: "sparkles")
                        .foregroundColor(.primary)
                }
                .accessibilityHidden(true)
            }
            Text(animal.name)
                .font(.headline)
        }
        .padding(.vertical, 4)
    }
}

#if DEBUG
struct FunFactsView_Previews: PreviewProvider {
    static var previews: some View {
        FunFactsView()
    }
}
#endif
