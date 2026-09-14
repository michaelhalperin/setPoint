import Foundation
import HealthKit

struct HealthWritePreferences: Equatable, Codable {
    var energy = true
    var protein = true
    var carbs = true
    var fat = true
    var bodyMass = false

    static let defaultsKey = "com.setpoint.app.health.writePreferences"
    static let versionsKey = "com.setpoint.app.health.mealSyncVersions"

    var writesNutrition: Bool { energy || protein || carbs || fat }

    var settingsPayload: HealthWritePayload {
        HealthWritePayload(energy: energy, protein: protein, carbs: carbs, fat: fat, bodyMass: bodyMass)
    }

    static func from(_ payload: HealthWritePayload) -> HealthWritePreferences {
        HealthWritePreferences(
            energy: payload.energy,
            protein: payload.protein,
            carbs: payload.carbs,
            fat: payload.fat,
            bodyMass: payload.bodyMass
        )
    }
}

struct DietaryWrite: Equatable {
    let mealId: String
    let kcal: Double
    let proteinG: Double
    let carbsG: Double
    let fatG: Double
    let date: Date
}

extension HealthDataSource {
    func requestAuthorization(read types: Set<HKObjectType>) async throws {
        try await requestAuthorization(toShare: [], read: types)
    }

    func requestStatus(read types: Set<HKObjectType>) async -> HKAuthorizationRequestStatus {
        await requestStatus(toShare: [], read: types)
    }
}
