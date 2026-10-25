import AVFoundation
import PhotosUI
import SwiftUI
import VisionKit

/// Full-bleed barcode scanner with a frame to aim at. Scan, confirm and log all
/// happen here: a hit pauses the camera and raises the product card over it; a
/// miss offers a label photo (which adds the product for next time), another
/// scan, or typing. Falls back to a dark empty state when VisionKit cannot run
/// (simulator, no camera) and explains when camera access is off.
struct BarcodeScannerView: View {
    var status: LogMealViewModel.ScanStatus
    @Binding var product: LogMealViewModel.BarcodeProduct?
    /// The meal this lands under, for the card's label ("Barcode · lunch").
    var slotTitle: String
    /// Debug stubs only: draw the aiming frame where the simulator has no camera.
    var previewAiming = false
    var onCode: (String) -> Void
    var onRescan: () -> Void
    var onType: () -> Void
    var onLabelPhoto: (Data) -> Void
    var onLog: () -> Void
    var onSave: () -> Void
    /// The product has been saved as a meal (the card's Save turns into Saved).
    var saved = false
    /// "Save as my meal" opens over the scanner, so the card is still there after.
    var editor: Binding<SavedMealDraft?> = .constant(nil)
    var editorSaving = false
    var editorError: String?
    var onSaveEditor: (SavedMealDraft) async -> Bool = { _ in false }
    var onCancel: () -> Void

    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var camera: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
    @State private var showLabelCamera = false
    @State private var showLabelLibrary = false
    @State private var labelPickerItem: PhotosPickerItem?

    private static let frameSize = CGSize(width: 300, height: 180)

    var body: some View {
        screenBody.trackScreen("barcode_scanner")
    }

    private var canScan: Bool {
        DataScannerViewController.isSupported && camera == .authorized
    }

    @ViewBuilder
    private var screenBody: some View {
        ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea()
            if canScan {
                DataScannerRepresentable(active: status == .scanning) { code in
                    Haptics.select()
                    onCode(code)
                }
                .ignoresSafeArea()
                if status != .found { aimingOverlay }
            } else if previewAiming {
                if status != .found { aimingOverlay }
            } else if DataScannerViewController.isSupported, camera == .denied || camera == .restricted {
                emptyState(
                    title: "Camera access is off",
                    detail: "Turn on Camera for SetPoint in Settings to scan barcodes.",
                    action: ("Open Settings", {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    })
                )
            } else if DataScannerViewController.isSupported, camera == .notDetermined {
                Color.clear
            } else {
                emptyState(
                    title: "Point the camera at a barcode",
                    detail: "Scanning needs a device with a camera.",
                    action: ("Type it instead", onType)
                )
            }

            if status == .found, let current = product {
                Color.black.opacity(0.55)
                    .ignoresSafeArea()
                    .transition(.opacity)
                VStack(spacing: Space.md) {
                    Spacer()
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Palette.positive)
                        Text(current.food.code)
                            .font(Typography.mono(13))
                            .foregroundStyle(Palette.lockScreenText)
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 36)
                    .background(.black.opacity(0.5), in: Capsule())
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text("Barcode found"))
                    ScannedProductCard(
                        product: Binding(get: { product ?? current }, set: { product = $0 }),
                        slotTitle: slotTitle,
                        saved: saved,
                        onLog: onLog,
                        onSave: onSave,
                        onRescan: onRescan
                    )
                }
                .ignoresSafeArea(edges: .bottom)
                .transition(.move(edge: .bottom))
            }

            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Palette.lockScreenText)
                    .frame(width: 40, height: 40)
                    .background(.black.opacity(0.35), in: Circle())
            }
            .padding(Space.gutter)
            .accessibilityLabel("Close scanner")
        }
        .animation(Motion.adaptive(Motion.snappy, reduceMotion: reduceMotion), value: status)
        .statusBarHidden(true)
        .task {
            guard camera == .notDetermined else { return }
            _ = await AVCaptureDevice.requestAccess(for: .video)
            camera = AVCaptureDevice.authorizationStatus(for: .video)
        }
        .fullScreenCover(isPresented: $showLabelCamera) {
            CameraCapture(
                onPhoto: { data in
                    showLabelCamera = false
                    onLabelPhoto(data)
                },
                onCancel: { showLabelCamera = false }
            )
            .ignoresSafeArea()
        }
        .photosPicker(isPresented: $showLabelLibrary, selection: $labelPickerItem, matching: .images)
        .sheet(item: editor) { draft in
            SavedMealEditorView(draft: draft, saving: editorSaving, error: editorError, onSave: onSaveEditor)
        }
        .onChange(of: labelPickerItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) { onLabelPhoto(data) }
                labelPickerItem = nil
            }
        }
    }

    private func photographLabel() {
        if CameraCapture.isAvailable {
            showLabelCamera = true
        } else {
            showLabelLibrary = true
        }
    }

    /// Dimmed surround with a clear window, corner marks, and the hint/status below.
    private var aimingOverlay: some View {
        GeometryReader { geo in
            let size = Self.frameSize
            let rect = CGRect(
                x: (geo.size.width - size.width) / 2,
                y: geo.size.height * 0.36 - size.height / 2,
                width: size.width,
                height: size.height
            )
            ZStack(alignment: .topLeading) {
                Path { path in
                    path.addRect(CGRect(origin: .zero, size: geo.size))
                    path.addRoundedRect(in: rect, cornerSize: CGSize(width: 22, height: 22), style: .continuous)
                }
                .fill(Color.black.opacity(0.55), style: FillStyle(eoFill: true))

                ScanCorners()
                    .stroke(status == .scanning ? Palette.lockScreenText : Palette.positive,
                            style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .frame(width: rect.width, height: rect.height)
                    .offset(x: rect.minX, y: rect.minY)
                    .animation(.easeOut(duration: 0.2), value: status)

                VStack(spacing: Space.sm) {
                    Text("Line up the barcode inside the frame")
                        .font(Typography.data(15, weight: .medium))
                        .foregroundStyle(Palette.lockScreenText)
                        .multilineTextAlignment(.center)
                    statusPanel
                }
                .padding(.horizontal, Space.gutter)
                .frame(width: geo.size.width)
                .offset(y: rect.maxY + Space.md)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(true)
    }

    @ViewBuilder
    private var statusPanel: some View {
        switch status {
        case .scanning:
            Text("It scans on its own — no button to press.")
                .font(Typography.data(13))
                .foregroundStyle(Palette.lockScreenText.opacity(0.7))
                .multilineTextAlignment(.center)
        case .lookingUp:
            busyPill("Looking it up…")
        case .readingLabel:
            busyPill("Reading the label…")
        case .found:
            EmptyView()
        case .notFound:
            missPanel(
                title: "Not in the food database yet",
                detail: L10n("Snap the nutrition label and I’ll add it — next time it scans instantly.")
            )
        case let .failed(message):
            missPanel(title: nil, detail: message)
        }
    }

    private func busyPill(_ text: LocalizedStringKey) -> some View {
        HStack(spacing: 10) {
            ProgressView().tint(Palette.lockScreenText)
            Text(text)
                .font(Typography.data(14, weight: .medium))
                .foregroundStyle(Palette.lockScreenText)
        }
        .padding(.horizontal, 18)
        .frame(height: 44)
        .background(.black.opacity(0.45), in: Capsule())
    }

    private func missPanel(title: LocalizedStringKey?, detail: String) -> some View {
        VStack(spacing: Space.sm) {
            VStack(spacing: 4) {
                if let title {
                    Text(title)
                        .font(Typography.data(16, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                }
                Text(detail)
                    .font(title == nil ? Typography.data(15, weight: .medium) : Typography.data(13))
                    .foregroundStyle(title == nil ? Palette.ink : Palette.inkSoft)
                    .multilineTextAlignment(.center)
            }
            PillButton(title: L10n("Photograph the label"), action: photographLabel)
            HStack(spacing: 10) {
                PillButton(title: L10n("Scan again"), kind: .secondary, action: onRescan)
                PillButton(title: L10n("Type it instead"), kind: .secondary, action: onType)
            }
        }
        .padding(Space.md)
        .frame(maxWidth: 360)
        .background(Palette.sheet.opacity(0.96), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func emptyState(title: LocalizedStringKey, detail: LocalizedStringKey, action: (String, () -> Void)) -> some View {
        VStack(spacing: Space.sm) {
            Spacer()
            Image(systemName: "barcode.viewfinder")
                .font(.system(size: 44, weight: .medium))
                .foregroundStyle(Palette.lockScreenText)
            Text(title)
                .font(Typography.voice(22))
                .foregroundStyle(Palette.lockScreenText)
                .multilineTextAlignment(.center)
            Text(detail)
                .font(Typography.data(14))
                .foregroundStyle(Palette.lockScreenText.opacity(0.7))
                .multilineTextAlignment(.center)
            PillButton(title: L10nKey(action.0), kind: .secondary, action: action.1)
                .padding(.top, Space.xs)
            Spacer()
        }
        .padding(.horizontal, Space.gutter)
        .frame(maxWidth: .infinity)
    }
}

/// The four corner marks of the aiming frame.
private struct ScanCorners: Shape {
    func path(in rect: CGRect) -> Path {
        let arm: CGFloat = 28
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY + arm))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX + arm, y: rect.minY))
        p.move(to: CGPoint(x: rect.maxX - arm, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + arm))
        p.move(to: CGPoint(x: rect.maxX, y: rect.maxY - arm))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - arm, y: rect.maxY))
        p.move(to: CGPoint(x: rect.minX + arm, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - arm))
        return p
    }
}

/// VisionKit's scanner. `active` pauses it while a code is looked up and
/// restarts it for "Scan again".
private struct DataScannerRepresentable: UIViewControllerRepresentable {
    var active: Bool
    var onCode: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode) }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.ean8, .ean13, .upce, .code128])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        if active { try? scanner.startScanning() }
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        context.coordinator.onCode = onCode
        if active, !scanner.isScanning {
            context.coordinator.handled = false
            try? scanner.startScanning()
        } else if !active, scanner.isScanning {
            scanner.stopScanning()
        }
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var onCode: (String) -> Void
        var handled = false

        init(onCode: @escaping (String) -> Void) {
            self.onCode = onCode
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !handled else { return }
            for item in addedItems {
                if case let .barcode(barcode) = item, let payload = barcode.payloadStringValue {
                    handled = true
                    dataScanner.stopScanning()
                    onCode(payload)
                    return
                }
            }
        }
    }
}

/// The scanned product over the paused camera. Barcode data is the maker's own
/// label, so it reads as exact rather than an estimate; the amount is the only
/// thing to decide before logging.
struct ScannedProductCard: View {
    @Binding var product: LogMealViewModel.BarcodeProduct
    var slotTitle: String
    var saved = false
    var onLog: () -> Void
    var onSave: () -> Void
    var onRescan: () -> Void

    private var hasServing: Bool { (product.food.servingG ?? 0) > 0 }

    private var portion: (grams: Double, kcal: Int, proteinG: Double, carbsG: Double, fatG: Double) {
        product.food.portion(servings: product.servings)
    }

    /// Without a serving size on the pack, one step is 100 g.
    private var presets: [(value: Double, title: String)] {
        hasServing
            ? [(0.5, "½"), (1, "1"), (2, "2"), (3, "3")]
            : [(0.5, "50 g"), (1, "100 g"), (1.5, "150 g"), (2, "200 g")]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Capsule()
                .fill(Color.white.opacity(0.18))
                .frame(width: 40, height: 5)
                .frame(maxWidth: .infinity)

            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n("Barcode · \(slotTitle.lowercased())")).sectionLabelStyle()
                    FittingHeadline(product.food.name, size: 26)
                    Text(detailLine)
                        .font(Typography.data(13))
                        .foregroundStyle(Palette.inkSoft)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text("Label values")
                    .font(Typography.data(12, weight: .regular))
                    .foregroundStyle(Palette.positive)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Palette.positive.opacity(0.12), in: Capsule())
                    .fixedSize()
                    .padding(.top, 2)
            }

            HStack(spacing: 8) {
                let kcal = Double(max(portion.kcal, 1))
                macro("kcal", value: "\(portion.kcal)", fraction: 1, color: Palette.amber)
                macro("Protein", value: L10n("\(Int(portion.proteinG.rounded())) g"), fraction: portion.proteinG * 4 / kcal, color: Palette.amber)
                macro("Carbs", value: L10n("\(Int(portion.carbsG.rounded())) g"), fraction: portion.carbsG * 4 / kcal, color: Palette.ink)
                macro("Fat", value: L10n("\(Int(portion.fatG.rounded())) g"), fraction: portion.fatG * 9 / kcal, color: Palette.inkFaint)
            }
            .animation(.snappy(duration: 0.2), value: product.servings)

            amount

            HStack(spacing: 10) {
                ActionButton(title: L10n("Log \(portion.kcal) kcal"), symbol: "plus", action: onLog)
                Button {
                    Haptics.select()
                    onSave()
                } label: {
                    Label(saved ? "Saved" : "Save", systemImage: saved ? "star.fill" : "star")
                        .font(Typography.data(15, weight: .regular))
                        .foregroundStyle(saved ? Palette.amber : Palette.ink)
                        .frame(width: 96, height: 58)
                        .glassCapsule(fill: Color.white.opacity(0.06), stroke: Color.white.opacity(0.10))
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(PressableCard())
                .disabled(saved)
                .accessibilityLabel(saved ? "Saved as my meal" : "Save as my meal")
            }

            Button("Not this — scan again", action: onRescan)
                .font(Typography.data(14, weight: .regular))
                .foregroundStyle(Palette.inkSoft)
                .frame(maxWidth: .infinity, minHeight: 36)
        }
        .padding(.horizontal, Space.gutter)
        .padding(.top, Space.sm)
        .padding(.bottom, Space.lg)
        .background {
            UnevenRoundedRectangle(topLeadingRadius: 32, topTrailingRadius: 32, style: .continuous)
                .fill(Palette.sheet)
                .ignoresSafeArea(edges: .bottom)
        }
    }

    private var detailLine: String {
        var parts: [String] = []
        if let brand = product.food.brand, !brand.isEmpty { parts.append(brand) }
        if let serving = product.food.servingG, serving > 0 {
            parts.append(L10n("1 serving = \(Int(serving.rounded())) g"))
        } else {
            parts.append(L10n("per 100 g"))
        }
        return parts.joined(separator: " · ")
    }

    /// Quick picks for the usual amounts, fine steps on the side.
    private var amount: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("How much").sectionLabelStyle()
                Text(L10n("\(Int(portion.grams.rounded())) g"))
                    .font(Typography.mono(12))
                    .foregroundStyle(Palette.inkFaint)
                    .contentTransition(.numericText(value: portion.grams))
                Spacer()
                stepper
            }
            HStack(spacing: 8) {
                ForEach(presets, id: \.value) { preset in
                    let selected = abs(product.servings - preset.value) < 0.01
                    Button {
                        product.servings = preset.value
                        Haptics.select()
                    } label: {
                        Text(preset.title)
                            .font(Typography.data(15, weight: selected ? .semibold : .regular))
                            .foregroundStyle(selected ? Palette.onBone : Palette.ink)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background {
                                if selected {
                                    Capsule().fill(Palette.ink)
                                } else {
                                    Capsule().fill(Color.white.opacity(0.06))
                                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.10)))
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
    }

    private var stepper: some View {
        HStack(spacing: 0) {
            stepButton("minus", label: "Less", enabled: product.servings > 0.5) {
                product.servings = max(0.5, product.servings - 0.5)
            }
            Text(servingsText)
                .font(Typography.data(15, weight: .medium))
                .foregroundStyle(Palette.ink)
                .frame(minWidth: 34)
                .contentTransition(.numericText(value: product.servings))
            stepButton("plus", label: "More", enabled: product.servings < 20) {
                product.servings = min(20, product.servings + 0.5)
            }
        }
        .glassCapsule(fill: Color.white.opacity(0.05), stroke: Color.white.opacity(0.10))
    }

    private var servingsText: String {
        let s = product.servings
        if !hasServing { return L10n("\(Int((s * 100).rounded())) g") }
        if s == 0.5 { return "½" }
        return s == s.rounded() ? "\(Int(s))" : String(format: "%.1f", s)
    }

    private func stepButton(_ symbol: String, label: LocalizedStringKey, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button {
            action()
            Haptics.select()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(enabled ? Palette.ink : Palette.inkFaint.opacity(0.5))
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(label)
    }

    private func macro(_ label: String, value: String, fraction: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(LocalizedStringKey(label)).sectionLabelStyle()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(value)
                .font(Typography.data(18, weight: .regular))
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText())
            GeometryReader { box in
                Capsule().fill(Color.white.opacity(0.08))
                    .overlay(alignment: .leading) {
                        Capsule().fill(color)
                            .frame(width: box.size.width * min(1, max(0, fraction)))
                    }
            }
            .frame(height: 5)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass(radius: 14)
        .accessibilityElement(children: .combine)
    }
}

/// USDA catalog pick: amount in grams, then log or save.
struct CatalogFoodSheet: View {
    @Binding var pick: LogMealViewModel.CatalogPick
    var slotTitle: String
    var logging = false
    var onLog: () -> Void
    var onSave: () -> Void
    var onClose: () -> Void

    private var portion: (grams: Double, kcal: Int, proteinG: Double, carbsG: Double, fatG: Double) {
        pick.food.portion(grams: pick.grams)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Capsule()
                .fill(Color.white.opacity(0.18))
                .frame(width: 40, height: 5)
                .frame(maxWidth: .infinity)

            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Foods").sectionLabelStyle(Palette.positive)
                    Headline(pick.food.name, size: 26)
                    Text(detailLine)
                        .font(Typography.data(13, weight: .regular))
                        .foregroundStyle(Palette.inkSoft)
                }
                Spacer(minLength: 8)
                RoundIconButton("star", label: "Save as my meal", action: onSave)
            }

            HStack(spacing: 8) {
                macroTile("kcal", value: "\(portion.kcal)")
                macroTile("Protein", value: L10n("\(Int(portion.proteinG.rounded())) g"))
                macroTile("Carbs", value: L10n("\(Int(portion.carbsG.rounded())) g"))
                macroTile("Fat", value: L10n("\(Int(portion.fatG.rounded())) g"))
            }

            GlassList {
                StepperRow(
                    name: "Amount",
                    note: pick.food.servingDesc,
                    value: "\(Int(pick.grams.rounded())) g",
                    valueWidth: 80,
                    canDown: pick.grams > 25,
                    canUp: pick.grams < 2000,
                    onDown: { pick.grams = max(25, pick.grams - 25) },
                    onUp: { pick.grams = min(2000, pick.grams + 25) }
                )
            }

            VStack(spacing: 4) {
                ActionButton(
                    title: L10n("Log \(portion.kcal) kcal · \(slotTitle.lowercased())"),
                    busy: logging,
                    busyTitle: "Logging",
                    symbol: "plus",
                    action: onLog
                )
                Button("Not this", action: onClose)
                    .font(Typography.data(14, weight: .regular))
                    .foregroundStyle(Palette.inkSoft)
                    .frame(maxWidth: .infinity, minHeight: 40)
            }
        }
        .padding(.horizontal, Space.gutter)
        .padding(.top, Space.sm)
        .padding(.bottom, Space.md)
        .background {
            UnevenRoundedRectangle(topLeadingRadius: 32, topTrailingRadius: 32, style: .continuous)
                .fill(Palette.sheet)
                .ignoresSafeArea(edges: .bottom)
        }
    }

    private var detailLine: String {
        var parts: [String] = []
        if let category = pick.food.category, !category.isEmpty { parts.append(category) }
        parts.append(L10n("\(Int(portion.grams.rounded())) g"))
        return parts.joined(separator: " · ")
    }

    private func macroTile(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(LocalizedStringKey(label))
                .font(Typography.mono(9))
                .tracking(1.1)
                .textCase(.uppercase)
                .foregroundStyle(Palette.inkFaint)
            Text(value)
                .font(Typography.data(18, weight: .regular))
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass(radius: 14)
    }
}

#if DEBUG
#Preview("Scanned product") {
    Color.black.ignoresSafeArea()
        .safeAreaInset(edge: .bottom) {
            ScannedProductCard(
                product: .constant(.init(food: .sampleYogurt, servings: 1)),
                slotTitle: "Lunch",
                onLog: {},
                onSave: {},
                onRescan: {}
            )
        }
}
#endif
