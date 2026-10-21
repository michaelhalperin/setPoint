import SwiftUI

/// Order nearby: when there's no food at hand, one dish from a place near you
/// that fills what you still need, with the rest a tap away. SetPoint never
/// orders — "Open in Wolt" opens Wolt on the dish, you add it and pay there, and
/// back here one tap logs it. Drawn in haze so it reads apart from the plates.
struct OrderNearbyView: View {
    /// What's still needed for this meal.
    let gapKcal: Int
    /// "Lunch", "Dinner"…
    let slotTitle: String
    var preview: NearbyResponse? = nil
    /// Called after a dish is logged, so Today can reload.
    var onLogged: () -> Void = {}

    @Environment(AppEnvironment.self) private var env
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Phase {
        case loading
        case locationDenied
        case failed(String)
        case loaded(NearbyResponse)
    }

    /// Where the hand-off is: choosing, back from Wolt, or logged.
    private enum Hand: Equatable {
        case browse
        case back
        case logged(mealID: String)
    }

    private enum Filter: String, CaseIterable {
        case all = "All", bowls = "Bowls", wraps = "Wraps", plates = "Plates", drinks = "Drinks"

        func matches(_ kind: String) -> Bool {
            switch self {
            case .all: return true
            case .bowls: return kind == "BOWL"
            case .wraps: return kind == "WRAP"
            case .plates: return kind == "PLATE"
            case .drinks: return kind == "DRINK"
            }
        }
    }

    /// One dish at one place.
    private struct Candidate: Identifiable, Equatable {
        let venue: NearbyResponse.Venue
        let dish: NearbyResponse.Dish
        var id: String { "\(venue.id)/\(dish.id)" }
    }

    @State private var phase: Phase = .loading
    @State private var filter: Filter = .all
    /// The dish the user swapped in; nil means the best fit.
    @State private var pickID: String?
    @State private var hand: Hand = .browse
    @State private var logging = false
    @State private var toast: String?
    @State private var location = LocationOnce()

    var body: some View {
        screenBody.trackScreen("order_nearby")
    }

    @ViewBuilder
    private var screenBody: some View {
        InnerScreen(glow: .haze, spacing: 16) {
            ScreenHeader(label: "Order nearby")

            VStack(alignment: .leading, spacing: 8) {
                Headline(headline, tail: tail, size: 34)
                    .contentTransition(.opacity)
                Text(metaLine)
                    .font(Typography.mono(10))
                    .tracking(1.2)
                    .foregroundStyle(Palette.inkFaint)
            }
            .padding(.horizontal, 4)
            .appearIn(0, rise: 16)

            switch phase {
            case .loading:
                BusyDots(tint: Palette.haze)
                    .frame(maxWidth: .infinity, minHeight: 200)
            case .locationDenied:
                notice(
                    "Location is off for SetPoint.",
                    "Turn it on in Settings to see places near you. It’s only used for this search."
                ) {
                    ActionButton(title: "Open Settings", kind: .secondary) {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                }
            case let .failed(message):
                notice("Couldn’t find places.", message) {
                    ActionButton(title: "Try again", kind: .secondary) { Task { await load() } }
                }
            case let .loaded(response):
                loaded(response)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let hero = currentHero {
                bottomBar(hero)
            }
        }
        .overlay(alignment: .top) {
            if let toast {
                HStack(spacing: 10) {
                    Circle().fill(Palette.haze).frame(width: 8, height: 8)
                    Text(toast)
                        .font(Typography.data(13, weight: .regular))
                        .foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .glass(radius: 18, fill: Color(hex: 0x1C1C20, opacity: 0.96), stroke: Color.white.opacity(0.12))
                .padding(.horizontal, Space.gutter)
                .padding(.top, 4)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(Motion.snappy, value: toast)
        .animation(Motion.adaptive(Motion.settle, reduceMotion: reduceMotion), value: hand)
        .animation(Motion.adaptive(Motion.settle, reduceMotion: reduceMotion), value: pickID)
        .task { await load() }
    }

    // MARK: Picking

    private var isLogged: Bool {
        if case .logged = hand { return true }
        return false
    }

    /// Every dish that matches the filter, closest to the gap first, then the most protein.
    private func pool(_ response: NearbyResponse) -> [Candidate] {
        response.venues
            .flatMap { venue in venue.dishes.map { Candidate(venue: venue, dish: $0) } }
            .filter { filter.matches($0.dish.kind) }
            .sorted {
                let a = abs($0.dish.kcal - gapKcal), b = abs($1.dish.kcal - gapKcal)
                return a != b ? a < b : $0.dish.proteinG > $1.dish.proteinG
            }
    }

    private func hero(in pool: [Candidate]) -> Candidate? {
        pool.first { $0.id == pickID } ?? pool.first
    }

    private var currentHero: Candidate? {
        guard case let .loaded(response) = phase else { return nil }
        return hero(in: pool(response))
    }

    private var swapped: Bool {
        guard case let .loaded(response) = phase, let first = pool(response).first else { return false }
        return currentHero?.id != first.id
    }

    // MARK: Copy

    private var loggedKcal: Int { isLogged ? (currentHero?.dish.kcal ?? 0) : 0 }
    private var leftKcal: Int { max(0, gapKcal - loggedKcal) }

    private var headline: String {
        guard isLogged else { return "\(gapKcal.formatted()) kcal to go." }
        return leftKcal > 60 ? "\(leftKcal.formatted()) kcal to go." : "\(slotTitle) covered."
    }

    private var tail: String {
        if isLogged { return leftKcal > 60 ? "A snack later covers it." : "That’s the gap closed." }
        guard currentHero != nil else { return "Let’s see what’s near you." }
        return swapped ? "Good swap." : "This one fills it."
    }

    private var metaLine: String {
        var parts = [slotTitle.uppercased()]
        if case let .loaded(response) = phase {
            parts.append(response.venues.isEmpty ? "NONE ON OUR LIST WITHIN 3 KM" : "\(response.venues.count) PLACES WITHIN 3 KM")
            if response.sample { parts.append("SAMPLE PLACES") }
        } else {
            parts.append("WITHIN 3 KM")
        }
        return parts.joined(separator: " · ")
    }

    private func fitLabel(_ dish: NearbyResponse.Dish) -> String {
        let diff = dish.kcal - gapKcal
        if abs(diff) <= 60 { return "FILLS IT" }
        if diff < 0 { return "COVERS \(Int((Double(dish.kcal) / Double(max(gapKcal, 1)) * 100).rounded()))%" }
        return "FILLS IT · +\(diff.formatted())"
    }

    private func why(_ dish: NearbyResponse.Dish) -> String {
        if isLogged { return "Logged as \(slotTitle.lowercased()). It’s on Today with its calories and protein." }
        if swapped {
            return dish.kcal - gapKcal < -60 ? "Your swap. A snack later covers the rest." : "Your swap. Close enough to the gap."
        }
        return dish.proteinG >= 40 ? "Closest to your gap, and high in protein." : "Closest to your gap from what’s near you."
    }

    private func share(_ kcal: Int) -> CGFloat {
        min(1, CGFloat(kcal) / CGFloat(max(gapKcal, 1)))
    }

    // MARK: Loaded

    @ViewBuilder
    private func loaded(_ response: NearbyResponse) -> some View {
        let pool = pool(response)
        if response.venues.isEmpty, let ideas = response.suggestions, !ideas.isEmpty {
            fallback(ideas)
        } else if response.venues.isEmpty {
            notice(
                "No places near you yet.",
                "We’re adding places area by area. Until then, log something you have at home."
            ) { EmptyView() }
        } else if let hero = hero(in: pool) {
            heroCard(hero, canShuffle: pool.count > 1) {
                guard let index = pool.firstIndex(of: hero) else { return }
                pickID = pool[(index + 1) % pool.count].id
                hand = .browse
            }
            .appearIn(1, rise: 14)

            HStack(alignment: .firstTextBaseline) {
                Text("More that fit").sectionLabelStyle()
                Spacer(minLength: 8)
                Text("Tap one to swap it in")
                    .font(Typography.data(12, weight: .regular))
                    .foregroundStyle(Palette.inkFaint)
            }
            .padding(.horizontal, 4)
            .padding(.top, 4)
            .appearIn(2)

            filters.appearIn(2)

            list(pool.filter { $0 != hero }.prefix(10).map { $0 })
                .appearIn(3, rise: 12)
        } else {
            filters
            notice("Nothing of that kind fits nearby.", "Try All, or log something you have at home.") { EmptyView() }
        }

        if !response.venues.isEmpty {
            Text("SetPoint never orders, pays, or sees your Wolt account. Calories are our estimate from the menu. Dishes with foods you avoid are already left out.")
                .font(Typography.data(12, weight: .regular))
                .foregroundStyle(Palette.inkFaint)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)
                .padding(.top, 2)
        }
    }

    // MARK: Hero

    // MARK: Nothing on our list nearby

    /// Kinds of dish that fit the gap, each opening Wolt's search near the user.
    @ViewBuilder
    private func fallback(_ ideas: [NearbyResponse.Dish]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Nothing on our list near you yet.")
                .font(Typography.data(15, weight: .regular))
                .foregroundStyle(Palette.ink)
            Text("Here’s what to look for. Wolt shows what’s open around you.")
                .font(Typography.data(13, weight: .regular))
                .foregroundStyle(Palette.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 4)
        .appearIn(1)

        if let first = ideas.first {
            ideaCard(first).appearIn(1, rise: 14)
        }

        if ideas.count > 1 {
            Text("Or look for").sectionLabelStyle()
                .padding(.horizontal, 4)
                .padding(.top, 4)
                .appearIn(2)
            VStack(spacing: 0) {
                ForEach(Array(ideas.dropFirst().enumerated()), id: \.element.id) { index, idea in
                    if index > 0 { Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1) }
                    ideaRow(idea)
                }
            }
            .glass(radius: 22, fill: Color.white.opacity(0.035), stroke: Color.white.opacity(0.08))
            .appearIn(3, rise: 12)
        }

        Text("Calories are a typical estimate for this kind of dish. SetPoint never orders, pays, or sees your Wolt account.")
            .font(Typography.data(12, weight: .regular))
            .foregroundStyle(Palette.inkFaint)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 4)
            .padding(.top, 2)
    }

    private func ideaCard(_ idea: NearbyResponse.Dish) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 6) {
                Circle().fill(Palette.hazeSoft).frame(width: 6, height: 6)
                Text("LOOK FOR").font(Typography.mono(10)).tracking(1.2).foregroundStyle(Palette.hazeSoft)
            }
            HStack(spacing: 18) {
                fillRing(idea.kcal)
                VStack(alignment: .leading, spacing: 8) {
                    Text(idea.name)
                        .font(Typography.data(20, weight: .regular))
                        .tracking(-0.4)
                        .foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("About \(idea.kcal.formatted()) kcal · \(Int(idea.proteinG.rounded())) g protein")
                        .font(Typography.data(13, weight: .regular))
                        .foregroundStyle(Palette.inkSoft)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            ActionButton(title: "Search Wolt for it", kind: .primary, symbol: "magnifyingglass") { search(idea) }
        }
        .padding(18)
        .background {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(LinearGradient(colors: [Palette.haze.opacity(0.14), Color.white.opacity(0.03)], startPoint: .topLeading, endPoint: UnitPoint(x: 0.6, y: 0.9)))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(Palette.haze.opacity(0.40))
        }
        .accessibilityElement(children: .contain)
    }

    private func ideaRow(_ idea: NearbyResponse.Dish) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(idea.name)
                    .font(Typography.data(14, weight: .regular))
                    .foregroundStyle(Palette.ink)
                Text("About \(idea.kcal.formatted()) kcal · \(Int(idea.proteinG.rounded())) g protein")
                    .font(Typography.data(12, weight: .regular))
                    .foregroundStyle(Palette.inkFaint)
            }
            Spacer(minLength: 8)
            Button { search(idea) } label: {
                Label("Search", systemImage: "magnifyingglass")
                    .font(Typography.data(13, weight: .medium))
                    .foregroundStyle(Palette.hazeSoft)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 36)
                    .background(Palette.haze.opacity(0.14), in: Capsule())
                    .overlay(Capsule().strokeBorder(Palette.haze.opacity(0.40)))
            }
            .buttonStyle(PressableCard())
            .frame(minHeight: 44)
            .accessibilityLabel("Search Wolt for \(idea.name)")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private func search(_ idea: NearbyResponse.Dish) {
        guard let raw = idea.woltUrl, let url = URL(string: raw) else { return }
        Haptics.nudge()
        if preview == nil {
            Analytics.send(.woltOpened, props: ["venueId": "wolt-search", "dishId": idea.id], api: env.api)
        }
        openURL(url)
    }

    private func heroCard(_ hero: Candidate, canShuffle: Bool, shuffle: @escaping () -> Void) -> some View {
        let dish = hero.dish
        let label = isLogged ? "LOGGED" : swapped ? "YOUR SWAP" : "MY PICK"
        let labelTint = isLogged ? Palette.positive : Palette.hazeSoft
        return VStack(alignment: .leading, spacing: 16) {
            HStack {
                HStack(spacing: 6) {
                    Circle().fill(labelTint).frame(width: 6, height: 6)
                    Text(label).font(Typography.mono(10)).tracking(1.2).foregroundStyle(labelTint)
                }
                Spacer(minLength: 8)
                Text("\(hero.venue.distanceKm.formatted(.number.precision(.fractionLength(1)))) KM AWAY")
                    .font(Typography.mono(10))
                    .tracking(1)
                    .foregroundStyle(Palette.inkFaint)
            }

            HStack(spacing: 18) {
                fillRing(dish.kcal)
                VStack(alignment: .leading, spacing: 8) {
                    Text(dish.name)
                        .font(Typography.data(20, weight: .regular))
                        .tracking(-0.4)
                        .foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(hero.venue.name)
                        .font(Typography.data(13, weight: .regular))
                        .foregroundStyle(Palette.inkSoft)
                    Text(fitLabel(dish))
                        .font(Typography.mono(10))
                        .tracking(1)
                        .foregroundStyle(dish.kcal - gapKcal < -60 ? Color(hex: 0xD4D4D8) : Palette.hazeSoft)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .glassCapsule(fill: Color.white.opacity(0.05), stroke: Color.white.opacity(0.10))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 8) {
                macroTile(dish.proteinG, "PROTEIN")
                macroTile(dish.carbsG, "CARBS")
                macroTile(dish.fatG, "FAT")
            }

            HStack(spacing: 12) {
                Text(why(dish))
                    .font(Typography.data(12, weight: .regular))
                    .foregroundStyle(Palette.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if canShuffle && !isLogged {
                    Button(action: shuffle) {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.left.arrow.right").font(.system(size: 11, weight: .semibold))
                            Text("Something else").font(Typography.data(12, weight: .regular))
                        }
                        .foregroundStyle(Palette.ink)
                        .padding(.horizontal, 12)
                        .frame(height: 32)
                        .glassCapsule(fill: Color.white.opacity(0.06), stroke: Color.white.opacity(0.12))
                    }
                    .buttonStyle(PressableCard())
                    .accessibilityHint("Shows the next dish that fits")
                }
            }
        }
        .padding(18)
        .background {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(isLogged
                      ? AnyShapeStyle(LinearGradient(colors: [Palette.positive.opacity(0.08), Palette.positive.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                      : AnyShapeStyle(LinearGradient(colors: [Palette.haze.opacity(0.14), Color.white.opacity(0.03)], startPoint: .topLeading, endPoint: UnitPoint(x: 0.6, y: 0.9))))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(isLogged ? Palette.positive.opacity(0.35) : Palette.haze.opacity(0.40))
        }
        .shadow(color: Palette.haze.opacity(isLogged ? 0 : 0.10), radius: 30, y: 16)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("The pick: \(dish.name) from \(hero.venue.name)")
    }

    private func fillRing(_ kcal: Int) -> some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.08), lineWidth: 8)
            Circle()
                .trim(from: 0, to: share(kcal))
                .stroke(
                    LinearGradient(colors: [Palette.hazeSoft, Palette.haze], startPoint: .topLeading, endPoint: .bottomTrailing),
                    style: StrokeStyle(lineWidth: 8, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: Palette.haze.opacity(0.55), radius: 6)
            VStack(spacing: 2) {
                Text(kcal.formatted())
                    .font(Typography.data(28, weight: .light))
                    .tracking(-0.8)
                    .foregroundStyle(Palette.ink)
                    .contentTransition(.numericText())
                Text("OF \(gapKcal.formatted())")
                    .font(Typography.mono(9))
                    .tracking(1.2)
                    .foregroundStyle(Palette.inkFaint)
            }
        }
        .padding(4)
        .frame(width: 116, height: 116)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(kcal) of the \(gapKcal) kilocalories you still need")
    }

    private func macroTile(_ grams: Double?, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(grams.map { "\(Int($0.rounded())) g" } ?? "—")
                .font(Typography.data(16, weight: .regular))
                .foregroundStyle(Palette.ink)
            Text(label)
                .font(Typography.mono(9))
                .tracking(1.2)
                .foregroundStyle(Palette.inkFaint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .glass(radius: 14, fill: Color.white.opacity(0.04), stroke: Color.white.opacity(0.07))
        .accessibilityElement(children: .combine)
    }

    // MARK: Filters and list

    private var filters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Filter.allCases, id: \.self) { option in
                    let on = option == filter
                    Button {
                        filter = option
                        pickID = nil
                        hand = .browse
                    } label: {
                        Text(option.rawValue)
                            .font(Typography.data(13, weight: on ? .medium : .regular))
                            .foregroundStyle(on ? Palette.onBone : Palette.inkSoft)
                            .padding(.horizontal, 16)
                            .frame(height: 34)
                            .background(on ? AnyShapeStyle(Palette.ink) : AnyShapeStyle(Color.white.opacity(0.05)), in: Capsule())
                            .overlay(Capsule().strokeBorder(on ? Palette.ink : Color.white.opacity(0.10)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
        }
        .disabled(isLogged)
        .opacity(isLogged ? 0.4 : 1)
    }

    private func list(_ rows: [Candidate]) -> some View {
        VStack(spacing: 0) {
            if rows.isEmpty {
                Text("That’s the only one of this kind near you. Try All for more.")
                    .font(Typography.data(13, weight: .regular))
                    .foregroundStyle(Palette.inkSoft)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
            }
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                if index > 0 {
                    Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
                }
                Button { pickID = row.id; hand = .browse } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle().stroke(Color.white.opacity(0.10), lineWidth: 4)
                            Circle()
                                .trim(from: 0, to: share(row.dish.kcal))
                                .stroke(Palette.haze, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                        }
                        .frame(width: 26, height: 26)
                        .padding(4)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(row.dish.name)
                                .font(Typography.data(14, weight: .regular))
                                .foregroundStyle(Palette.ink)
                                .lineLimit(1)
                            Text("\(row.venue.name) · \(row.venue.distanceKm.formatted(.number.precision(.fractionLength(1)))) km")
                                .font(Typography.data(12, weight: .regular))
                                .foregroundStyle(Palette.inkFaint)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 8)
                        VStack(alignment: .trailing, spacing: 3) {
                            Text(row.dish.kcal.formatted())
                                .font(Typography.mono(12))
                                .foregroundStyle(Palette.ink)
                            Text("\(Int(row.dish.proteinG.rounded())) g protein")
                                .font(Typography.mono(10))
                                .foregroundStyle(Palette.inkFaint)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(row.dish.name) from \(row.venue.name), \(row.dish.kcal) kilocalories")
                .accessibilityHint("Makes it the pick")
            }
        }
        .glass(radius: 22, fill: Color.white.opacity(0.035), stroke: Color.white.opacity(0.08))
        .disabled(isLogged)
        .opacity(isLogged ? 0.4 : 1)
    }

    // MARK: Bottom bar

    private func bottomBar(_ hero: Candidate) -> some View {
        Group {
            switch hand {
            case .browse:
                VStack(spacing: 8) {
                    Button { open(hero) } label: {
                        HStack(spacing: 10) {
                            Text("Open in Wolt")
                                .font(Typography.data(15, weight: .medium))
                            Spacer(minLength: 8)
                            Text("\(hero.dish.kcal.formatted()) KCAL")
                                .font(Typography.mono(11))
                                .foregroundStyle(Color(hex: 0x52525B))
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(Color(hex: 0x0B0B1F))
                                .frame(width: 40, height: 40)
                                .background(Circle().fill(RadialGradient(colors: [Color(hex: 0xE0E7FF), Palette.haze], center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: 24)))
                        }
                        .foregroundStyle(Palette.onBone)
                        .padding(.leading, 22)
                        .padding(.trailing, 8)
                        .frame(height: 56)
                        .background(Palette.ink, in: Capsule())
                        .shadow(color: Palette.haze.opacity(0.25), radius: 20, y: 10)
                    }
                    .buttonStyle(PressableCard())
                    .accessibilityLabel("Open \(hero.dish.name) from \(hero.venue.name) in Wolt")
                    Text("Wolt opens on the dish. You tap Add and pay there.")
                        .font(Typography.data(11, weight: .regular))
                        .foregroundStyle(Palette.inkFaint)
                }
            case .back:
                VStack(alignment: .leading, spacing: 12) {
                    (Text("Back from Wolt. ").foregroundColor(Palette.ink)
                        + Text("Did you order the \(hero.dish.name)?").foregroundColor(Palette.inkSoft))
                        .font(Typography.data(15, weight: .regular))
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        Button { Task { await log(hero) } } label: {
                            BusyLabel(title: "Yes, log it", busy: logging, tint: Palette.onBone)
                                .font(Typography.data(14, weight: .medium))
                                .foregroundStyle(Palette.onBone)
                                .frame(maxWidth: .infinity, minHeight: 46)
                                .background(Palette.ink, in: Capsule())
                        }
                        .buttonStyle(PressableCard())
                        .disabled(logging)
                        Button { hand = .browse } label: {
                            Text("Not this time")
                                .font(Typography.data(14, weight: .regular))
                                .foregroundStyle(Palette.ink)
                                .frame(maxWidth: .infinity, minHeight: 46)
                                .glassCapsule(fill: Color.white.opacity(0.06), stroke: Color.white.opacity(0.12))
                        }
                        .buttonStyle(PressableCard())
                        .disabled(logging)
                    }
                }
                .padding(16)
                .background(Color(hex: 0x16161F, opacity: 0.97), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(Palette.haze.opacity(0.45))
                }
                .shadow(color: .black.opacity(0.5), radius: 20, y: -6)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            case .logged:
                HStack(spacing: 10) {
                    Image(systemName: "checkmark").font(.system(size: 14, weight: .bold))
                    Text("Logged · \(hero.dish.kcal.formatted()) kcal")
                        .font(Typography.data(14, weight: .regular))
                    Spacer(minLength: 8)
                    Button("Undo") { Task { await undo() } }
                        .font(Typography.data(13, weight: .regular))
                        .foregroundStyle(Palette.inkSoft)
                        .buttonStyle(.plain)
                        .padding(.horizontal, 14)
                        .frame(height: 40)
                }
                .foregroundStyle(Palette.positive)
                .padding(.leading, 20)
                .padding(.trailing, 8)
                .frame(height: 56)
                .background(Palette.positive.opacity(0.10), in: Capsule())
                .background(Palette.background, in: Capsule())
                .overlay(Capsule().strokeBorder(Palette.positive.opacity(0.4)))
                .transition(.opacity)
            }
        }
        .padding(.horizontal, Space.gutter)
        .padding(.top, 28)
        .padding(.bottom, 8)
        .background {
            LinearGradient(
                stops: [.init(color: Palette.background.opacity(0), location: 0), .init(color: Palette.background.opacity(0.94), location: 0.26), .init(color: Palette.background, location: 1)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()
        }
    }

    private func notice(_ title: String, _ detail: String, @ViewBuilder action: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(Typography.data(16, weight: .regular))
                .foregroundStyle(Palette.ink)
            Text(detail)
                .font(Typography.data(14, weight: .regular))
                .foregroundStyle(Palette.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
            action()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.white.opacity(0.14), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
        }
    }

    // MARK: Actions

    private func open(_ hero: Candidate) {
        Haptics.nudge()
        pickID = hero.id
        hand = .back
        if let link = hero.dish.woltUrl ?? hero.venue.woltUrl, let url = URL(string: link) {
            if preview == nil {
                Analytics.send(.woltOpened, props: ["venueId": hero.venue.id, "dishId": hero.dish.id], api: env.api)
            }
            openURL(url)
        } else {
            flash("Sample dish: the live list opens Wolt on \(hero.dish.name).")
        }
    }

    private func log(_ hero: Candidate) async {
        let dish = hero.dish
        if preview != nil {
            hand = .logged(mealID: "preview")
            flash("\(dish.name) logged · \(dish.kcal.formatted()) kcal")
            return
        }
        logging = true
        defer { logging = false }
        do {
            let response: LogMealResponse = try await env.api.post(
                "/api/meals",
                LogMealRequest(
                    text: "\(dish.name) · \(hero.venue.name)",
                    macros: .init(kcal: dish.kcal, proteinG: dish.proteinG, carbsG: dish.carbsG, fatG: dish.fatG),
                    clientId: UUID().uuidString
                )
            )
            Haptics.landed()
            hand = .logged(mealID: response.meal.id)
            flash("\(dish.name) logged · \(dish.kcal.formatted()) kcal toward \(slotTitle.lowercased())")
            env.changes.mealsChanged()
            onLogged()
        } catch {
            flash(UserFacingError.message(for: error, fallback: "Couldn’t log it. Try again."))
        }
    }

    private func undo() async {
        guard case let .logged(mealID) = hand else { return }
        if mealID != "preview" {
            do {
                try await env.api.delete("/api/meals/\(mealID)")
                env.changes.mealsChanged()
                onLogged()
            } catch {
                flash(UserFacingError.message(for: error, fallback: "Couldn’t undo. Try again."))
                return
            }
        }
        hand = .browse
    }

    private func flash(_ text: String) {
        toast = text
        let shown = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.8) {
            if toast == shown { toast = nil }
        }
    }

    private func load() async {
        if let preview {
            phase = .loaded(preview)
            return
        }
        phase = .loading
        do {
            let coordinate = try await location.coordinate()
            let response: NearbyResponse = try await env.api.get(
                "/api/nearby",
                query: [
                    "lat": String(coordinate.latitude),
                    "lng": String(coordinate.longitude),
                    "kcal": String(min(3000, max(100, gapKcal))),
                ]
            )
            phase = .loaded(response)
        } catch LocationOnce.Failure.denied {
            phase = .locationDenied
        } catch LocationOnce.Failure.unavailable {
            phase = .failed("Couldn’t get your location. Check that Location Services are on.")
        } catch {
            phase = .failed(UserFacingError.message(for: error, fallback: "Try again in a moment."))
        }
    }
}

#if DEBUG
extension NearbyResponse {
    /// The live-list preview, or, with `-nothingNearby`, what someone far from every listed place sees.
    static var sample: NearbyResponse {
        ProcessInfo.processInfo.arguments.contains("-nothingNearby") ? nothingNearby : liveSample
    }

    /// Nothing on our list in reach: kinds of dish to search Wolt for.
    static let nothingNearby = NearbyResponse(
        gapKcal: 700,
        sample: false,
        venues: [],
        suggestions: [
            .init(id: "generic-poke", name: "A salmon or chicken poke bowl", kcal: 700, proteinG: 38, carbsG: 85, fatG: 20, kind: "BOWL", woltUrl: "https://wolt.com/en/isr/eilat/search?q=poke"),
            .init(id: "generic-shawarma-pita", name: "Shawarma in a pita", kcal: 750, proteinG: 42, carbsG: 68, fatG: 32, kind: "WRAP", woltUrl: "https://wolt.com/en/isr/eilat/search?q=shawarma"),
            .init(id: "generic-chicken-sandwich", name: "A chicken sandwich", kcal: 700, proteinG: 42, carbsG: 65, fatG: 28, kind: "WRAP", woltUrl: "https://wolt.com/en/isr/eilat/search?q=sandwich"),
        ]
    )

    /// A few dishes from the live Tel Aviv list, without links.
    static let liveSample = NearbyResponse(
        gapKcal: 700,
        sample: false,
        venues: [
            .init(id: "cb", name: "Congress Basel", distanceKm: 0.9, woltUrl: nil, dishes: [
                .init(id: "cb1", name: "Athlete’s bowl", kcal: 760, proteinG: 62, carbsG: 35, fatG: 40, kind: "BOWL", woltUrl: nil),
            ]),
            .init(id: "al", name: "Aloha", distanceKm: 1.3, woltUrl: nil, dishes: [
                .init(id: "al1", name: "Kua Moa chicken on rice", kcal: 760, proteinG: 42, carbsG: 85, fatG: 26, kind: "BOWL", woltUrl: nil),
            ]),
            .init(id: "ut", name: "Under The Tree", distanceKm: 1.2, woltUrl: nil, dishes: [
                .init(id: "ut1", name: "Shawarma bowl on freekeh", kcal: 720, proteinG: 40, carbsG: 75, fatG: 28, kind: "BOWL", woltUrl: nil),
            ]),
            .init(id: "nm", name: "Nam", distanceKm: 0.5, woltUrl: nil, dishes: [
                .init(id: "nm1", name: "Pad kra pao with omelette", kcal: 780, proteinG: 38, carbsG: 85, fatG: 30, kind: "BOWL", woltUrl: nil),
            ]),
            .init(id: "zc", name: "Zoe Chicken", distanceKm: 2.5, woltUrl: nil, dishes: [
                .init(id: "zc1", name: "Chicken breast, two sides", kcal: 780, proteinG: 55, carbsG: 75, fatG: 26, kind: "PLATE", woltUrl: nil),
            ]),
            .init(id: "pv", name: "Pasta Via", distanceKm: 0.9, woltUrl: nil, dishes: [
                .init(id: "pv1", name: "Bolognese", kcal: 850, proteinG: 38, carbsG: 100, fatG: 30, kind: "PLATE", woltUrl: nil),
            ]),
            .init(id: "hm", name: "HaMexicani", distanceKm: 1.3, woltUrl: nil, dishes: [
                .init(id: "hm1", name: "Chicken tortilla wrap", kcal: 800, proteinG: 50, carbsG: 80, fatG: 28, kind: "WRAP", woltUrl: nil),
            ]),
            .init(id: "ya", name: "Yashka", distanceKm: 0.7, woltUrl: nil, dishes: [
                .init(id: "ya1", name: "Chicken breast in pita", kcal: 620, proteinG: 40, carbsG: 60, fatG: 22, kind: "WRAP", woltUrl: nil),
            ]),
            .init(id: "dn", name: "Denita Shake", distanceKm: 0.2, woltUrl: nil, dishes: [
                .init(id: "dn1", name: "Chocolate oat shake", kcal: 620, proteinG: 16, carbsG: 95, fatG: 20, kind: "DRINK", woltUrl: nil),
                .init(id: "dn2", name: "Chocolate protein shake", kcal: 380, proteinG: 30, carbsG: 45, fatG: 8, kind: "DRINK", woltUrl: nil),
            ]),
        ]
    )
}
#endif

/// What Order nearby should fill, from Today: the open check-in's plate, else the
/// next meal's size, else what's left of the day.
enum OrderNearbyContext {
    static func gap(_ home: HomeResponse) -> Int {
        let kcal = home.activeCheckIn?.prescription?.totalKcal
            ?? home.appetite?.nextPlate?.kcal
            ?? home.day?.pace?.next?.suggestedKcal
            ?? home.ledger.remainingKcal
        return min(1500, max(200, kcal))
    }

    static func slotTitle(_ home: HomeResponse) -> String {
        if let slot = home.activeCheckIn?.slot { return TodayCopy.slotTitle(slot) }
        if let next = home.nextCheckIn?.slot { return TodayCopy.slotTitle(next) }
        let minute = home.day?.nowMin ?? TodayLayout.minuteOfDay(from: .now)
        return TodayLayout.slot(forMinute: minute, times: home.resolvedMealTimes).title
    }
}
