import SwiftUI

struct HistoryView: View {
    @ObservedObject private var history = HistoryStore.shared

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                if history.events.isEmpty {
                    Text("No events yet")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                } else {
                    ForEach(history.events) { event in
                        eventRow(event)
                    }
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 6)
        }
        .frame(maxHeight: 420)
    }

    private func eventRow(_ event: DeviceEvent) -> some View {
        HStack(spacing: 9) {
            Image(systemName: event.connected ? "arrow.forward.circle.fill" : "minus.circle.fill")
                .font(.system(size: 13))
                .foregroundStyle(event.connected ? Color.green : Color.secondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(event.deviceName)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Text("\(event.connected ? "Connected" : "Disconnected") · \(event.connectionType) · \(event.date.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
    }
}
