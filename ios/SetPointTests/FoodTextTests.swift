import XCTest
@testable import SetPoint

final class FoodTextTests: XCTestCase {
    private func withLanguage(_ language: AppLanguage, _ body: () -> Void) {
        let key = AppLanguage.storageKey
        let flagsKey = "com.setpoint.app.featureFlags.v1"
        let previous = UserDefaults.standard.object(forKey: key)
        let previousFlags = UserDefaults.standard.object(forKey: flagsKey)
        UserDefaults.standard.set(language.rawValue, forKey: key)
        UserDefaults.standard.set(["app_language": true], forKey: flagsKey)
        defer {
            UserDefaults.standard.set(previous, forKey: key)
            UserDefaults.standard.set(previousFlags, forKey: flagsKey)
        }
        body()
    }

    func testHebrewSuggestionShowsInEnglish() {
        withLanguage(.en) {
            XCTAssertEqual(FoodText.name("2 × חלב מלא + שקדים"), "2 × Whole milk + Almonds")
            XCTAssertEqual(FoodText.name("Whole milk"), "Whole milk")
            XCTAssertEqual(FoodText.name("my own dish"), "my own dish")
        }
    }

    func testEnglishSuggestionShowsInHebrew() {
        withLanguage(.he) {
            XCTAssertEqual(FoodText.name("2 × Whole milk + Almonds"), "2 × חלב מלא + שקדים")
        }
    }
}
