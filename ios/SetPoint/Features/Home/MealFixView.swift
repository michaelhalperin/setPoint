import SwiftUI

/// Fix a meal that's already logged — a text meal the estimate got wrong, or a
/// photo meal looked at again. The same plate editor as the photo confirm; saving
/// corrects the meal in place, so its time and check-in stay as they were.
struct MealFixView: View {
    let meal: MealSummary
    /// The corrected meal, after it's saved.
    var onSaved: (MealSummary) -> Void = { _ in }
    /// "Not my meal": the presenter removes it (its own way, with its own reload).
    var onRemove: () -> Void
    var onClose: () -> Void

    @Environment(AppEnvironment.self) private var env
    @State private var saving = false
    @State private var error: String?
    @State private var photo: UIImage?

    var body: some View {
        MealCorrectionEditor(
            meal: meal,
            photo: photo,
            saving: saving,
            error: error,
            onCancel: onClose,
            onSave: save,
            onRemove: onRemove
        )
        .task { photo = await MealPhotoCache.shared.image(for: meal) }
    }

    private func save(_ summary: String, _ items: [MealCorrectionRequest.Item]) async -> Bool {
        guard !saving else { return false }
        saving = true
        error = nil
        defer { saving = false }
        do {
            let response: MealCorrectionResponse = try await env.api.patch(
                "/api/meals/\(meal.id)",
                MealCorrectionRequest(summary: summary, items: items)
            )
            Haptics.landed()
            env.changes.mealsChanged()
            onSaved(response.meal)
            await HealthKitManager.shared.writeMeal(response.meal, reportErrors: false)
            onClose()
            return true
        } catch {
            self.error = UserFacingError.message(for: error, fallback: "Couldn’t save. Try again.")
            return false
        }
    }
}

/// "Logged · 640 kcal · Fix" for a few seconds after a meal lands, on any tab —
/// so a wrong estimate can be put right while it's fresh.
struct JustLoggedToast: View {
    let logged: AppChrome.JustLogged
    let onFix: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Palette.amber)
            Text("Logged · \(logged.kcal.formatted()) kcal")
                .font(Typography.data(13, weight: .regular))
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
            Spacer(minLength: 4)
            Button(action: onFix) {
                Text("Fix")
                    .font(Typography.data(13, weight: .medium))
                    .foregroundStyle(Palette.ink)
                    .padding(.horizontal, 14)
                    .frame(height: 30)
                    .glassCapsule(fill: Color.white.opacity(0.08), stroke: Color.white.opacity(0.14))
            }
            .buttonStyle(PressableCard())
            .accessibilityLabel("Fix \(logged.title)")
        }
        .padding(.leading, 16)
        .padding(.trailing, 6)
        .frame(height: 42)
        .background {
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(Capsule(style: .continuous).fill(Color(hex: 0x1C1C20, opacity: 0.85)))
                .overlay(Capsule(style: .continuous).strokeBorder(Palette.hairline))
                .shadow(color: .black.opacity(0.45), radius: 16, y: 10)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// "Didn't save · Try again": an instant action the server refused has been
/// undone on screen; one tap sends it again.
struct ActionFailedToast: View {
    let failure: AppChrome.ActionFailure
    let onRetry: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(Palette.danger).frame(width: 8, height: 8).shadow(color: Palette.danger, radius: 4)
            Text(failure.message)
                .font(Typography.data(13, weight: .regular))
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
            Spacer(minLength: 4)
            Button(action: onRetry) {
                Text("Try again")
                    .font(Typography.data(13, weight: .medium))
                    .foregroundStyle(Palette.ink)
                    .padding(.horizontal, 14)
                    .frame(height: 30)
                    .glassCapsule(fill: Color.white.opacity(0.08), stroke: Color.white.opacity(0.14))
            }
            .buttonStyle(PressableCard())
        }
        .padding(.leading, 16)
        .padding(.trailing, 6)
        .frame(height: 42)
        .background {
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(Capsule(style: .continuous).fill(Color(hex: 0x1C1C20, opacity: 0.9)))
                .overlay(Capsule(style: .continuous).strokeBorder(Palette.danger.opacity(0.35)))
                .shadow(color: .black.opacity(0.45), radius: 16, y: 10)
        }
        .accessibilityElement(children: .combine)
    }
}

