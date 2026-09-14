import SwiftUI

/// How body weight is shown and entered. Everything is stored and sent in kg;
/// this only converts at the edges. Views read it with
/// `@AppStorage(MassUnit.storageKey) var unit = MassUnit.localeDefault` so a
/// change in Settings shows everywhere at once.
enum MassUnit: String, CaseIterable, Identifiable {
    case kg
    case lb

    var id: String { rawValue }

    static let storageKey = "com.setpoint.app.massUnit"
    private static let poundsPerKg = 2.2046226218

    /// Pounds where the region weighs in pounds, kilograms elsewhere.
    static var localeDefault: MassUnit {
        Locale.current.measurementSystem == .us ? .lb : .kg
    }

    static var current: MassUnit {
        get { UserDefaults.standard.string(forKey: storageKey).flatMap(MassUnit.init(rawValue:)) ?? localeDefault }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: storageKey) }
    }

    var title: String {
        switch self {
        case .kg: return "Kilograms"
        case .lb: return "Pounds"
        }
    }

    var abbreviation: String { rawValue }

    /// For VoiceOver: "72 kilograms".
    var spokenName: String {
        switch self {
        case .kg: return "kilograms"
        case .lb: return "pounds"
        }
    }

    func fromKg(_ kg: Double) -> Double {
        self == .lb ? kg * Self.poundsPerKg : kg
    }

    func toKg(_ value: Double) -> Double {
        self == .lb ? value / Self.poundsPerKg : value
    }

    /// The number alone, in this unit: "72.5" / "159.8".
    func number(_ kg: Double, digits: ClosedRange<Int> = 0 ... 1) -> String {
        fromKg(kg).formatted(.number.precision(.fractionLength(digits)))
    }

    /// With the unit: "72.5 kg" / "159.8 lb".
    func formatKg(_ kg: Double, digits: Int = 1) -> String {
        "\(number(kg, digits: digits ... digits)) \(abbreviation)"
    }

    /// A kg-valued binding shown and edited in this unit.
    func binding(kg: Binding<Double>) -> Binding<Double> {
        Binding(get: { fromKg(kg.wrappedValue) }, set: { kg.wrappedValue = toKg($0) })
    }

    /// A kg range expressed in this unit, on whole numbers.
    func range(kg: ClosedRange<Double>) -> ClosedRange<Double> {
        fromKg(kg.lowerBound).rounded(.up) ... fromKg(kg.upperBound).rounded(.down)
    }

    /// Moves a kg value by whole steps of this unit, landing on a whole number of it.
    func nudge(kg: Double, by steps: Double) -> Double {
        toKg((fromKg(kg) + steps).rounded())
    }
}
