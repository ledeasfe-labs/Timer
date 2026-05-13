import SwiftUI
import UIKit
import Combine
import AVFoundation
import CoreMotion

// MARK: - Color Extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:  (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:  (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:  (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default: (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(.sRGB, red: Double(r)/255, green: Double(g)/255, blue: Double(b)/255, opacity: Double(a)/255)
    }
}

// MARK: - Theme (static helpers only — bg/accent are dynamic via AppSettings)

enum Theme {
    static let overlay = Color(hex: "1E1E22")
    static let text    = Color.white
    static let dim     = Color(white: 0.30)

    static func display(_ size: CGFloat) -> Font {
        .system(size: size, weight: .thin, design: .rounded)
    }
    static let label = Font.system(size: 10, weight: .semibold)
}

// MARK: - AppSettings (namespace for presets + bg helper)

enum AppSettings {
    static func bg(for mode: String) -> Color {
        switch mode {
        case "navy":     return Color(hex: "06091A")
        case "midnight": return Color(hex: "040407")
        case "forest":   return Color(hex: "060C08")
        case "dusk":     return Color(hex: "0E0816")
        default:         return Color(hex: "070708")
        }
    }

    static let bgPresets: [(name: String, mode: String)] = [
        ("Dark",     "dark"),
        ("Navy",     "navy"),
        ("Midnight", "midnight"),
        ("Forest",   "forest"),
        ("Dusk",     "dusk"),
    ]
    static let accentPresets: [(name: String, hex: String)] = [
        ("Amber",  "FF9500"),
        ("Blue",   "5AC8FA"),
        ("Rose",   "FF2D55"),
        ("Mint",   "30D158"),
        ("Purple", "BF5AF2"),
        ("Gold",   "FFD60A"),
    ]
    static let warningSounds: [(name: String, id: String)] = [
        ("Ping",   "ping"),
        ("Double", "double"),
        ("Bell",   "bell"),
    ]
    static let melodyPatterns: [(name: String, id: String)] = [
        ("Ascend",  "ascend"),
        ("Cascade", "cascade"),
        ("Wave",    "wave"),
        ("Pulse",   "pulse"),
    ]
}

// MARK: - Haptics

final class HapticManager {
    static let shared = HapticManager()
    private let selection = UISelectionFeedbackGenerator()
    private let light     = UIImpactFeedbackGenerator(style: .light)
    private let medium    = UIImpactFeedbackGenerator(style: .medium)
    private let heavy     = UIImpactFeedbackGenerator(style: .heavy)
    private let notify    = UINotificationFeedbackGenerator()
    private var hapticsEnabled: Bool {
        UserDefaults.standard.object(forKey: "hapticsEnabled") as? Bool ?? true
    }
    private init() { selection.prepare(); heavy.prepare() }

    func tick()     { guard hapticsEnabled else { return }; selection.selectionChanged() }
    func tap()      { guard hapticsEnabled else { return }; light.impactOccurred(intensity: 0.7) }
    func start()    { guard hapticsEnabled else { return }; heavy.impactOccurred(intensity: 1.0) }
    func stop()     { guard hapticsEnabled else { return }; medium.impactOccurred(intensity: 0.6) }
    func lap()      { guard hapticsEnabled else { return }; light.impactOccurred(intensity: 0.9) }
    func reset()    { guard hapticsEnabled else { return }; medium.impactOccurred(intensity: 0.4) }
    func complete() { guard hapticsEnabled else { return }; notify.notificationOccurred(.success) }
    func warning()  { guard hapticsEnabled else { return }; notify.notificationOccurred(.warning) }
}

// MARK: - SoundManager

final class SoundManager {
    static let shared = SoundManager()
    private let engine = AVAudioEngine()
    private let node   = AVAudioPlayerNode()
    private let rate   = 44100.0
    private var looping = false
    private var loopID  = UUID()

    private var soundEnabled: Bool {
        UserDefaults.standard.object(forKey: "soundEnabled") as? Bool ?? true
    }

    private init() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, options: .mixWithOthers)
        try? AVAudioSession.sharedInstance().setActive(true)
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode,
                       format: AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)!)
        try? engine.start()
    }

    func startLoop() {
        guard soundEnabled else { return }
        looping = true
        let id = UUID(); loopID = id
        let st = UserDefaults.standard.integer(forKey: "pitchSemitones")
        let pat = UserDefaults.standard.string(forKey: "melodyPattern") ?? "ascend"
        playPhrase(id: id, semitones: st, pattern: pat)
    }

    func stopLoop() { looping = false; node.stop() }

    func complete() {
        guard soundEnabled else { return }
        let sh = pow(2.0, Double(UserDefaults.standard.integer(forKey: "pitchSemitones")) / 12.0)
        chime([(523.25*sh, 0.00, 0.18), (659.25*sh, 0.13, 0.18), (783.99*sh, 0.26, 0.42)], amp: 0.36)
    }

    func warning() {
        guard soundEnabled else { return }
        playWarning(type: UserDefaults.standard.string(forKey: "warningSound") ?? "ping")
    }

    func phaseTransition() {
        guard soundEnabled else { return }
        chime([(1046.5, 0.00, 0.07), (1318.5, 0.09, 0.07)], amp: 0.26)
    }

    func previewWarning(type: String) { playWarning(type: type) }

    func previewTone(semitones: Int) {
        let sh = pow(2.0, Double(semitones) / 12.0)
        play(freq: 523.25 * sh, dur: 0.07, amp: 0.18)
    }

    func previewPattern(semitones: Int, pattern: String) {
        let sh = pow(2.0, Double(semitones) / 12.0)
        for note in phraseNotes(pattern: pattern, shift: sh) {
            DispatchQueue.main.asyncAfter(deadline: .now() + note.delay) {
                self.play(freq: note.freq, dur: note.dur, amp: 0.28)
            }
        }
    }

    private func phraseNotes(pattern: String, shift: Double) -> [(freq: Double, delay: Double, dur: Double)] {
        let t = 523.25 * shift; let th = 659.25 * shift; let fi = 783.99 * shift
        switch pattern {
        case "cascade": return [(fi, 0.00, 0.16), (th, 0.19, 0.16), (t, 0.38, 0.20), (t, 0.64, 0.38)]
        case "wave":    return [(t, 0.00, 0.11), (fi, 0.13, 0.11), (th, 0.26, 0.11), (fi, 0.39, 0.11), (t, 0.54, 0.32)]
        case "pulse":   return [(t, 0.00, 0.08), (t, 0.10, 0.08), (fi, 0.24, 0.12), (th, 0.40, 0.10), (t, 0.56, 0.32)]
        default:        return [(t, 0.00, 0.13), (th, 0.14, 0.13), (fi, 0.28, 0.18),
                                (th, 0.47, 0.13), (th * (8.0/9.0), 0.61, 0.13), (t, 0.75, 0.36)]
        }
    }

    private func playWarning(type: String) {
        switch type {
        case "double": chime([(880.0, 0.00, 0.06), (1108.0, 0.10, 0.06)], amp: 0.20)
        case "bell":   chime([(1046.5, 0.00, 0.14)], amp: 0.18)
        default:       chime([(880.0,  0.00, 0.07)], amp: 0.20)
        }
    }

    private func playPhrase(id: UUID, semitones: Int, pattern: String) {
        guard looping, loopID == id else { return }
        let shift = pow(2.0, Double(semitones) / 12.0)
        for note in phraseNotes(pattern: pattern, shift: shift) {
            DispatchQueue.main.asyncAfter(deadline: .now() + note.delay) { [weak self] in
                guard let self, self.looping, self.loopID == id else { return }
                self.play(freq: note.freq, dur: note.dur, amp: 0.34)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.46) { [weak self] in
            self?.playPhrase(id: id, semitones: semitones, pattern: pattern)
        }
    }

    private func chime(_ notes: [(Double, Double, Double)], amp: Float) {
        for (freq, delay, dur) in notes {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { self.play(freq: freq, dur: dur, amp: amp) }
        }
    }

    private func play(freq: Double, dur: Double, amp: Float) {
        let frames = AVAudioFrameCount(rate * dur)
        let fmt = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)!
        guard let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: frames) else { return }
        buf.frameLength = frames
        let ch = buf.floatChannelData![0]
        let atk = 0.008, rel = dur * 0.28
        for i in 0..<Int(frames) {
            let t = Double(i) / rate
            let env: Float = t < atk ? Float(t / atk) : (t > dur - rel ? Float((dur - t) / rel) : 1)
            ch[i] = amp * env * Float(sin(2 * Double.pi * freq * t))
        }
        if !engine.isRunning { try? engine.start() }
        node.scheduleBuffer(buf)
        if !node.isPlaying { node.play() }
    }
}

// MARK: - GyroManager

final class GyroManager: ObservableObject {
    static let shared = GyroManager()
    private let motion = CMMotionManager()
    @Published var angle: Double = 0
    private var screenAngle: Double = 0

    private init() {
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        NotificationCenter.default.addObserver(self, selector: #selector(orientationChanged),
                                               name: UIDevice.orientationDidChangeNotification, object: nil)
        refreshScreenAngle()
    }

    @objc private func orientationChanged() {
        refreshScreenAngle()
        angle = 0
    }

    private func refreshScreenAngle() {
        switch UIDevice.current.orientation {
        case .landscapeLeft:      screenAngle = -.pi / 2
        case .landscapeRight:     screenAngle = .pi / 2
        case .portraitUpsideDown: screenAngle = .pi
        case .portrait:           screenAngle = 0
        default: break
        }
    }

    func start() {
        guard motion.isAccelerometerAvailable, !motion.isAccelerometerActive else { return }
        motion.accelerometerUpdateInterval = 1.0 / 30.0
        motion.startAccelerometerUpdates(to: .main) { [weak self] data, _ in
            guard let self, let data else { return }
            let a = data.acceleration
            var raw = atan2(a.x, -a.y) - self.screenAngle
            if raw >  .pi { raw -= 2 * .pi }
            if raw < -.pi { raw += 2 * .pi }
            self.angle = self.angle * 0.93 + raw * 0.07
        }
    }

    func stop() {
        motion.stopAccelerometerUpdates()
        angle = 0
    }
}

struct GyroLevelModifier: ViewModifier {
    @ObservedObject private var gyro = GyroManager.shared
    @AppStorage("gyroLevel") private var gyroLevel = false

    func body(content: Content) -> some View {
        content.rotationEffect(.radians(gyroLevel ? -gyro.angle : 0))
    }
}

extension View {
    func gyroLeveled() -> some View { modifier(GyroLevelModifier()) }
}

// MARK: - UnifiedDragView

struct UnifiedDragView: UIViewRepresentable {
    var onChanged: (CGFloat, Int) -> Void
    var onTouchCountChange: (Int) -> Void
    var onEnd: () -> Void

    func makeUIView(context: Context) -> UIView {
        let v = UIView(); v.backgroundColor = .clear
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pan))
        pan.minimumNumberOfTouches = 1
        pan.maximumNumberOfTouches = 10
        pan.cancelsTouchesInView = false
        v.addGestureRecognizer(pan)
        return v
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onChanged = onChanged
        context.coordinator.onTouchCountChange = onTouchCountChange
        context.coordinator.onEnd = onEnd
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject {
        var onChanged: (CGFloat, Int) -> Void
        var onTouchCountChange: (Int) -> Void
        var onEnd: () -> Void
        var prevY: CGFloat = 0
        var lastTC = 0

        init(_ p: UnifiedDragView) {
            onChanged = p.onChanged
            onTouchCountChange = p.onTouchCountChange
            onEnd = p.onEnd
        }

        @objc func pan(_ g: UIPanGestureRecognizer) {
            let y = g.translation(in: g.view).y
            let tc = g.numberOfTouches

            switch g.state {
            case .began:
                prevY = y; lastTC = tc; onTouchCountChange(tc)
            case .changed:
                if tc != lastTC {
                    prevY = y; lastTC = tc; onTouchCountChange(tc); return
                }
                let delta = prevY - y; prevY = y
                onChanged(delta, tc)
            case .ended, .cancelled:
                lastTC = 0; onTouchCountChange(0); onEnd()
            default: break
            }
        }
    }
}

// MARK: - ScreenBorderRing

struct ScreenBorderRing: View {
    var progress: Double
    var color: Color = Color(hex: "FF9500")
    var pulsing: Bool = false

    @State private var glow = false

    var body: some View {
        GeometryReader { geo in
            let p = max(0.001, min(1.0, progress))
            let inset: CGFloat = 14
            let w = geo.size.width  - inset * 2
            let h = geo.size.height - inset * 2
            let cr: CGFloat = 26

            ZStack {
                RoundedRectangle(cornerRadius: cr, style: .continuous)
                    .stroke(color.opacity(0.08), lineWidth: 1.5)
                RoundedRectangle(cornerRadius: cr, style: .continuous)
                    .trim(from: 0, to: p)
                    .stroke(color.opacity(pulsing ? (glow ? 0.62 : 0.14) : 0.3),
                            style: StrokeStyle(lineWidth: 24, lineCap: .round))
                    .blur(radius: 24)
                RoundedRectangle(cornerRadius: cr, style: .continuous)
                    .trim(from: 0, to: p)
                    .stroke(color.opacity(pulsing ? (glow ? 1.0 : 0.38) : 0.65),
                            style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .blur(radius: 6)
                RoundedRectangle(cornerRadius: cr, style: .continuous)
                    .trim(from: 0, to: p)
                    .stroke(color, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
            }
            .frame(width: w, height: h)
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
            .animation(.linear(duration: 1.0 / 30.0), value: p)
            .onChange(of: pulsing) { _, isPulsing in
                if isPulsing {
                    withAnimation(.easeInOut(duration: 0.65).repeatForever(autoreverses: true)) { glow = true }
                } else {
                    withAnimation(.easeOut(duration: 0.4)) { glow = false }
                }
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - GlassButton

struct GlassButton: View {
    let icon: String
    var accent: Bool = false
    var size: CGFloat = 64
    var iconColor: Color? = nil
    let action: () -> Void

    @AppStorage("accentHex") private var accentHex = "FF9500"
    private var accentColor: Color { Color(hex: accentHex) }

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: accent ? size * 0.33 : size * 0.27, weight: .light))
                .foregroundColor(iconColor ?? (accent ? Color.black.opacity(0.82) : Theme.text.opacity(0.88)))
                .frame(width: size, height: size)
                .background(buttonBg)
        }.buttonStyle(.plain)
    }

    @ViewBuilder
    private var buttonBg: some View {
        if accent {
            Circle()
                .fill(accentColor)
                .overlay(Circle().fill(LinearGradient(
                    colors: [Color.white.opacity(0.42), Color.clear],
                    startPoint: .topLeading, endPoint: UnitPoint(x: 0.55, y: 0.65)
                )))
                .overlay(Circle().stroke(Color.white.opacity(0.28), lineWidth: 0.9))
        } else {
            Circle()
                .fill(.ultraThinMaterial)
                .overlay(Circle().fill(LinearGradient(
                    colors: [Color.white.opacity(0.18), Color.clear, Color.black.opacity(0.07)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )))
                .overlay(Circle().fill(LinearGradient(
                    colors: [Color.white.opacity(0.30), Color.clear],
                    startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.44)
                )))
                .overlay(Circle().stroke(LinearGradient(
                    colors: [Color.white.opacity(0.34), Color.white.opacity(0.04), Color.white.opacity(0.13)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ), lineWidth: 1.0))
        }
    }
}

// MARK: - GlassCapsuleButton

struct GlassCapsuleButton: View {
    let label: String
    let action: () -> Void

    @AppStorage("accentHex") private var accentHex = "FF9500"
    private var accent: Color { Color(hex: accentHex) }

    var body: some View {
        Button(action: action) {
            Text(label).font(.system(size: 12, weight: .bold)).tracking(3)
                .foregroundColor(Color.black.opacity(0.82)).frame(width: 130, height: 50)
                .background(
                    Capsule().fill(accent)
                        .overlay(Capsule().fill(LinearGradient(
                            colors: [Color.white.opacity(0.42), Color.clear],
                            startPoint: .topLeading, endPoint: UnitPoint(x: 0.55, y: 0.65)
                        )))
                        .overlay(Capsule().stroke(Color.white.opacity(0.28), lineWidth: 0.9))
                )
        }.buttonStyle(.plain)
    }
}

// MARK: - ModeSwitcher

struct ModeSwitcher: View {
    @Binding var page: Int
    var expanded: Bool = false
    var onNavigate: (Int) -> Void = { _ in }
    var onExpand: () -> Void = {}
    private let names = ["CLOCK", "TIMER", "WATCH", "INTERVAL", "POMODORO"]

    @AppStorage("accentHex") private var accentHex = "FF9500"
    private var accent: Color { Color(hex: accentHex) }

    var body: some View {
        HStack(spacing: expanded ? 4 : 0) {
            if page == -1 {
                Button { expanded ? onNavigate(-1) : onExpand() } label: {
                    Text("SETTINGS")
                        .font(.system(size: 9, weight: .bold)).tracking(1.8)
                        .foregroundColor(Theme.dim)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Theme.dim.opacity(0.14))
                                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(Theme.dim.opacity(0.32), lineWidth: 0.7))
                        )
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            } else {
                Button { onNavigate(-1) } label: {
                    Circle().fill(Color.white.opacity(0.22)).frame(width: 6, height: 6)
                }
                .buttonStyle(.plain)
                .opacity(expanded ? 1 : 0)
                .frame(width: expanded ? 36 : 0)
                .clipped()
                ForEach(0..<5, id: \.self) { i in
                    if i == page {
                        Button { expanded ? onNavigate(i) : onExpand() } label: {
                            Text(names[i])
                                .font(.system(size: 9, weight: .bold)).tracking(1.8)
                                .foregroundColor(accent)
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(accent.opacity(0.14))
                                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .stroke(accent.opacity(0.32), lineWidth: 0.7))
                                )
                        }
                        .buttonStyle(.plain)
                        .transition(.opacity)
                    } else {
                        Button { onNavigate(i) } label: {
                            Circle().fill(Color.white.opacity(0.22)).frame(width: 6, height: 6)
                        }
                        .buttonStyle(.plain)
                        .opacity(expanded ? 1 : 0)
                        .frame(width: expanded ? 36 : 0)
                        .clipped()
                    }
                }
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.05))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.14), Color.white.opacity(0.03)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ), lineWidth: 0.7
                ))
        )
        .animation(.easeInOut(duration: 0.18), value: page)
    }
}

// MARK: - CountdownTimer

@MainActor final class CountdownTimer: ObservableObject {
    @Published var remaining: TimeInterval = 0
    @Published var state: CState = .idle
    enum CState { case idle, running, paused, complete }

    private var endTime: Date?
    private var setDuration: TimeInterval = 0
    private var cancellable: AnyCancellable?

    var progress: Double {
        guard setDuration > 0 else { return 0 }
        return max(0, min(1, remaining / setDuration))
    }

    func setAndStart(seconds: Int) {
        let d = TimeInterval(seconds); guard d > 0 else { return }
        guard !(state == .running && setDuration == d) else { return }
        setDuration = d; remaining = d
        endTime = Date().addingTimeInterval(d)
        state = .running; startTicking(); HapticManager.shared.start()
    }
    func togglePause() {
        switch state {
        case .running:
            cancellable?.cancel(); endTime = nil; state = .paused; HapticManager.shared.stop()
        case .paused:
            endTime = Date().addingTimeInterval(remaining)
            state = .running; startTicking(); HapticManager.shared.start()
        default: break
        }
    }
    func reset() {
        cancellable?.cancel(); endTime = nil; remaining = 0; state = .idle
        HapticManager.shared.reset(); SoundManager.shared.stopLoop()
    }
    private func startTicking() {
        cancellable = Timer.publish(every: 1.0/30.0, tolerance: 0.004, on: .main, in: .common)
            .autoconnect().sink { [weak self] _ in self?.tick() }
    }
    private func tick() {
        guard let end = endTime else { return }
        let left = end.timeIntervalSinceNow
        if left <= 0 {
            remaining = 0; cancellable?.cancel(); state = .complete
            HapticManager.shared.complete(); SoundManager.shared.startLoop()
        } else {
            if remaining > 10 && left <= 10 { HapticManager.shared.warning(); SoundManager.shared.warning() }
            remaining = left
        }
    }
}

// MARK: - CountdownView

struct CountdownView: View {
    @ObservedObject var timer: CountdownTimer
    @State private var pendingSeconds: Double = 0
    @State private var touchCount: Int = 0

    @AppStorage("accentHex") private var accentHex = "FF9500"
    private var accent: Color { Color(hex: accentHex) }

    var body: some View {
        ZStack {
            switch timer.state {
            case .idle:     idleContent
            case .running:  runningContent
            case .paused:   pausedContent
            case .complete: completeContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.spring(response: 0.3, dampingFraction: 0.82), value: timer.state == .idle)
    }

    private var idleContent: some View {
        ZStack {
            if touchCount > 0 && pendingSeconds > 0 {
                RadialGradient(colors: [accent.opacity(0.06), .clear],
                               center: .center, startRadius: 0, endRadius: 240)
                    .ignoresSafeArea().allowsHitTesting(false)
            }
            VStack(spacing: 14) {
                Spacer()
                pendingDisplay
                    .scaleEffect(touchCount > 0 ? 1.05 : 1.0)
                    .animation(.spring(response: 0.18, dampingFraction: 0.7), value: touchCount > 0)
                    .gyroLeveled()
                Text(
                    touchCount >= 2    ? "TWO FINGER — HOURS" :
                    pendingSeconds == 0 ? "DRAG TO SET" : "RELEASE TO START"
                )
                .font(Theme.label).foregroundColor(Theme.dim).tracking(3)
                Spacer()
            }
        }
        .overlay(
            UnifiedDragView(
                onChanged: { delta, tc in
                    let absD = Swift.abs(delta); guard absD > 0.5 else { return }
                    let step: Double
                    if tc >= 2 {
                        if absD < 3 { step = 1800 } else if absD < 8 { step = 3600 } else { step = 7200 }
                    } else {
                        if absD < 2 { step = 1 } else if absD < 5 { step = 5 }
                        else if absD < 10 { step = 15 } else if absD < 20 { step = 60 } else { step = 300 }
                    }
                    let prev = pendingSeconds
                    pendingSeconds = Swift.max(0, Swift.min(pendingSeconds + (delta > 0 ? step : -step), 359_999))
                    if Int(pendingSeconds) != Int(prev) { HapticManager.shared.tick() }
                },
                onTouchCountChange: { tc in touchCount = tc },
                onEnd: {
                    touchCount = 0
                    if pendingSeconds > 0 { timer.setAndStart(seconds: Int(pendingSeconds)) }
                }
            )
            .ignoresSafeArea()
        )
        .contentShape(Rectangle())
        .ignoresSafeArea()
    }

    private var pendingDisplay: some View {
        let s = Int(pendingSeconds), h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        let txt = h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
        return Text(txt).font(Theme.display(86))
            .foregroundColor(pendingSeconds > 0 ? Theme.text : Theme.dim.opacity(0.14))
    }

    private var runningContent: some View {
        ZStack {
            ScreenBorderRing(
                progress: timer.progress, color: accent,
                pulsing: timer.remaining <= 10 && timer.remaining > 0
            )
            RadialGradient(colors: [accent.opacity(0.05), .clear],
                           center: .center, startRadius: 0, endRadius: 220)
                .allowsHitTesting(false)
            VStack(spacing: 20) {
                Spacer()
                activeDisplay.gyroLeveled()
                    .frame(minHeight: 110)
                Text("TAP TO PAUSE").font(Theme.label)
                    .foregroundColor(Theme.dim.opacity(0.3)).tracking(3)
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { timer.togglePause() }
    }

    private var pausedContent: some View {
        ZStack {
            ScreenBorderRing(progress: timer.progress, color: accent.opacity(0.28))
            VStack(spacing: 48) {
                Spacer()
                activeDisplay.opacity(0.5).gyroLeveled()
                    .frame(minHeight: 110)
                HStack(spacing: 22) {
                    GlassButton(icon: "xmark") { timer.reset(); pendingSeconds = 0 }
                    GlassButton(icon: "play.fill", accent: true, action: timer.togglePause)
                }
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var completeContent: some View {
        GlassCapsuleButton(label: "DISMISS") { timer.reset(); pendingSeconds = 0 }
    }

    private var activeDisplay: some View {
        let t = Int(timer.remaining.rounded(.up))
        let h = t / 3600, m = (t % 3600) / 60, s = t % 60
        let txt = h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
        return Text(txt).font(Theme.display(86)).foregroundColor(Theme.text)
    }
}

// MARK: - StopwatchTimer

@MainActor final class StopwatchTimer: ObservableObject {
    @Published var elapsed: TimeInterval = 0
    @Published var laps: [TimeInterval] = []
    @Published var isRunning = false

    private var startDate: Date?
    private var accumulated: TimeInterval = 0
    private var cancellable: AnyCancellable?

    var currentLapElapsed: TimeInterval { elapsed - laps.reduce(0, +) }

    func toggle() { isRunning ? pause() : start() }
    func lapOrReset() {
        if isRunning { laps.append(currentLapElapsed); HapticManager.shared.lap() } else { reset() }
    }
    func reset() {
        cancellable?.cancel(); elapsed = 0; accumulated = 0; startDate = nil; laps = []
        isRunning = false; HapticManager.shared.reset()
    }
    private func start() {
        startDate = Date(); isRunning = true
        cancellable = Timer.publish(every: 0.02, tolerance: 0.004, on: .main, in: .common)
            .autoconnect().sink { [weak self] _ in self?.tick() }
        HapticManager.shared.start()
    }
    private func pause() {
        cancellable?.cancel()
        if let s = startDate { accumulated += Date().timeIntervalSince(s) }
        startDate = nil; isRunning = false; HapticManager.shared.stop()
    }
    private func tick() {
        guard let s = startDate else { return }
        elapsed = accumulated + Date().timeIntervalSince(s)
    }
}

// MARK: - StopwatchView

struct StopwatchView: View {
    @StateObject private var timer = StopwatchTimer()
    @AppStorage("accentHex") private var accentHex = "FF9500"
    private var accent: Color { Color(hex: accentHex) }

    var body: some View {
        ZStack {
            VStack(spacing: 60) {
                mainTime.gyroLeveled()
                    .frame(minHeight: 110)
                HStack(spacing: 26) {
                    GlassButton(
                        icon: timer.isRunning ? "flag" : (timer.elapsed > 0 ? "arrow.counterclockwise" : "flag"),
                        action: timer.lapOrReset
                    )
                    .opacity(timer.elapsed == 0 ? 0.18 : 1)
                    .disabled(timer.elapsed == 0)
                    GlassButton(icon: timer.isRunning ? "pause.fill" : "play.fill", accent: true, action: timer.toggle)
                }
            }
            if !timer.laps.isEmpty {
                VStack { Spacer(); lapList.padding(.bottom, 28) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var mainTime: some View {
        let (h, m, s, cs) = split(timer.elapsed)
        return HStack(alignment: .lastTextBaseline, spacing: 0) {
            if h > 0 { Text("\(h):").font(Theme.display(72)).foregroundColor(Theme.text) }
            Text(String(format: h > 0 ? "%02d:" : "%d:", m)).font(Theme.display(72)).foregroundColor(Theme.text)
            Text(String(format: "%02d", s)).font(Theme.display(72)).foregroundColor(Theme.text)
            Text(String(format: ".%02d", cs)).font(Theme.display(34)).foregroundColor(Theme.dim)
        }
    }

    private var lapList: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                if timer.isRunning || timer.elapsed > 0 {
                    lapRow(number: timer.laps.count + 1, time: timer.currentLapElapsed, isCurrent: true)
                }
                ForEach(timer.laps.indices.reversed(), id: \.self) { i in
                    lapRow(number: i + 1, time: timer.laps[i], isCurrent: false)
                }
            }
        }
        .frame(maxHeight: 160)
        .mask(LinearGradient(colors: [Color.clear, Color.black],
                             startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.28)))
    }

    private func lapRow(number: Int, time: TimeInterval, isCurrent: Bool) -> some View {
        let (_, m, s, cs) = split(time)
        return HStack {
            Text("LAP \(number)").font(Theme.label)
                .foregroundColor(isCurrent ? accent : Theme.dim).tracking(1.5)
            Spacer()
            Text(String(format: "%d:%02d.%02d", m, s, cs))
                .font(.system(size: 15, weight: .thin, design: .rounded))
                .foregroundColor(isCurrent ? Theme.text : Theme.dim.opacity(0.6))
        }
        .padding(.horizontal, 36).padding(.vertical, 11)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.white.opacity(0.05)).frame(height: 0.5).padding(.horizontal, 36)
        }
    }

    private func split(_ t: TimeInterval) -> (Int, Int, Int, Int) {
        let n = Int(t * 100)
        return (n / 360000, (n / 6000) % 60, (n / 100) % 60, n % 100)
    }
}

// MARK: - IntervalTimer

@MainActor final class IntervalTimer: ObservableObject {
    @Published var workSecs: Double = 30
    @Published var restSecs: Double = 10
    @Published var totalRounds = 8
    @Published var remaining: TimeInterval = 0
    @Published var currentRound = 0
    @Published var phase: IPhase = .idle
    enum IPhase { case idle, work, rest, complete }

    private var endTime: Date?
    private var cancellable: AnyCancellable?

    var phaseDuration: TimeInterval { phase == .work ? workSecs : restSecs }
    var progress: Double {
        guard phaseDuration > 0 else { return 0 }
        return max(0, min(1, remaining / phaseDuration))
    }

    func start() {
        guard workSecs > 0 else { return }
        currentRound = 1; beginPhase(.work); HapticManager.shared.start()
    }
    func stop() {
        cancellable?.cancel(); phase = .idle; currentRound = 0; remaining = 0
        HapticManager.shared.reset(); SoundManager.shared.stopLoop()
    }
    private func beginPhase(_ next: IPhase) {
        phase = next
        let dur = next == .work ? workSecs : restSecs
        endTime = Date().addingTimeInterval(dur); remaining = dur
        cancellable = Timer.publish(every: 1.0/30.0, tolerance: 0.004, on: .main, in: .common)
            .autoconnect().sink { [weak self] _ in self?.tick() }
    }
    private func tick() {
        guard let end = endTime else { return }
        let left = end.timeIntervalSinceNow
        if left <= 0 { cancellable?.cancel(); advance() }
        else {
            if remaining > 10 && left <= 10 { HapticManager.shared.warning(); SoundManager.shared.warning() }
            remaining = left
        }
    }
    private func advance() {
        switch phase {
        case .work:
            if restSecs > 0 {
                beginPhase(.rest); HapticManager.shared.lap(); SoundManager.shared.phaseTransition()
            } else { nextRound() }
        case .rest: nextRound()
        default: break
        }
    }
    private func nextRound() {
        if currentRound >= totalRounds {
            phase = .complete; remaining = 0
            HapticManager.shared.complete(); SoundManager.shared.startLoop()
        } else {
            currentRound += 1; beginPhase(.work)
            HapticManager.shared.start(); SoundManager.shared.phaseTransition()
        }
    }
}

// MARK: - DragSetCard

struct DragSetCard: View {
    let label: String
    let color: Color
    @Binding var totalSeconds: Double
    let maxSeconds: Double

    @State private var prevTranslation: CGFloat = 0
    @State private var isDragging = false

    private var formattedTime: String {
        let s = Int(totalSeconds), m = s / 60, sec = s % 60
        return String(format: "%d:%02d", m, sec)
    }

    var body: some View {
        VStack(spacing: 10) {
            Text(label).font(Theme.label)
                .foregroundColor(isDragging ? color : color.opacity(0.55)).tracking(2.5)
            Text(formattedTime).font(Theme.display(46))
                .foregroundColor(isDragging ? color : Theme.text)
            Image(systemName: "arrow.up.arrow.down")
                .font(.system(size: 10, weight: .light)).foregroundColor(Theme.dim.opacity(0.4))
        }
        .frame(maxWidth: .infinity).padding(.vertical, 30)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(isDragging ? color.opacity(0.08) : Color.white.opacity(0.05))
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(
                    LinearGradient(
                        colors: isDragging ? [color.opacity(0.45), color.opacity(0.12)]
                                           : [Color.white.opacity(0.13), Color.white.opacity(0.03)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ), lineWidth: 0.8
                ))
        )
        .animation(.easeOut(duration: 0.13), value: isDragging)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 3)
                .onChanged { drag in
                    if !isDragging { isDragging = true; prevTranslation = drag.translation.height }
                    let delta = prevTranslation - drag.translation.height
                    prevTranslation = drag.translation.height
                    let abs = Swift.abs(delta); guard abs > 0.5 else { return }
                    let step: Double
                    switch abs {
                    case ..<2:  step = 1
                    case ..<5:  step = 5
                    case ..<10: step = 15
                    case ..<20: step = 30
                    default:    step = 60
                    }
                    let prev = totalSeconds
                    totalSeconds = Swift.max(1, Swift.min(maxSeconds, totalSeconds + (delta > 0 ? step : -step)))
                    if Int(totalSeconds) != Int(prev) { HapticManager.shared.tick() }
                }
                .onEnded { _ in isDragging = false; prevTranslation = 0 }
        )
    }
}

// MARK: - IntervalView

struct IntervalView: View {
    @StateObject private var timer = IntervalTimer()
    @AppStorage("accentHex") private var accentHex = "FF9500"
    private var accent: Color { Color(hex: accentHex) }
    private var restColor: Color { Color(hex: "5AC8FA") }

    var body: some View {
        ZStack {
            if timer.phase != .idle {
                ScreenBorderRing(
                    progress: timer.progress, color: phaseColor,
                    pulsing: timer.remaining <= 10 && timer.remaining > 0 && timer.phase != .complete
                )
            }
            if timer.phase == .idle { setupContent.transition(.opacity) }
            else { activeContent.transition(.opacity) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeInOut(duration: 0.28), value: timer.phase == .idle)
    }

    private var setupContent: some View {
        VStack(spacing: 22) {
            Spacer()
            HStack(spacing: 12) {
                DragSetCard(label: "WORK", color: accent, totalSeconds: $timer.workSecs, maxSeconds: 3599)
                DragSetCard(label: "REST", color: restColor, totalSeconds: $timer.restSecs, maxSeconds: 3599)
            }.padding(.horizontal, 24)

            HStack(spacing: 28) {
                GlassButton(icon: "minus", size: 40, iconColor: Theme.dim) {
                    if timer.totalRounds > 1 { timer.totalRounds -= 1; HapticManager.shared.tick() }
                }
                VStack(spacing: 2) {
                    Text("\(timer.totalRounds)").font(Theme.display(40)).foregroundColor(Theme.text)
                    Text("ROUNDS").font(Theme.label).foregroundColor(Theme.dim).tracking(2)
                }.frame(minWidth: 72)
                GlassButton(icon: "plus", size: 40, iconColor: Theme.dim) {
                    if timer.totalRounds < 99 { timer.totalRounds += 1; HapticManager.shared.tick() }
                }
            }.padding(.vertical, 4)

            GlassCapsuleButton(label: "BEGIN", action: timer.start)
            Spacer()
        }
    }

    private var activeContent: some View {
        VStack(spacing: 32) {
            Spacer()
            VStack(spacing: 12) {
                Text(phaseLabel).font(Theme.label).foregroundColor(phaseColor).tracking(3)
                let t = Int(timer.remaining.rounded(.up))
                Text(String(format: "%d:%02d", t / 60, t % 60))
                    .font(Theme.display(86)).foregroundColor(Theme.text)
                    .gyroLeveled()
                if timer.phase != .complete {
                    Text("\(timer.currentRound) of \(timer.totalRounds)")
                        .font(Theme.label).foregroundColor(Theme.dim).tracking(1)
                }
            }
            if timer.phase == .complete {
                GlassButton(icon: "arrow.counterclockwise", action: timer.stop)
            } else {
                GlassButton(icon: "xmark", action: timer.stop)
            }
            Spacer()
        }
    }

    private var phaseColor: Color { timer.phase == .rest ? restColor : accent }
    private var phaseLabel: String {
        switch timer.phase {
        case .work: return "WORK"; case .rest: return "REST"
        case .complete: return "DONE"; default: return ""
        }
    }
}

// MARK: - PomodoroTimer

@MainActor final class PomodoroTimer: ObservableObject {
    @Published var focusMinutes = 25
    @Published var shortBreakMinutes = 5
    @Published var longBreakMinutes = 15
    @Published var sessionsPerLong = 4
    @Published var remaining: TimeInterval = 0
    @Published var completedSessions = 0
    @Published var phase: PPhase = .idle
    @Published var isPaused = false
    enum PPhase { case idle, focus, shortBreak, longBreak, complete }

    private var endTime: Date?
    private var cancellable: AnyCancellable?

    var isActive: Bool { phase != .idle && phase != .complete }
    var phaseDuration: TimeInterval {
        switch phase {
        case .focus:      return TimeInterval(focusMinutes * 60)
        case .shortBreak: return TimeInterval(shortBreakMinutes * 60)
        case .longBreak:  return TimeInterval(longBreakMinutes * 60)
        case .idle, .complete: return 0
        }
    }
    var progress: Double {
        guard phaseDuration > 0 else { return 0 }
        return max(0, min(1, remaining / phaseDuration))
    }
    var sessionIndexInCycle: Int { completedSessions % sessionsPerLong }

    func start() { completedSessions = 0; isPaused = false; beginPhase(.focus); HapticManager.shared.start() }
    func togglePause() {
        if isPaused {
            isPaused = false; endTime = Date().addingTimeInterval(remaining)
            startTicking(); HapticManager.shared.start()
        } else {
            isPaused = true; cancellable?.cancel(); endTime = nil; HapticManager.shared.stop()
        }
    }
    func skip() {
        guard isActive else { return }
        cancellable?.cancel(); advanceFrom(phase); HapticManager.shared.tap()
    }
    func stop() {
        cancellable?.cancel(); phase = .idle; remaining = 0; completedSessions = 0
        isPaused = false; HapticManager.shared.reset(); SoundManager.shared.stopLoop()
    }
    private func beginPhase(_ next: PPhase) {
        phase = next; isPaused = false
        let dur: TimeInterval
        switch next {
        case .focus:      dur = TimeInterval(focusMinutes * 60)
        case .shortBreak: dur = TimeInterval(shortBreakMinutes * 60)
        case .longBreak:  dur = TimeInterval(longBreakMinutes * 60)
        case .idle, .complete: return
        }
        endTime = Date().addingTimeInterval(dur); remaining = dur; startTicking()
    }
    private func startTicking() {
        cancellable = Timer.publish(every: 1.0/30.0, tolerance: 0.004, on: .main, in: .common)
            .autoconnect().sink { [weak self] _ in self?.tick() }
    }
    private func tick() {
        guard let end = endTime else { return }
        let left = end.timeIntervalSinceNow
        if left <= 0 { cancellable?.cancel(); advanceFrom(phase) }
        else {
            if remaining > 10 && left <= 10 { HapticManager.shared.warning(); SoundManager.shared.warning() }
            remaining = left
        }
    }
    private func advanceFrom(_ p: PPhase) {
        switch p {
        case .focus:
            completedSessions += 1
            HapticManager.shared.complete(); SoundManager.shared.complete()
            beginPhase(completedSessions % sessionsPerLong == 0 ? .longBreak : .shortBreak)
        case .shortBreak:
            beginPhase(.focus); HapticManager.shared.start(); SoundManager.shared.phaseTransition()
        case .longBreak:
            phase = .complete; remaining = 0; isPaused = false; endTime = nil
            HapticManager.shared.complete(); SoundManager.shared.startLoop()
        case .idle, .complete: break
        }
    }
}

// MARK: - DragRow

struct DragRow: View {
    let label: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let unit: String

    @State private var prevTranslation: CGFloat = 0
    @State private var isDragging = false

    @AppStorage("accentHex") private var accentHex = "FF9500"
    private var accent: Color { Color(hex: accentHex) }

    var body: some View {
        HStack {
            Text(label).font(Theme.label)
                .foregroundColor(isDragging ? accent : Theme.dim).tracking(1.5)
            Spacer()
            HStack(spacing: 6) {
                Text(unit.isEmpty ? "\(value)" : "\(value) \(unit)")
                    .font(.system(size: 15, weight: .thin, design: .rounded))
                    .foregroundColor(isDragging ? accent : Theme.text)
                    .frame(minWidth: 52, alignment: .trailing)
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 9, weight: .light))
                    .foregroundColor(Theme.dim.opacity(isDragging ? 0.8 : 0.35))
            }
        }
        .padding(.vertical, 14).padding(.horizontal, 18)
        .animation(.easeOut(duration: 0.1), value: isDragging)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 5)
                .onChanged { drag in
                    if !isDragging { isDragging = true; prevTranslation = drag.translation.height }
                    let delta = prevTranslation - drag.translation.height
                    prevTranslation = drag.translation.height
                    guard Swift.abs(delta) > 0.8 else { return }
                    let step = Swift.abs(delta) > 12 ? 5 : 1
                    let next = delta > 0
                        ? Swift.min(range.upperBound, value + step)
                        : Swift.max(range.lowerBound, value - step)
                    if next != value { value = next; HapticManager.shared.tick() }
                }
                .onEnded { _ in isDragging = false; prevTranslation = 0 }
        )
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.white.opacity(0.05)).frame(height: 0.5).padding(.horizontal, 18)
        }
    }
}

// MARK: - PomodoroView

struct PomodoroView: View {
    @StateObject private var timer = PomodoroTimer()
    @AppStorage("accentHex") private var accentHex = "FF9500"
    private var accent: Color { Color(hex: accentHex) }

    var body: some View {
        ZStack {
            if timer.phase == .complete    { completeContent.transition(.opacity) }
            else if !timer.isActive        { setupContent.transition(.opacity) }
            else if timer.isPaused         { pausedContent.transition(.opacity) }
            else                           { runningContent.transition(.opacity) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeInOut(duration: 0.25), value: timer.phase == .idle)
        .animation(.easeInOut(duration: 0.25), value: timer.phase == .complete)
        .animation(.easeInOut(duration: 0.2),  value: timer.isPaused)
    }

    private var setupContent: some View {
        VStack(spacing: 0) {
            Spacer()
            focusDragPreview.padding(.bottom, 32)
            VStack(spacing: 0) {
                DragRow(label: "FOCUS",       value: $timer.focusMinutes,      range: 1...99, unit: "min")
                DragRow(label: "SHORT BREAK", value: $timer.shortBreakMinutes, range: 1...30, unit: "min")
                DragRow(label: "LONG BREAK",  value: $timer.longBreakMinutes,  range: 1...60, unit: "min")
                DragRow(label: "SESSIONS",    value: $timer.sessionsPerLong,   range: 1...12, unit: "")
            }
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.white.opacity(0.045))
                    .overlay(RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.white.opacity(0.08), lineWidth: 0.6))
            )
            .padding(.horizontal, 24)
            Spacer().frame(height: 28)
            GlassCapsuleButton(label: "FOCUS", action: timer.start)
            Spacer()
        }
    }

    @State private var focusPrevTranslation: CGFloat = 0
    @State private var focusIsDragging = false

    private var focusDragPreview: some View {
        VStack(spacing: 8) {
            Text(String(format: "%d:00", timer.focusMinutes))
                .font(Theme.display(72))
                .foregroundColor(focusIsDragging ? accent : Theme.text)
            Text("FOCUS — DRAG TO SET")
                .font(Theme.label).foregroundColor(Theme.dim).tracking(2.5)
        }
        .scaleEffect(focusIsDragging ? 1.04 : 1.0)
        .animation(.spring(response: 0.18, dampingFraction: 0.7), value: focusIsDragging)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 5)
                .onChanged { drag in
                    if !focusIsDragging { focusIsDragging = true; focusPrevTranslation = drag.translation.height }
                    let delta = focusPrevTranslation - drag.translation.height
                    focusPrevTranslation = drag.translation.height
                    guard Swift.abs(delta) > 0.8 else { return }
                    let step = Swift.abs(delta) > 12 ? 5 : 1
                    let next = delta > 0
                        ? Swift.min(99, timer.focusMinutes + step)
                        : Swift.max(1,  timer.focusMinutes - step)
                    if next != timer.focusMinutes { timer.focusMinutes = next; HapticManager.shared.tick() }
                }
                .onEnded { _ in focusIsDragging = false; focusPrevTranslation = 0 }
        )
    }

    private var runningContent: some View {
        ZStack {
            ScreenBorderRing(progress: timer.progress, color: phaseColor,
                             pulsing: timer.remaining <= 10 && timer.remaining > 0)
            RadialGradient(colors: [phaseColor.opacity(0.05), .clear],
                           center: .center, startRadius: 0, endRadius: 220)
                .allowsHitTesting(false)
            VStack(spacing: 0) {
                Spacer()
                HStack(spacing: 6) {
                    ForEach(0..<timer.sessionsPerLong, id: \.self) { i in
                        Circle().fill(i < timer.sessionIndexInCycle ? phaseColor : Theme.overlay)
                            .frame(width: 5, height: 5)
                    }
                }.padding(.bottom, 28)
                VStack(spacing: 10) {
                    Text(phaseLabel).font(Theme.label).foregroundColor(phaseColor).tracking(3)
                    let t = Int(timer.remaining)
                    Text(String(format: "%d:%02d", t / 60, t % 60))
                        .font(Theme.display(86)).foregroundColor(Theme.text)
                        .gyroLeveled()
                    Text("TAP TO PAUSE").font(Theme.label)
                        .foregroundColor(Theme.dim.opacity(0.28)).tracking(3).padding(.top, 6)
                }
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { timer.togglePause() }
    }

    private var pausedContent: some View {
        ZStack {
            ScreenBorderRing(progress: timer.progress, color: phaseColor.opacity(0.28))
            VStack(spacing: 40) {
                Spacer()
                VStack(spacing: 10) {
                    Text(phaseLabel).font(Theme.label).foregroundColor(phaseColor.opacity(0.5)).tracking(3)
                    let t = Int(timer.remaining)
                    Text(String(format: "%d:%02d", t / 60, t % 60))
                        .font(Theme.display(86)).foregroundColor(Theme.text.opacity(0.5))
                        .gyroLeveled()
                }
                HStack(spacing: 20) {
                    GlassButton(icon: "xmark", action: timer.stop)
                    GlassButton(icon: "play.fill", accent: true, action: timer.togglePause)
                    GlassButton(icon: "forward.end.fill", action: timer.skip)
                }
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var completeContent: some View {
        VStack(spacing: 28) {
            Text("DONE").font(Theme.display(86)).foregroundColor(accent).gyroLeveled()
            Text("\(timer.completedSessions) SESSIONS")
                .font(Theme.label).foregroundColor(Theme.dim).tracking(3)
            GlassButton(icon: "arrow.counterclockwise", action: timer.stop)
        }
    }

    private var phaseColor: Color {
        switch timer.phase {
        case .focus:           return accent
        case .shortBreak:      return Color(hex: "30D158")
        case .longBreak:       return Color(hex: "5AC8FA")
        case .idle, .complete: return Theme.dim
        }
    }
    private var phaseLabel: String {
        switch timer.phase {
        case .focus: return "FOCUS"; case .shortBreak: return "SHORT BREAK"
        case .longBreak: return "LONG BREAK"; default: return ""
        }
    }
}

// MARK: - Alarm

struct Alarm: Identifiable, Codable, Equatable {
    var id = UUID()
    var hour: Int
    var minute: Int
    var enabled: Bool
}

// MARK: - AlarmRow

struct AlarmRow: View {
    @Binding var alarm: Alarm
    var onSave: () -> Void
    var onDelete: () -> Void

    @State private var hourDragging = false
    @State private var hourPrev: CGFloat = 0
    @State private var minDragging = false
    @State private var minPrev: CGFloat = 0
    @State private var swipeOffset: CGFloat = 0
    @State private var isPressing = false

    @AppStorage("accentHex") private var accentHex = "FF9500"
    private var accent: Color { Color(hex: accentHex) }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "alarm")
                .font(.system(size: 12, weight: .light))
                .foregroundColor(alarm.enabled ? accent : Color.white.opacity(0.28))
            HStack(spacing: 0) {
                Text(String(format: "%02d", alarm.hour))
                    .frame(minWidth: 26)
                    .contentShape(Rectangle())
                    .gesture(hourDrag)
                Text(":").padding(.horizontal, 1)
                Text(String(format: "%02d", alarm.minute))
                    .frame(minWidth: 26)
                    .contentShape(Rectangle())
                    .gesture(minDrag)
            }
            .font(.system(size: 15, weight: .thin, design: .rounded))
            .foregroundColor(alarm.enabled ? Theme.text : Color.white.opacity(0.45))
            .monospacedDigit()
            Toggle(isOn: $alarm.enabled) { EmptyView() }
                .labelsHidden()
                .tint(accent)
                .scaleEffect(0.8)
                .onChange(of: alarm.enabled) { _, _ in HapticManager.shared.tap(); onSave() }
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(Capsule().fill(LinearGradient(
                    colors: [Color.white.opacity(0.18), Color.clear],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )))
                .overlay(Capsule().stroke(LinearGradient(
                    colors: [Color.white.opacity(0.30), Color.white.opacity(0.05)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ), lineWidth: 0.8))
        )
        .shadow(color: isPressing ? Color.red.opacity(0.72) : .clear, radius: isPressing ? 14 : 0)
        .offset(y: swipeOffset)
        .onLongPressGesture(minimumDuration: 0.5, pressing: { pressing in
            withAnimation(pressing ? .easeIn(duration: 0.4) : .easeOut(duration: 0.15)) {
                isPressing = pressing
            }
        }) {
            withAnimation(.easeOut(duration: 0.18)) { swipeOffset = -400 }
            HapticManager.shared.tap()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { onDelete() }
        }
    }

    private var hourDrag: some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { drag in
                if !hourDragging { hourDragging = true; hourPrev = drag.translation.height }
                let delta = hourPrev - drag.translation.height; hourPrev = drag.translation.height
                guard Swift.abs(delta) > 1 else { return }
                alarm.hour = (alarm.hour + (delta > 0 ? 1 : -1) + 24) % 24
                HapticManager.shared.tick()
            }
            .onEnded { _ in hourDragging = false; hourPrev = 0; onSave() }
    }

    private var minDrag: some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { drag in
                if !minDragging { minDragging = true; minPrev = drag.translation.height }
                let delta = minPrev - drag.translation.height; minPrev = drag.translation.height
                guard Swift.abs(delta) > 1 else { return }
                alarm.minute = (alarm.minute + (delta > 0 ? 1 : -1) + 60) % 60
                HapticManager.shared.tick()
            }
            .onEnded { _ in minDragging = false; minPrev = 0; onSave() }
    }
}

// MARK: - ClockView

struct ClockView: View {
    @State private var now = Date()
    @State private var alarms: [Alarm] = []
    @State private var firedAlarmID: UUID? = nil

    @AppStorage("accentHex") private var accentHex = "FF9500"
    private var accent: Color { Color(hex: accentHex) }

    private var timeString: String {
        let c = Calendar.current.dateComponents([.hour, .minute, .second], from: now)
        return String(format: "%02d:%02d:%02d", c.hour ?? 0, c.minute ?? 0, c.second ?? 0)
    }

    var body: some View {
        ZStack {
            if let id = firedAlarmID { firedContent(id: id) } else { mainContent }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { loadAlarms() }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { date in
            now = date
            guard firedAlarmID == nil else { return }
            let c = Calendar.current.dateComponents([.hour, .minute, .second], from: date)
            guard (c.second ?? 1) == 0 else { return }
            for alarm in alarms where alarm.enabled {
                if c.hour == alarm.hour && c.minute == alarm.minute {
                    firedAlarmID = alarm.id
                    HapticManager.shared.complete()
                    SoundManager.shared.startLoop()
                    break
                }
            }
        }
    }

    private var mainContent: some View {
        ZStack(alignment: .bottom) {
            Text(timeString)
                .font(Theme.display(86))
                .foregroundColor(Theme.text)
                .monospacedDigit()
                .gyroLeveled()
                .frame(minHeight: 110)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            alarmArea
                .padding(.bottom, 80)
        }
    }

    private var alarmArea: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(alarms) { alarm in
                    AlarmRow(
                        alarm: Binding(
                            get: { alarms.first { $0.id == alarm.id } ?? alarm },
                            set: { new in
                                if let i = alarms.firstIndex(where: { $0.id == alarm.id }) {
                                    alarms[i] = new
                                }
                            }
                        ),
                        onSave: saveAlarms,
                        onDelete: {
                            var t = Transaction()
                            t.disablesAnimations = true
                            withTransaction(t) {
                                alarms.removeAll { $0.id == alarm.id }
                                saveAlarms()
                            }
                        }
                    )
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.01, anchor: .leading).combined(with: .opacity),
                        removal: .identity
                    ))
                }
                if alarms.count < 5 {
                    Button {
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.55)) {
                            alarms.append(Alarm(hour: 8, minute: 0, enabled: false))
                            saveAlarms()
                        }
                        HapticManager.shared.tap()
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(Theme.dim)
                            .frame(width: 30, height: 30)
                            .background(
                                Circle()
                                    .fill(.ultraThinMaterial)
                                    .overlay(Circle().stroke(Color.white.opacity(0.14), lineWidth: 0.7))
                            )
                    }
                    .buttonStyle(.plain)
                    .transition(.scale(scale: 0.01).combined(with: .opacity))
                }
            }
            .padding(.horizontal, 24)
            .animation(.spring(response: 0.45, dampingFraction: 0.55), value: alarms.count)
        }
    }

    private func firedContent(id: UUID) -> some View {
        VStack(spacing: 32) {
            Image(systemName: "alarm")
                .font(.system(size: 52, weight: .thin))
                .foregroundColor(accent)
            GlassCapsuleButton(label: "DISMISS") {
                firedAlarmID = nil
                if let i = alarms.firstIndex(where: { $0.id == id }) {
                    alarms[i].enabled = false
                    saveAlarms()
                }
                SoundManager.shared.stopLoop()
            }
        }
    }

    private func loadAlarms() {
        guard let data = UserDefaults.standard.data(forKey: "alarmsData"),
              let decoded = try? JSONDecoder().decode([Alarm].self, from: data),
              !decoded.isEmpty else {
            alarms = [Alarm(hour: 7, minute: 0, enabled: false)]
            return
        }
        alarms = decoded
    }

    private func saveAlarms() {
        if let data = try? JSONEncoder().encode(alarms) {
            UserDefaults.standard.set(data, forKey: "alarmsData")
        }
    }
}

// MARK: - SettingsView

struct SettingsView: View {
    @AppStorage("bgMode")           private var bgMode         = "dark"
    @AppStorage("accentHex")        private var accentHex      = "FF9500"
    @AppStorage("warningSound")     private var warningSound   = "ping"
    @AppStorage("pitchSemitones")   private var pitchSemitones = 0
    @AppStorage("melodyPattern")    private var melodyPattern  = "ascend"
    @AppStorage("soundEnabled")     private var soundEnabled   = true
    @AppStorage("hapticsEnabled")   private var hapticsEnabled = true
    @AppStorage("gyroLevel")        private var gyroLevel      = false

    @State private var soundExpanded = false

    private var accent: Color { Color(hex: accentHex) }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                Spacer().frame(height: 80)

                settingCard {
                    VStack(spacing: 0) {
                        HStack(spacing: 12) {
                            Image(systemName: "speaker.wave.2")
                                .font(.system(size: 14, weight: .light))
                                .foregroundColor(soundEnabled ? accent : Theme.dim)
                                .frame(width: 24)
                            Text("SOUND")
                                .font(Theme.label).tracking(1.5)
                                .foregroundColor(soundEnabled ? Theme.text : Theme.dim)
                            Spacer()
                            Button {
                                withAnimation(.spring(response: 0.34, dampingFraction: 0.78)) { soundExpanded.toggle() }
                                HapticManager.shared.tap()
                            } label: {
                                HStack(spacing: 4) {
                                    Text("CUSTOMISE")
                                        .font(.system(size: 9, weight: .semibold)).tracking(1.6)
                                        .foregroundColor(soundExpanded ? accent : Theme.dim.opacity(0.45))
                                    Image(systemName: soundExpanded ? "chevron.up" : "chevron.down")
                                        .font(.system(size: 8, weight: .bold))
                                        .foregroundColor(soundExpanded ? accent : Theme.dim.opacity(0.38))
                                }
                            }
                            .buttonStyle(.plain)
                            .padding(.trailing, 8)
                            Toggle(isOn: $soundEnabled) { EmptyView() }
                                .labelsHidden()
                                .tint(accent)
                                .onChange(of: soundEnabled) { _, _ in HapticManager.shared.tap() }
                        }
                        .padding(.vertical, 12)
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(Color.white.opacity(0.05)).frame(height: 0.5)
                        }
                        toggleRow(label: "HAPTICS", icon: "hand.tap",        isOn: $hapticsEnabled, divider: true)
                        Toggle(isOn: $gyroLevel) {
                            HStack(spacing: 12) {
                                Image(systemName: "gyroscope")
                                    .font(.system(size: 14, weight: .light))
                                    .foregroundColor(gyroLevel ? accent : Theme.dim)
                                    .frame(width: 24)
                                Text("GYRO LEVEL")
                                    .font(Theme.label)
                                    .foregroundColor(gyroLevel ? Theme.text : Theme.dim)
                                    .tracking(1.5)
                            }
                        }
                        .tint(accent)
                        .padding(.vertical, 12)
                        .onChange(of: gyroLevel) { _, enabled in
                            HapticManager.shared.tap()
                            if enabled { GyroManager.shared.start() } else { GyroManager.shared.stop() }
                        }
                    }
                }

                if soundExpanded {
                    settingCard {
                        VStack(alignment: .leading, spacing: 20) {
                            VStack(alignment: .leading, spacing: 10) {
                                rowLabel("10S WARNING")
                                HStack(spacing: 8) {
                                    ForEach(AppSettings.warningSounds, id: \.id) { s in
                                        soundChip(s.name, isSelected: warningSound == s.id) {
                                            warningSound = s.id
                                            SoundManager.shared.previewWarning(type: s.id)
                                            HapticManager.shared.tap()
                                        }
                                    }
                                }
                            }

                            VStack(alignment: .leading, spacing: 10) {
                                rowLabel("MELODY")
                                HStack(spacing: 8) {
                                    ForEach(AppSettings.melodyPatterns, id: \.id) { p in
                                        soundChip(p.name, isSelected: melodyPattern == p.id) {
                                            melodyPattern = p.id
                                            SoundManager.shared.previewPattern(semitones: pitchSemitones, pattern: p.id)
                                            HapticManager.shared.tap()
                                        }
                                    }
                                }
                            }

                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    rowLabel("PITCH")
                                    Spacer()
                                    Text(pitchSemitones == 0 ? "default"
                                         : (pitchSemitones > 0 ? "+\(pitchSemitones)" : "\(pitchSemitones)") + " st")
                                        .font(.system(size: 10, weight: .light, design: .rounded))
                                        .foregroundColor(pitchSemitones == 0 ? Theme.dim.opacity(0.4) : accent)
                                        .monospacedDigit()
                                }
                                GeometryReader { geo in
                                    let w = geo.size.width
                                    let pct = CGFloat(pitchSemitones + 12) / 24.0
                                    ZStack(alignment: .leading) {
                                        Capsule()
                                            .fill(Color.white.opacity(0.08))
                                            .frame(height: 3)
                                            .frame(maxWidth: .infinity)
                                        Rectangle()
                                            .fill(Color.white.opacity(0.20))
                                            .frame(width: 1.5, height: 9)
                                            .frame(maxWidth: .infinity, alignment: .center)
                                        Circle()
                                            .fill(accent)
                                            .frame(width: 22, height: 22)
                                            .shadow(color: accent.opacity(0.45), radius: 6)
                                            .padding(.leading, pct * (w - 22))
                                    }
                                    .frame(height: 22)
                                    .contentShape(Rectangle())
                                    .gesture(
                                        DragGesture(minimumDistance: 0)
                                            .onChanged { drag in
                                                let x = max(0, min(w, drag.location.x))
                                                let newSt = max(-12, min(12, Int(((x / w) * 24 - 12).rounded())))
                                                if newSt != pitchSemitones {
                                                    pitchSemitones = newSt
                                                    HapticManager.shared.tick()
                                                    SoundManager.shared.previewTone(semitones: newSt)
                                                }
                                            }
                                            .onEnded { _ in
                                                SoundManager.shared.previewPattern(semitones: pitchSemitones, pattern: melodyPattern)
                                            }
                                    )
                                }
                                .frame(height: 22)
                                HStack {
                                    Text("−12").font(.system(size: 8, weight: .light)).foregroundColor(Theme.dim.opacity(0.35))
                                    Spacer()
                                    Text("+12").font(.system(size: 8, weight: .light)).foregroundColor(Theme.dim.opacity(0.35))
                                }
                                .padding(.top, 2)
                            }
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                sectionLabel("APPEARANCE")

                settingCard {
                    VStack(alignment: .leading, spacing: 16) {
                        rowLabel("TIMER COLOR")
                        HStack(spacing: 14) {
                            ForEach(AppSettings.accentPresets, id: \.hex) { accentDot($0) }
                        }
                    }
                }

                settingCard {
                    VStack(alignment: .leading, spacing: 16) {
                        rowLabel("BACKGROUND")
                        HStack(spacing: 10) {
                            ForEach(AppSettings.bgPresets, id: \.mode) { bgSwatch($0) }
                        }
                    }
                }

                Spacer().frame(height: 40)
            }
            .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: – Helpers

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold)).tracking(2.5)
            .foregroundColor(Theme.dim.opacity(0.50))
            .padding(.horizontal, 2)
    }

    private func rowLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold)).tracking(2)
            .foregroundColor(Theme.dim)
    }

    @ViewBuilder
    private func settingCard<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 18).padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(0.04))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.07), lineWidth: 0.6))
            )
    }

    private func toggleRow(label: String, icon: String, isOn: Binding<Bool>, divider: Bool = false) -> some View {
        Toggle(isOn: isOn) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .light))
                    .foregroundColor(isOn.wrappedValue ? accent : Theme.dim)
                    .frame(width: 24)
                Text(label)
                    .font(Theme.label)
                    .foregroundColor(isOn.wrappedValue ? Theme.text : Theme.dim)
                    .tracking(1.5)
            }
        }
        .tint(accent)
        .padding(.vertical, 12)
        .onChange(of: isOn.wrappedValue) { _, _ in HapticManager.shared.tap() }
        .overlay(alignment: .bottom) {
            if divider { Rectangle().fill(Color.white.opacity(0.05)).frame(height: 0.5) }
        }
    }

    private func soundChip(_ label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 9, weight: .bold)).tracking(1.4)
                .foregroundColor(isSelected ? Color.black.opacity(0.78) : Theme.dim)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isSelected ? accent : Color.white.opacity(0.06))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(isSelected ? Color.clear : Color.white.opacity(0.08), lineWidth: 0.7))
                )
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isSelected)
    }

    private func bgSwatch(_ preset: (name: String, mode: String)) -> some View {
        let isSelected = bgMode == preset.mode
        return Button {
            bgMode = preset.mode; HapticManager.shared.tap()
        } label: {
            VStack(spacing: 5) {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(AppSettings.bg(for: preset.mode))
                    .frame(width: 42, height: 28)
                    .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(isSelected ? accent : Color.white.opacity(0.11),
                                lineWidth: isSelected ? 1.5 : 0.6))
                Text(preset.name)
                    .font(.system(size: 8, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? accent : Theme.dim)
                    .tracking(0.4)
            }
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isSelected)
    }

    private func accentDot(_ preset: (name: String, hex: String)) -> some View {
        let c = Color(hex: preset.hex)
        let isSelected = accentHex == preset.hex
        return Button {
            accentHex = preset.hex; HapticManager.shared.tap()
        } label: {
            ZStack {
                Circle().fill(c).frame(width: 30, height: 30)
                if isSelected {
                    Circle().stroke(Color.white.opacity(0.75), lineWidth: 2)
                        .frame(width: 36, height: 36)
                }
            }
            .shadow(color: c.opacity(isSelected ? 0.55 : 0), radius: 7)
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.22, dampingFraction: 0.62), value: isSelected)
    }
}

// MARK: - ContentView

struct ContentView: View {
    @StateObject private var countdownTimer = CountdownTimer()
    @State private var page = 0
    @State private var pillExpanded = false
    @State private var pillCollapseID = UUID()

    @AppStorage("bgMode") private var bgMode = "dark"
    private var bg: Color { AppSettings.bg(for: bgMode) }

    private func expandPill(for duration: Double = 0.65) {
        let id = UUID()
        pillCollapseID = id
        withAnimation(.spring(response: 0.38, dampingFraction: 0.62)) { pillExpanded = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            guard pillCollapseID == id else { return }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.78)) { pillExpanded = false }
        }
    }

    private func navigate(to newPage: Int) {
        guard newPage != page else { return }
        HapticManager.shared.tap()
        withAnimation(.easeInOut(duration: 0.5)) { page = newPage }
        expandPill()
    }

    var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 20)
            .onEnded { drag in
                let h = drag.translation.width
                let v = drag.translation.height
                guard Swift.abs(h) > Swift.abs(v) * 1.3 else { return }
                if h < -60     { navigate(to: Swift.min(4, page + 1)) }
                else if h > 60 { navigate(to: Swift.max(-1, page - 1)) }
            }
    }

    var body: some View {
        ZStack(alignment: .top) {
            bg.ignoresSafeArea()

            ZStack {
                SettingsView()
                    .opacity(page == -1 ? 1 : 0)
                    .scaleEffect(page == -1 ? 1 : 0.95)
                    .allowsHitTesting(page == -1)
                ClockView()
                    .opacity(page == 0 ? 1 : 0)
                    .scaleEffect(page == 0 ? 1 : 0.95)
                    .allowsHitTesting(page == 0)
                CountdownView(timer: countdownTimer)
                    .opacity(page == 1 ? 1 : 0)
                    .scaleEffect(page == 1 ? 1 : 0.95)
                    .allowsHitTesting(page == 1)
                StopwatchView()
                    .opacity(page == 2 ? 1 : 0)
                    .scaleEffect(page == 2 ? 1 : 0.95)
                    .allowsHitTesting(page == 2)
                IntervalView()
                    .opacity(page == 3 ? 1 : 0)
                    .scaleEffect(page == 3 ? 1 : 0.95)
                    .allowsHitTesting(page == 3)
                PomodoroView()
                    .opacity(page == 4 ? 1 : 0)
                    .scaleEffect(page == 4 ? 1 : 0.95)
                    .allowsHitTesting(page == 4)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea()

            ModeSwitcher(
                page: $page,
                expanded: pillExpanded,
                onNavigate: navigate,
                onExpand: { expandPill(for: 1.2) }
            )
            .padding(.top, 8)

            Text("By ledeasfe-labs / @ledeasfe")
                .font(.system(size: 11, weight: .light, design: .rounded))
                .foregroundColor(Color.white.opacity(0.09))
                .tracking(0.4)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 22)
                .allowsHitTesting(false)
        }
        .simultaneousGesture(swipeGesture)
    }
}
