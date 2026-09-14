import SwiftUI
import VisionKit

/// Full-bleed barcode scanner. Falls back to a dark empty state when VisionKit
/// cannot run (simulator, no camera, reduced capability).
struct BarcodeScannerView: View {
    var onCode: (String) -> Void
    var onCancel: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            Palette.ink.ignoresSafeArea()
            if DataScannerViewController.isSupported, DataScannerViewController.isAvailable {
                DataScannerRepresentable(onCode: onCode)
                    .ignoresSafeArea()
            } else {
                VStack(spacing: Space.sm) {
                    Spacer()
                    Image(systemName: "barcode.viewfinder")
                        .font(.system(size: 44, weight: .medium))
                        .foregroundStyle(Palette.lockScreenText)
                    Text("Point the camera at a barcode")
                        .font(Typography.voice(22))
                        .foregroundStyle(Palette.lockScreenText)
                    Text("Scanning needs a device with a camera.")
                        .font(Typography.data(14))
                        .foregroundStyle(Palette.lockScreenText.opacity(0.7))
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }

            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Palette.lockScreenText)
                    .frame(width: 40, height: 40)
                    .background(.white.opacity(0.18), in: Circle())
            }
            .padding(Space.gutter)
            .accessibilityLabel("Close scanner")
        }
        .statusBarHidden(true)
    }
}

private struct DataScannerRepresentable: UIViewControllerRepresentable {
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
        try? scanner.startScanning()
        return scanner
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {
        context.coordinator.onCode = onCode
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var onCode: (String) -> Void
        private var handled = false

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
        VStack(alignment: .leading, spacing: Space.md) {
            Capsule()
                .fill(Palette.inkFaint.opacity(0.4))
                .frame(width: 40, height: 5)
                .frame(maxWidth: .infinity)

            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Exact")
                        .font(Typography.data(11, weight: .bold))
                        .foregroundStyle(Palette.background)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Palette.dayOnTrack, in: Capsule())
                    Text(product.food.name)
                        .font(Typography.voice(24, weight: .medium))
                        .foregroundStyle(Palette.ink)
                    if let brand = product.food.brand, !brand.isEmpty {
                        Text(brand)
                            .font(Typography.data(14))
                            .foregroundStyle(Palette.inkSoft)
                    }
                }
                Spacer()
                Button(action: onSave) {
                    Image(systemName: "star")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Palette.accent)
                        .frame(width: 44, height: 44)
                        .background(Palette.accentTint, in: Circle())
                }
                .accessibilityLabel("Save as my meal")
            }

            HStack(spacing: 8) {
                macroTile("kcal", value: "\(portion.kcal)")
                macroTile("Protein", value: "\(Int(portion.proteinG.rounded())) g")
                macroTile("Carbs", value: "\(Int(portion.carbsG.rounded())) g")
                macroTile("Fat", value: "\(Int(portion.fatG.rounded())) g")
            }

            HStack {
                Text("Amount")
                    .font(Typography.data(14, weight: .semibold))
                    .foregroundStyle(Palette.inkSoft)
                Spacer()
                Button {
                    product.servings = max(0.5, (product.servings * 2 - 1) / 2)
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 14, weight: .bold))
                        .frame(width: 36, height: 36)
                        .background(Palette.surfaceSunk, in: Circle())
                }
                Text(product.servings == product.servings.rounded() ? "\(Int(product.servings))" : String(format: "%.1f", product.servings))
                    .font(Typography.data(22, weight: .heavy))
                    .foregroundStyle(Palette.ink)
                    .monospacedDigit()
                    .frame(minWidth: 36)
                Text("servings")
                    .font(Typography.data(13))
                    .foregroundStyle(Palette.inkFaint)
                Button {
                    product.servings = min(20, product.servings + 0.5)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .bold))
                        .frame(width: 36, height: 36)
                        .background(Palette.surfaceSunk, in: Circle())
                }
            }
            .foregroundStyle(Palette.ink)

            ActionButton(title: "Log for \(slotTitle.lowercased())", busy: logging, busyTitle: "Logging", action: onLog)

            Button("Not this", action: onClose)
                .font(Typography.data(14, weight: .semibold))
                .foregroundStyle(Palette.inkSoft)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, Space.gutter)
        .padding(.top, Space.sm)
        .padding(.bottom, Space.md)
        .background {
            UnevenRoundedRectangle(topLeadingRadius: 32, topTrailingRadius: 32, style: .continuous)
                .fill(Palette.background)
                .ignoresSafeArea(edges: .bottom)
        }
    }

    private func macroTile(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).sectionLabelStyle()
            Text(value)
                .font(Typography.data(18, weight: .heavy))
                .foregroundStyle(Palette.ink)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Palette.hairline))
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
