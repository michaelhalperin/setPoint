import AVFoundation
import SwiftUI
import VisionKit

/// Full-bleed barcode scanner with a frame to aim at. It stays up while the code
/// is looked up, and a miss is answered here (scan again / type it) rather than
/// by closing. Falls back to a dark empty state when VisionKit cannot run
/// (simulator, no camera) and explains when camera access is off.
struct BarcodeScannerView: View {
    var status: LogMealViewModel.ScanStatus
    /// Debug stubs only: draw the aiming frame where the simulator has no camera.
    var previewAiming = false
    var onCode: (String) -> Void
    var onRescan: () -> Void
    var onType: () -> Void
    var onCancel: () -> Void

    @Environment(\.openURL) private var openURL
    @State private var camera: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)

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
                aimingOverlay
            } else if previewAiming {
                aimingOverlay
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
        .statusBarHidden(true)
        .task {
            guard camera == .notDetermined else { return }
            _ = await AVCaptureDevice.requestAccess(for: .video)
            camera = AVCaptureDevice.authorizationStatus(for: .video)
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
            HStack(spacing: 10) {
                ProgressView().tint(Palette.lockScreenText)
                Text("Looking it up…")
                    .font(Typography.data(14, weight: .medium))
                    .foregroundStyle(Palette.lockScreenText)
            }
            .padding(.horizontal, 18)
            .frame(height: 44)
            .background(.black.opacity(0.45), in: Capsule())
        case .notFound:
            missPanel(
                title: "Not in the food database",
                detail: L10n("Some products aren’t listed yet. Type what it is and I’ll work it out.")
            )
        case let .failed(message):
            missPanel(title: "Couldn't look that up", detail: message)
        }
    }

    private func missPanel(title: LocalizedStringKey, detail: String) -> some View {
        VStack(spacing: Space.sm) {
            VStack(spacing: 4) {
                Text(title)
                    .font(Typography.data(16, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                Text(detail)
                    .font(Typography.data(13))
                    .foregroundStyle(Palette.inkSoft)
                    .multilineTextAlignment(.center)
            }
            HStack(spacing: 10) {
                PillButton(title: L10n("Scan again"), kind: .secondary, action: onRescan)
                PillButton(title: L10n("Type it instead"), action: onType)
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

/// Product sheet after a scan: Exact badge, macro tiles, amount stepper,
/// "Log for <slot>", star to save.
struct BarcodeProductSheet: View {
    @Binding var product: LogMealViewModel.BarcodeProduct
    var slotTitle: String
    var logging = false
    var onLog: () -> Void
    var onSave: () -> Void
    var onClose: () -> Void

    private var portion: (grams: Double, kcal: Int, proteinG: Double, carbsG: Double, fatG: Double) {
        product.food.portion(servings: product.servings)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Capsule()
                .fill(Color.white.opacity(0.18))
                .frame(width: 40, height: 5)
                .frame(maxWidth: .infinity)

            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Found").sectionLabelStyle(Palette.positive)
                    Headline(product.food.name, size: 26)
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
                    name: (product.food.servingG ?? 0) > 0 ? "Servings" : "Amount",
                    // No serving size on the label: each step is 100 g.
                    note: (product.food.servingG ?? 0) > 0 ? nil : "× 100 g",
                    value: product.servings == product.servings.rounded() ? "\(Int(product.servings))" : String(format: "%.1f", product.servings),
                    canDown: product.servings > 0.5,
                    canUp: product.servings < 20,
                    onDown: { product.servings = max(0.5, (product.servings * 2 - 1) / 2) },
                    onUp: { product.servings = min(20, product.servings + 0.5) }
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
        if let brand = product.food.brand, !brand.isEmpty { parts.append(brand) }
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
#Preview("Product") {
    Color.black.ignoresSafeArea()
        .safeAreaInset(edge: .bottom) {
            BarcodeProductSheet(
                product: .constant(.init(food: .sampleYogurt, servings: 1)),
                slotTitle: "Lunch",
                onLog: {},
                onSave: {},
                onClose: {}
            )
        }
}
#endif
