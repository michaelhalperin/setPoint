import PhotosUI
import SwiftUI

/// Meal logging (§5.5) — free text, a photo, or both. When the user submits, what
/// they wrote lifts to a compact "you said" chip and a shimmering `.redacted`
/// skeleton of the breakdown slides in beneath it; the real numbers then resolve
/// into the same card (count-up, staggered items), with a one-tap undo if the
/// parse is wrong.
struct LogMealSheet: View {
    /// Called once the user is done (logged & kept, or cancelled) — reload Home.
    let onFinished: () -> Void
    var previewModel: LogMealViewModel?

    @Environment(AppEnvironment.self) private var env
    @State private var model: LogMealViewModel?

    var body: some View {
        Group {
            if let model {
                LogMealBody(model: model, onFinished: onFinished)
            } else {
                Color.clear
            }
        }
        .task { if model == nil { model = previewModel ?? LogMealViewModel(api: env.api) } }
    }
}

private struct LogMealBody: View {
    @Bindable var model: LogMealViewModel
    let onFinished: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var focused: Bool
    @State private var pickerItem: PhotosPickerItem?

    /// Skeleton stand-ins shown under the shimmer while the model is `.parsing`.
    private static let skeletonItems: [LogMealResponse.Parsed.Item] = [
        .init(name: "Main portion", quantity: "1 serving", kcal: 280, proteinG: 32, carbsG: 4, fatG: 9),
        .init(name: "Side", quantity: "1 cup", kcal: 210, proteinG: 5, carbsG: 42, fatG: 3),
        .init(name: "Extras", quantity: "1 scoop", kcal: 150, proteinG: 5, carbsG: 20, fatG: 2),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                switch model.phase {
                case .compose:
                    compose
                case let .failed(message):
                    failed(message)
                default:
                    reveal
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(Motion.adaptive(Motion.standard, reduceMotion: reduceMotion), value: model.phase)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Palette.background)
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    model.attach(data)
                }
                pickerItem = nil
                focused = false
            }
        }
        .onChange(of: model.phase) { _, phase in
            if case .logged = phase { Haptics.landed() }
        }
        .onAppear { focused = true }
    }

    // MARK: Compose

    @ViewBuilder
    private var compose: some View {
        Text("What did you eat?")
            .font(Typography.voice(22))
            .foregroundStyle(Palette.ink)

        if let photo = model.photo {
            ZStack(alignment: .topTrailing) {
                Image(uiImage: photo.preview)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 160)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                Button {
                    model.removePhoto()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(.white, Color.black.opacity(0.45))
                        .padding(8)
                }
            }
        }

        TextField("e.g. chicken burrito bowl, large", text: $model.text, axis: .vertical)
            .font(Typography.data(16))
            .lineLimit(1 ... 3)
            .padding(14)
            .background(Palette.surfaceSunk, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .focused($focused)

        HStack(spacing: 12) {
            PhotosPicker(selection: $pickerItem, matching: .images, photoLibrary: .shared()) {
                Label(model.photo == nil ? "Add photo" : "Change photo", systemImage: "camera")
                    .font(Typography.data(15, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Palette.surfaceSunk, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }

        ActionButton(title: "Log it") {
            focused = false
            Task { await model.submit() }
        }
        .opacity(model.canSubmit ? 1 : 0.5)
        .disabled(!model.canSubmit)

        Text("A rough guess is fine — the app fills in the macros.")
            .font(Typography.data(12))
            .foregroundStyle(Palette.inkFaint)
    }

    // MARK: Parse reveal (parsing skeleton → resolved result, one continuous card)

    @ViewBuilder
    private var reveal: some View {
        let logged: LogMealViewModel.Logged? = {
            if case let .logged(value) = model.phase { return value }
            return nil
        }()
        let parsing = logged == nil

        Text(headline(logged))
            .font(Typography.voice(22))
            .foregroundStyle(Palette.ink)
            .contentTransition(.opacity)

        inputChip

        ParsedBreakdown(
            summary: logged?.summary ?? "Reading the portions",
            kcal: logged?.kcal ?? 640,
            proteinG: logged?.proteinG ?? 41,
            items: logged?.items ?? Self.skeletonItems,
            notes: logged?.notes,
            redacted: parsing
        )
        .shimmering(parsing)

        if let logged {
            if logged.resolvedCheckIn {
                Text("That closes out your open check-in.")
                    .font(Typography.data(13))
                    .foregroundStyle(Palette.inkSoft)
                    .appearIn(0)
            }

            ActionButton(title: "Looks right") {
                onFinished()
            }
            .appearIn(1)

            Button("That's not what I ate — remove it") {
                Task { await model.undo() }
            }
            .font(Typography.data(14, weight: .medium))
            .foregroundStyle(Palette.accent)
            .frame(maxWidth: .infinity)
            .appearIn(2)
        }
    }

    private func headline(_ logged: LogMealViewModel.Logged?) -> String {
        guard let logged else { return "Working it out…" }
        return logged.fromPhoto ? "Logged from your photo" : "Logged"
    }

    /// What the user gave us, kept visible through parsing and the result so the
    /// source stays attached to the guess.
    @ViewBuilder
    private var inputChip: some View {
        let trimmed = model.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty || model.photo != nil {
            HStack(spacing: 10) {
                if let photo = model.photo {
                    Image(uiImage: photo.preview)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 40, height: 40)
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                Text(trimmed.isEmpty ? "From your photo" : trimmed)
                    .font(Typography.data(13))
                    .foregroundStyle(Palette.inkSoft)
                    .lineLimit(2)
                Spacer(minLength: 0)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.surfaceSunk.opacity(0.6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    // MARK: Failure

    @ViewBuilder
    private func failed(_ message: String) -> some View {
        Text("That didn't go through")
            .font(Typography.voice(22))
            .foregroundStyle(Palette.ink)
        inputChip
        Text(message)
            .font(Typography.data(14))
            .foregroundStyle(Palette.inkSoft)
        ActionButton(title: "Try again", kind: .secondary) { model.reset() }
    }
}

/// The macro breakdown card — used both as the redacted skeleton and the real
/// parsed result, at a stable position so the values resolve in place.
private struct ParsedBreakdown: View {
    let summary: String?
    let kcal: Int
    let proteinG: Double
    let items: [LogMealResponse.Parsed.Item]
    let notes: String?
    var redacted: Bool = false

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                if let summary {
                    Text(summary)
                        .font(Typography.voice(17))
                        .foregroundStyle(Palette.ink)
                }

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(kcal)")
                        .font(Typography.data(28, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                        .contentTransition(.numericText(value: Double(kcal)))
                        .monospacedDigit()
                    Text("kcal · \(Int(proteinG.rounded())) g protein")
                        .font(Typography.data(14))
                        .foregroundStyle(Palette.inkFaint)
                }

                if !items.isEmpty {
                    Divider().overlay(Palette.ink.opacity(0.06))
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        HStack {
                            Text(item.name)
                                .font(Typography.data(14))
                                .foregroundStyle(Palette.ink)
                            Text(item.quantity)
                                .font(Typography.data(12))
                                .foregroundStyle(Palette.inkFaint)
                            Spacer()
                            Text("\(item.kcal) kcal")
                                .font(Typography.data(13))
                                .foregroundStyle(Palette.inkFaint)
                        }
                        .appearIn(redacted ? 0 : index, rise: 4)
                    }
                }

                if let notes, !notes.isEmpty {
                    Text(notes)
                        .font(Typography.data(12))
                        .foregroundStyle(Palette.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .redacted(reason: redacted ? .placeholder : [])
    }
}

#if DEBUG
#Preview {
    Color.black.sheet(isPresented: .constant(true)) {
        LogMealSheet(onFinished: {})
            .environment(AppEnvironment.preview())
            .presentationDetents([.medium, .large])
    }
}
#endif
