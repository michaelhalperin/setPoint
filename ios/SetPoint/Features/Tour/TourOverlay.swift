import SwiftUI

/// The tour on screen: a dim layer with a cutout around the step's element and a bone tip
/// card beside it. The admin's Tour tab draws the same thing (backend/src/admin/tourPhone.ts),
/// so keep the two in step.
struct TourOverlay: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let proxy: GeometryProxy
    let anchors: [String: Anchor<CGRect>]

    @State private var cardSize: CGSize = .zero
    /// The element can take a moment to appear after a tab switch; after this the tip stops waiting for it.
    @State private var gaveUp = false

    private let bone = Color(hex: 0xF5F5F4)
    private let boneText = Color(hex: 0x3F3F46)

    var body: some View {
        if let step = env.tour.step {
            let screen = proxy.size
            let target = spotlight(for: step, in: screen)
            let waiting = step.anchor != nil && target == nil && !gaveUp
            let layout = cardLayout(step: step, target: target, screen: screen)

            ZStack(alignment: .topLeading) {
                SpotlightShape(
                    origin: target?.minimumPoint ?? CGPoint(x: screen.width / 2, y: screen.height / 2),
                    size: target?.size ?? .zero,
                    radius: CGFloat(step.radius ?? 20),
                    bounds: CGRect(origin: .zero, size: screen)
                )
                .fill(Color(hex: 0x050507, opacity: 0.72), style: FillStyle(eoFill: true))
                .contentShape(Rectangle())
                .onTapGesture { env.tour.finish() }
                .accessibilityHidden(true)

                if let target {
                    RoundedRectangle(cornerRadius: CGFloat(step.radius ?? 20), style: .continuous)
                        .strokeBorder(Palette.amber.opacity(0.75), lineWidth: 1.5)
                        .frame(width: target.width, height: target.height)
                        .offset(x: target.minX, y: target.minY)
                        .allowsHitTesting(false)
                }

                if let arrow = layout.arrow, !waiting, cardSize != .zero {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(bone)
                        .frame(width: 14, height: 14)
                        .rotationEffect(.degrees(45))
                        .position(arrow)
                        .allowsHitTesting(false)
                }

                card(step, width: layout.width)
                    .background(GeometryReader { geo in
                        Color.clear
                            .onAppear { cardSize = geo.size }
                            .onChange(of: geo.size) { _, size in cardSize = size }
                    })
                    .offset(x: layout.origin.x, y: layout.origin.y)
                    .opacity(waiting ? 0 : 1)
            }
            .frame(width: screen.width, height: screen.height, alignment: .topLeading)
            .environment(\.layoutDirection, AppLanguage.current.layoutDirection)
            .animation(Motion.adaptive(.spring(response: 0.42, dampingFraction: 0.86), reduceMotion: reduceMotion), value: layout.origin)
            .animation(Motion.adaptive(.spring(response: 0.42, dampingFraction: 0.86), reduceMotion: reduceMotion), value: target)
            .task(id: step.id) {
                gaveUp = false
                try? await Task.sleep(for: .seconds(1))
                gaveUp = true
            }
            .accessibilityAddTraits(.isModal)
            #if DEBUG
            .task(id: "\(step.id)-\(cardSize.height)-\(layout.origin.x)-\(layout.origin.y)") {
                guard CommandLine.arguments.contains("-dumpTourCard"), cardSize != .zero else { return }
                try? await Task.sleep(for: .seconds(1.5))
                let rect = [layout.origin.x, layout.origin.y, cardSize.width, cardSize.height].map { Double($0) }
                if let data = try? JSONSerialization.data(withJSONObject: ["id": step.id, "rect": rect]),
                   let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                    try? data.write(to: docs.appendingPathComponent("tour-card.json"))
                }
            }
            #endif
        }
    }

    // MARK: Geometry

    /// The element's frame, padded; nil when the step has no element or it isn't on screen.
    private func spotlight(for step: TourStep, in screen: CGSize) -> CGRect? {
        guard let id = step.anchor, let anchor = anchors[id] else { return nil }
        let frame = proxy[anchor]
        guard frame.width > 1, frame.height > 1,
              frame.intersects(CGRect(origin: .zero, size: screen)),
              frame.midY < screen.height - 40 else { return nil }
        return frame.insetBy(dx: -CGFloat(step.pad ?? 8), dy: -CGFloat(step.pad ?? 8))
    }

    /// The phone the admin's preview is drawn on (iPhone 16 Pro, points). Which side the tip takes is
    /// decided as on that phone, so every phone agrees with the preview. From there the tip sits a fixed
    /// distance from its element (plus the owner's nudge), and a shorter phone only pushes it up when it
    /// would otherwise run off the screen.
    private static let referenceHeight: CGFloat = 874

    private struct Layout {
        var width: CGFloat
        var origin: CGPoint
        var arrow: CGPoint?
    }

    private func cardLayout(step: TourStep, target: CGRect?, screen: CGSize) -> Layout {
        let width = min(284, screen.width - 32)
        let height = cardSize.height
        let nudge = CGPoint(x: step.dx ?? 0, y: step.dy ?? 0)
        let nudged = nudge != .zero
        /// A nudge counts from the tip's spot against its element, not from where this phone's bottom
        /// edge would push it, so it lands where the owner put it on a phone of any height.
        func settle(raw: CGPoint, clamped: CGPoint) -> CGPoint {
            guard nudged else { return clamped }
            return CGPoint(
                x: max(16, min(screen.width - width - 16, raw.x + nudge.x)),
                y: max(58, min(min(screen.height, Self.referenceHeight) - height - 24, raw.y + nudge.y))
            )
        }
        guard let target else {
            let middle = CGPoint(x: (screen.width - width) / 2, y: (screen.height - height) / 2 - 30)
            return Layout(width: width, origin: settle(raw: middle, clamped: middle), arrow: nil)
        }
        let gap: CGFloat = 16
        let below = Self.referenceHeight - target.maxY - gap - 8
        let above = target.minY - gap - 56
        let placeBelow: Bool
        switch step.side {
        case "below": placeBelow = true
        case "above": placeBelow = false
        default: placeBelow = below >= height || (above < height && below > above)
        }
        let rawTop = placeBelow ? target.maxY + gap : target.minY - gap - height
        let rawLeft = target.midX - width / 2
        let clamped = CGPoint(
            x: max(16, min(screen.width - width - 16, rawLeft)),
            y: max(58, min(min(screen.height, Self.referenceHeight) - height - 24, rawTop))
        )
        let origin = settle(raw: CGPoint(x: rawLeft, y: rawTop), clamped: clamped)
        // The arrow points at the element from whichever edge faces it; a tip dragged over it has none.
        var arrow: CGPoint?
        let arrowX = origin.x + max(22, min(width - 22, target.midX - origin.x))
        if origin.y >= target.maxY - 2 {
            arrow = CGPoint(x: arrowX, y: origin.y + 2)
        } else if origin.y + height <= target.minY + 2 {
            arrow = CGPoint(x: arrowX, y: origin.y + height - 2)
        }
        return Layout(width: width, origin: origin, arrow: arrow)
    }

    // MARK: The card

    private func card(_ step: TourStep, width: CGFloat) -> some View {
        let words = step.words
        return VStack(alignment: .leading, spacing: 0) {
            if let position = env.tour.position {
                HStack(spacing: 4) {
                    ForEach(1...position.of, id: \.self) { i in
                        Capsule()
                            .fill(i <= position.at ? Palette.onBone : Palette.onBone.opacity(0.12))
                            .frame(height: 3)
                    }
                }
                .padding(.bottom, 10)
                .accessibilityHidden(true)
            }
            Text(words.title)
                .font(Typography.data(18, weight: .medium))
                .tracking(-0.27)
                .foregroundStyle(Palette.onBone)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.trailing, 26)
                .padding(.bottom, 6)
                .accessibilityAddTraits(.isHeader)
            Text(words.body)
                .font(Typography.data(14, weight: .regular))
                .lineSpacing(2)
                .foregroundStyle(boneText)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                if let position = env.tour.position {
                    Text(L10n("\(position.at) of \(position.of)"))
                        .font(Typography.mono(11))
                        .foregroundStyle(Color(hex: 0x71717A))
                }
                Spacer(minLength: 8)
                tipButton(step.welcome ? L10n("Not now") : L10n("Back"), dark: false) { env.tour.back() }
                tipButton(nextTitle(step), dark: true) { Haptics.select(); env.tour.next() }
            }
            .padding(.top, 14)
        }
        .padding(.top, 16)
        .padding(.horizontal, 16)
        .padding(.bottom, 14)
        .frame(width: width, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(bone))
        .shadow(color: .black.opacity(0.55), radius: 30, y: 24)
        .overlay(alignment: .topTrailing) {
            Button { env.tour.finish() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Palette.onBone)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Palette.onBone.opacity(0.07)))
            }
            .buttonStyle(.plain)
            .padding(10)
            .accessibilityLabel(L10n("Close"))
        }
    }

    private func nextTitle(_ step: TourStep) -> String {
        if step.welcome { return L10n("Show me") }
        return env.tour.isLast ? L10n("Done") : L10n("Next")
    }

    private func tipButton(_ title: String, dark: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if dark { Circle().fill(Palette.ember).frame(width: 8, height: 8).shadow(color: Palette.ember, radius: 4) }
                Text(title)
                    .font(Typography.data(13, weight: .medium))
                    .lineLimit(1)
                    .fixedSize()
            }
            .foregroundStyle(dark ? bone : Palette.onBone)
            .padding(.horizontal, 15)
            .frame(height: 36)
            .background(Capsule().fill(dark ? Palette.onBone : Palette.onBone.opacity(0.07)))
        }
        .buttonStyle(.plain)
    }
}

private extension CGRect {
    var minimumPoint: CGPoint { CGPoint(x: minX, y: minY) }
}

/// The whole screen with one rounded hole, drawn even-odd. Origin, size and radius animate,
/// so the hole glides from one element to the next.
private struct SpotlightShape: Shape {
    var origin: CGPoint
    var size: CGSize
    var radius: CGFloat
    let bounds: CGRect

    var animatableData: AnimatablePair<CGPoint.AnimatableData, AnimatablePair<CGSize.AnimatableData, CGFloat>> {
        get { .init(origin.animatableData, .init(size.animatableData, radius)) }
        set {
            origin.animatableData = newValue.first
            size.animatableData = newValue.second.first
            radius = newValue.second.second
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRect(bounds)
        path.addRoundedRect(in: CGRect(origin: origin, size: size), cornerSize: CGSize(width: radius, height: radius), style: .continuous)
        return path
    }
}
