import PhotosUI
import SwiftUI

/// Meal logging (§5.5) — free text, a photo, or both. While the backend's vision
/// model works, a `.redacted` skeleton of the breakdown shows; the real numbers
/// fade in on top, with a one-tap undo if the parse is wrong.
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                switch model.phase {
                case .compose:
                    compose
                case .parsing:
                    parsing
                case let .logged(logged):
                    result(logged)
                case let .failed(message):
                    failed(message)
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

    // MARK: Parsing skeleton

    @ViewBuilder
    private var parsing: some View {
        Text("Working it out…")
            .font(Typography.voice(22))
            .foregroundStyle(Palette.ink)

        ParsedBreakdown(
            summary: "Chicken burrito bowl",
            kcal: 640,
            proteinG: 41,
            items: [
                .init(name: "Grilled chicken", quantity: "1 serving", kcal: 280, proteinG: 32, carbsG: 2, fatG: 9),
                .init(name: "Cilantro-lime rice", quantity: "1 cup", kcal: 210, proteinG: 4, carbsG: 44, fatG: 3),
                .init(name: "Black beans + salsa", quantity: "1 scoop", kcal: 150, proteinG: 5, carbsG: 22, fatG: 2),
            ],
            notes: nil
        )
        .redacted(reason: .placeholder)
        .accessibilityLabel("Estimating the meal")
    }

    // MARK: Result

    @ViewBuilder
    private func result(_ logged: LogMealViewModel.Logged) -> some View {
        Text(logged.fromPhoto ? "Logged from your photo" : "Logged")
            .font(Typography.voice(22))
            .foregroundStyle(Palette.ink)

        if logged.items.isEmpty {
            ParsedBreakdown(
                summary: logged.summary,
                kcal: logged.kcal,
                proteinG: logged.proteinG,
                items: [],
                notes: logged.notes
            )
        } else {
            ParsedBreakdown(
                summary: logged.summary,
                kcal: logged.kcal,
                proteinG: logged.proteinG,
                items: logged.items,
                notes: logged.notes
            )
            .transition(.opacity)
        }

        if logged.resolvedCheckIn {
            Text("That closes out your open check-in.")
                .font(Typography.data(13))
                .foregroundStyle(Palette.inkSoft)
        }

        ActionButton(title: "Looks right") {
            onFinished()
        }

        Button("That's not what I ate — remove it") {
            Task { await model.undo() }
        }
        .font(Typography.data(14, weight: .medium))
        .foregroundStyle(Palette.accent)
        .frame(maxWidth: .infinity)
    }

    // MARK: Failure

    @ViewBuilder
    private func failed(_ message: String) -> some View {
        Text("That didn't go through")
            .font(Typography.voice(22))
            .foregroundStyle(Palette.ink)
        Text(message)
            .font(Typography.data(14))
            .foregroundStyle(Palette.inkSoft)
        ActionButton(title: "Try again", kind: .secondary) { model.reset() }
    }
}

/// The macro breakdown card — used both as the redacted skeleton and the real
/// parsed result.
private struct ParsedBreakdown: View {
    let summary: String?
    let kcal: Int
    let proteinG: Double
    let items: [LogMealResponse.Parsed.Item]
    let notes: String?

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
                    Text("kcal · \(Int(proteinG.rounded())) g protein")
                        .font(Typography.data(14))
                        .foregroundStyle(Palette.inkFaint)
                }

                if !items.isEmpty {
                    Divider().overlay(Palette.ink.opacity(0.06))
                    ForEach(items) { item in
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
