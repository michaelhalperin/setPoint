#if DEBUG
import SwiftUI

/// A tab as the tour sees it, with sample data and the real floating nav, for screenshots and
/// for reading element frames: `-uiStub tour-today | tour-train | tour-progress | tour-you`.
/// `-tourStep <id>` runs that step over it; `-dumpTourFrames` writes each element's frame to
/// the app's Documents folder (tour-frames-<tab>.json), which is where the admin's phone
/// preview gets its numbers.
struct TourShellStub: View {
    let tab: MainTabView.Tab
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        NavigationStack {
            content
                .toolbar(.hidden, for: .navigationBar)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    FloatingNav(selection: tab, onSelect: { _ in }, onLog: {})
                }
        }
        .overlayPreferenceValue(TourAnchorKey.self) { anchors in
            GeometryReader { proxy in
                let frames = anchors.mapValues { proxy[$0] }
                ZStack {
                    if env.tour.isActive { TourOverlay(proxy: proxy, anchors: anchors) }
                    FrameDumper(tab: tab, frames: frames, size: proxy.size)
                }
            }
            .ignoresSafeArea()
        }
        .task {
            if let id = Self.argument("-tourStep") { env.tour.debugShow(stepID: id) }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch tab {
        case .today: HomeContent(model: .previewed(.loaded(.sampleTopUp)), previewLogger: .sampleQuickLog)
        case .training: TrainingScreen(preview: .sample, isTabRoot: true)
        case .week: SettlementView(previewModel: .previewed(.sample))
        case .you: SettingsView(previewModel: .previewed(admin: false))
        }
    }

    static func argument(_ flag: String) -> String? {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: flag), args.indices.contains(i + 1) else { return nil }
        return args[i + 1]
    }
}

/// Waits until the screen has stopped moving, then writes the frames it last saw.
private struct FrameDumper: View {
    let tab: MainTabView.Tab
    let frames: [String: CGRect]
    let size: CGSize

    var body: some View {
        Color.clear.task(id: frames) {
            guard CommandLine.arguments.contains("-dumpTourFrames") else { return }
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            var out: [String: [Double]] = [:]
            for (id, r) in frames {
                let values: [Double] = [r.minX, r.minY, r.width, r.height].map { Double($0) }
                out[id] = values.map { (($0 * 10).rounded()) / 10 }
            }
            let payload: [String: Any] = ["screen": [size.width, size.height], "anchors": out]
            guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys, .prettyPrinted]),
                  let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
            try? data.write(to: docs.appendingPathComponent("tour-frames-\(tab.screenName).json"))
        }
    }
}

extension TourController {
    /// Shows one step by id, wherever the tour is.
    func debugShow(stepID: String) {
        guard let i = tour.steps.firstIndex(where: { $0.id == stepID }) else { return }
        showForDebug(at: i)
    }
}
#endif
