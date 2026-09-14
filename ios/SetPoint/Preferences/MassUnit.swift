import Foundation

enum MassUnit: String, CaseIterable, Identifiable {
    case kg
    case lb

    var id: String { rawValue }

    var title: String {
        switch self {
        case .kg: return "Kilograms"
        case .lb: return "Pounds"
        }
    }

    var abbreviation: String {
        switch self {
        case .kg: return "kg"
        case .lb: return "lb"
        }
    }

    private static let key = "com.setpoint.app.massUnit"

    static var current: MassUnit {
        get { MassUnit(rawValue: UserDefaults.standard.string(forKey: key) ?? "kg") ?? .kg }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: key) }
    }

    func fromKg(_ kg: Double) -> Double {
        self == .lb ? kg * 2.2046226218 : kg
    }

    func toKg(_ value: Double) -> Double {
        self == .lb ? value / 2.2046226218 : value
    }

    func formatKg(_ kg: Double, digits: Int = 1) -> String {
        let value = fromKg(kg)
        let formatted = value.formatted(.number.precision(.fractionLength(digits)))
        return "\(formatted) \(abbreviation)"
    }
}
