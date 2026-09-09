import SwiftUI

/// Minimal meal logging — free text, AI-parsed by the backend (§5.5). Photo entry
/// and the redacted-placeholder skeleton while parsing runs come next.
struct LogMealSheet: View {
    let isLogging: Bool
    let onSubmit: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("What did you eat?")
                .font(Typography.voice(22))
                .foregroundStyle(Palette.ink)

            TextField("e.g. chicken burrito bowl, large", text: $text, axis: .vertical)
                .font(Typography.data(16))
                .lineLimit(1 ... 3)
                .padding(14)
                .background(Palette.surfaceSunk, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .focused($focused)

            ActionButton(title: isLogging ? "Logging…" : "Log it") {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty, !isLogging else { return }
                onSubmit(trimmed)
            }

            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.background)
        .onAppear { focused = true }
    }
}

#Preview {
    Color.black.sheet(isPresented: .constant(true)) {
        LogMealSheet(isLogging: false) { _ in }
            .presentationDetents([.medium])
    }
}
