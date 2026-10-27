import SwiftUI

// The guided tour. The owner edits the steps in /admin (backend/src/tour); the app fetches
// them at launch, caches them, and walks the person through the real screens: a dim layer
// with a cutout around one element, and a tip card next to it. Every element a step can
// point at is a view tagged with `.tourAnchor("id")`.

// MARK: - Model

struct TourStep: Codable, Identifiable, Equatable {
    struct Words: Codable, Equatable {
        let title: String
        let body: String
    }

    let id: String
    /// The element to spotlight; nil shows the tip in the middle of the screen.
    let anchor: String?
    /// The opening prompt ("Show me / Not now").
    let welcome: Bool
    let title: String
    let body: String
    let he: Words?
    /// The spotlight's padding and corner radius, from the element's entry on the server.
    let pad: Double?
    let radius: Double?
    /// Where the tip sits against the element: "auto", "above" or "below". Older tours don't say.
    var side: String? = nil
    /// The owner's nudge of the tip from that spot, in points.
    var dx: Double? = nil
    var dy: Double? = nil

    /// What this person reads: Hebrew when they use Hebrew and the step has it.
    var words: Words {
        if AppLanguage.current == .he, let he, !he.title.isEmpty, !he.body.isEmpty { return he }
        return Words(title: title, body: body)
    }

    /// The tab the element lives on.
    var tab: MainTabView.Tab? {
        switch anchor?.split(separator: ".").first {
        case "today", "nav": return .today
        case "train": return .training
        case "progress": return .week
        case "you": return .you
        default: return nil
        }
    }
}

struct Tour: Codable, Equatable {
    var revision: Int
    var steps: [TourStep]
}

// MARK: - Anchors

struct TourAnchorKey: PreferenceKey {
    static var defaultValue: [String: Anchor<CGRect>] = [:]
    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue()) { _, new in new }
    }
}

extension View {
    /// Marks this view as an element the guided tour can point at. `id` is one of the
    /// anchor ids the server knows (backend/src/tour).
    func tourAnchor(_ id: String) -> some View {
        anchorPreference(key: TourAnchorKey.self, value: .bounds) { [id: $0] }
    }
}

// MARK: - Controller

@MainActor
@Observable
final class TourController {
    private(set) var tour: Tour
    /// The step on screen; nil when no tour is running.
    private(set) var index: Int?
    @ObservationIgnored private var origin: MainTabView.Tab = .today
    @ObservationIgnored var requestTab: (MainTabView.Tab) -> Void = { _ in }

    private static let seenKey = "tour.seenRevision"
    private static let cacheKey = "tour.cache.v1"

    init() {
        tour = Self.cached() ?? Self.builtIn
    }

    static var builtIn: Tour {
        (try? JSONDecoder().decode(Tour.self, from: Data(TourDefault.json.utf8))) ?? Tour(revision: 1, steps: [])
    }

    private static func cached() -> Tour? {
        UserDefaults.standard.data(forKey: cacheKey).flatMap { try? JSONDecoder().decode(Tour.self, from: $0) }
    }

    // MARK: State

    var step: TourStep? {
        guard let index, tour.steps.indices.contains(index) else { return nil }
        return tour.steps[index]
    }

    var isActive: Bool { step != nil }

    /// "3 of 10": where this step sits among the steps that point at something.
    var position: (at: Int, of: Int)? {
        guard let index, let step, !step.welcome else { return nil }
        let real = tour.steps.filter { !$0.welcome }
        let at = tour.steps[...index].filter { !$0.welcome }.count
        return (at, real.count)
    }

    var isLast: Bool { index == tour.steps.count - 1 }

    private var seenRevision: Int {
        get { UserDefaults.standard.integer(forKey: Self.seenKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.seenKey) }
    }

    // MARK: Loading

    /// The owner's latest tour. A failed fetch keeps whatever we had.
    func refresh(api: APIClient) async {
        guard let fresh: Tour = try? await api.get("/api/tour"), fresh != tour else { return }
        tour = fresh
        if let data = try? JSONEncoder().encode(fresh) {
            UserDefaults.standard.set(data, forKey: Self.cacheKey)
        }
    }

    // MARK: Running

    /// After setup, once per revision: the opening prompt first.
    func startIfUnseen() {
        guard !isActive, seenRevision < tour.revision, !tour.steps.isEmpty else { return }
        begin(replay: false, from: .today)
    }

    /// From You → How SetPoint works: straight into the steps.
    func replay(from tab: MainTabView.Tab) {
        guard !tour.steps.isEmpty else { return }
        begin(replay: true, from: tab)
    }

    /// Admin: run it the way a new person gets it, opening prompt included.
    func showAsFirstRun(from tab: MainTabView.Tab) {
        seenRevision = 0
        begin(replay: false, from: tab)
    }

    private func begin(replay: Bool, from tab: MainTabView.Tab) {
        origin = tab
        let first = replay ? (tour.steps.firstIndex { !$0.welcome } ?? 0) : 0
        go(to: first)
    }

    func next() {
        guard let index else { return }
        if index + 1 >= tour.steps.count { finish() } else { go(to: index + 1) }
    }

    func back() {
        guard let index, let step else { return }
        if step.welcome || index == 0 { finish(); return }
        let previous = index - 1
        if tour.steps[previous].welcome { finish(); return }
        go(to: previous)
    }

    func finish() {
        index = nil
        seenRevision = max(seenRevision, tour.revision)
        requestTab(origin)
    }

    #if DEBUG
    func showForDebug(at newIndex: Int) { index = newIndex }

    func debugAdjust(stepID: String, side: String?, dx: Double?, dy: Double?) {
        guard let i = tour.steps.firstIndex(where: { $0.id == stepID }) else { return }
        if let side { tour.steps[i].side = side }
        if let dx { tour.steps[i].dx = dx }
        if let dy { tour.steps[i].dy = dy }
    }
    #endif

    private func go(to newIndex: Int) {
        index = newIndex
        if let tab = tour.steps[newIndex].tab { requestTab(tab) }
    }
}
