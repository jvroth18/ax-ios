import SwiftUI
import SwiftData

struct HistoryView: View {
    @Query(sort: \Interaction.date, order: .reverse) private var interactions: [Interaction]
    @Environment(\.modelContext) private var context

    var body: some View {
        List {
            ForEach(interactions) { interaction in
                VStack(alignment: .leading, spacing: 4) {
                    Text(interaction.transcript).font(.body)
                    if !interaction.toolSummary.isEmpty {
                        Text(interaction.toolSummary)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    Text(interaction.reply)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text(interaction.date, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 2)
            }
            .onDelete { offsets in
                offsets.map { interactions[$0] }.forEach(context.delete)
            }
        }
        .navigationTitle("History")
        .overlay {
            if interactions.isEmpty {
                ContentUnavailableView("No interactions yet", systemImage: "clock")
            }
        }
    }
}
