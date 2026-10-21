import Foundation

/// Per-account bits kept on this phone. Sign-in and sign-out wipe them so a
/// new Apple ID doesn't inherit the previous user's name, onboarding draft,
/// meals, or flags.
enum AccountLocalState {
    @MainActor
    static func clear(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: SettingsViewModel.displayNameKey)
        OnboardingViewModel.clearProgress(in: defaults)
        OfflineMealQueue.clear(in: defaults)
        FeatureFlags.clearStored()
        HomeViewModel.clearIgnoredCheckIn(in: defaults)
        PatternMemory.clear(in: defaults)
        TodaySnapshotSync.clear()
        HealthKitManager.shared.clearAccountSyncState()
        CalendarManager.shared.clearAccountState()
    }
}
