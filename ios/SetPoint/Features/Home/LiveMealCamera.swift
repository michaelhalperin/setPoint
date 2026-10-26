import AVFoundation
import SwiftUI
import UIKit

/// The camera that runs inside the log sheet: point it at the plate and tap the
/// shutter. The photo goes straight to being read, like the full-screen camera.
struct LiveMealCamera: View {
    var onPhoto: (Data) -> Void
    var onLibrary: () -> Void
    var disabled = false

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var camera = MealCameraSession()
    @State private var status: MealCameraSession.Status = .starting
    @State private var flash = false
    @State private var capturing = false

    static let height: CGFloat = 300

    var body: some View {
        ZStack {
            Color.black

            switch status {
            case .starting, .running:
                CameraPreview(session: camera.session)
                    .opacity(status == .running ? 1 : 0)
                    .animation(.easeOut(duration: 0.25), value: status)
            case .denied:
                notice(
                    title: "Camera is off",
                    detail: "Turn on Camera for SetPoint in Settings to snap a meal.",
                    action: ("Open Settings", openSettings)
                )
            case .unavailable:
                notice(title: "No camera here", detail: "Choose a photo from your library instead.", action: nil)
            }

            Color.white
                .opacity(flash ? 0.85 : 0)
                .allowsHitTesting(false)

            VStack {
                if status == .running {
                    Text("Point at your plate")
                        .font(Typography.data(12, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .frame(height: 28)
                        .background(.ultraThinMaterial, in: Capsule())
                        .environment(\.colorScheme, .dark)
                        .padding(.top, 14)
                        .transition(.opacity)
                }
                Spacer()
                controls
            }
        }
        .frame(height: Self.height)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Palette.hairline))
        .task { await begin() }
        .onDisappear { camera.stop() }
        .onChange(of: scenePhase) { _, phase in
            guard status == .running || status == .starting else { return }
            if phase == .active { camera.start() } else { camera.stop() }
        }
    }

    private var controls: some View {
        HStack {
            Button(action: onLibrary) {
                Image(systemName: "photo.on.rectangle")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(.ultraThinMaterial, in: Circle())
                    .environment(\.colorScheme, .dark)
            }
            .accessibilityLabel("Choose from library")

            Spacer()

            if status == .running {
                Button(action: shoot) {
                    ZStack {
                        Circle().strokeBorder(.white, lineWidth: 4).frame(width: 70, height: 70)
                        Circle().fill(.white).frame(width: 56, height: 56)
                            .scaleEffect(capturing ? 0.86 : 1)
                    }
                }
                .buttonStyle(.plain)
                .disabled(disabled || capturing)
                .accessibilityLabel("Take photo")
            }

            Spacer()

            // Balances the library button so the shutter sits in the middle.
            Color.clear.frame(width: 48, height: 48)
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 16)
        .animation(Motion.adaptive(Motion.snappy, reduceMotion: reduceMotion), value: capturing)
    }

    private func notice(title: LocalizedStringKey, detail: LocalizedStringKey, action: (LocalizedStringKey, () -> Void)?) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "camera")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(Palette.inkFaint)
            Text(title)
                .font(Typography.data(15, weight: .medium))
                .foregroundStyle(Palette.ink)
            Text(detail)
                .font(Typography.data(13, weight: .regular))
                .foregroundStyle(Palette.inkSoft)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let action {
                Button(action.0, action: action.1)
                    .font(Typography.data(13, weight: .medium))
                    .foregroundStyle(Palette.amber)
                    .padding(.top, 4)
            }
        }
        .padding(.horizontal, 32)
        .padding(.bottom, 56)
    }

    private func begin() async {
        guard camera.hasCamera else {
            status = .unavailable
            return
        }
        guard await MealCameraSession.requestAccess() else {
            status = .denied
            return
        }
        await camera.startAndWait()
        status = camera.isRunning ? .running : .unavailable
    }

    private func shoot() {
        guard !capturing else { return }
        capturing = true
        Haptics.select()
        withAnimation(.easeOut(duration: 0.06)) { flash = true }
        Task {
            let data = await camera.capture()
            withAnimation(.easeIn(duration: 0.3)) { flash = false }
            capturing = false
            if let data { onPhoto(data) }
        }
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}

/// One back-camera session with a photo output. Configured and run on its own
/// queue, since starting a capture session blocks.
final class MealCameraSession: NSObject, @unchecked Sendable {
    enum Status { case starting, running, denied, unavailable }

    let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "setpoint.meal-camera")
    private var configured = false
    private var pending: CheckedContinuation<Data?, Never>?

    var hasCamera: Bool {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) != nil
    }

    var isRunning: Bool { session.isRunning }

    /// True once access is granted; asks the first time.
    static func requestAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .video)
        default: return false
        }
    }

    func start() {
        queue.async { [self] in run() }
    }

    func startAndWait() async {
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            queue.async { [self] in
                run()
                done.resume()
            }
        }
    }

    func stop() {
        queue.async { [self] in
            if session.isRunning { session.stopRunning() }
        }
    }

    /// A JPEG of what the camera sees, or nil if it isn't running.
    func capture() async -> Data? {
        await withCheckedContinuation { cont in
            queue.async { [self] in
                guard configured, session.isRunning, pending == nil else {
                    cont.resume(returning: nil)
                    return
                }
                pending = cont
                if let connection = output.connection(with: .video), connection.isVideoRotationAngleSupported(90) {
                    connection.videoRotationAngle = 90
                }
                let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
                settings.photoQualityPrioritization = .speed
                output.capturePhoto(with: settings, delegate: self)
            }
        }
    }

    private func run() {
        configureIfNeeded()
        if configured, !session.isRunning { session.startRunning() }
    }

    private func configureIfNeeded() {
        guard !configured,
              let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device)
        else { return }
        session.beginConfiguration()
        session.sessionPreset = .photo
        if session.canAddInput(input) { session.addInput(input) }
        if session.canAddOutput(output) { session.addOutput(output) }
        session.commitConfiguration()
        configured = true
    }
}

extension MealCameraSession: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let data = error == nil ? photo.fileDataRepresentation() : nil
        queue.async { [self] in
            pending?.resume(returning: data)
            pending = nil
        }
    }
}

/// The live picture, filling its frame.
private struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}
