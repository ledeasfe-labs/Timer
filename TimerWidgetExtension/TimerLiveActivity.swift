import ActivityKit
import SwiftUI
import WidgetKit

// MARK: - Attributes
// This struct must stay byte-for-byte identical to the one in ContentView.swift.

struct TimerActivityAttributes: ActivityAttributes {
    var accentHex: String
    var totalDuration: TimeInterval

    struct ContentState: Codable, Hashable {
        var endDate: Date
        var isPaused: Bool
        var pausedRemaining: TimeInterval
    }
}

// MARK: - Widget Bundle Entry Point

@main
struct TimerWidgetBundle: WidgetBundle {
    var body: some Widget {
        TimerLiveActivity()
    }
}

// MARK: - Live Activity Widget

struct TimerLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TimerActivityAttributes.self) { context in
            TimerLockScreenView(context: context)
                .activityBackgroundTint(.black.opacity(0.78))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("TIMER", systemImage: "timer")
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(1.5)
                        .foregroundColor(.secondary)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Image(systemName: context.state.isPaused ? "pause.fill" : "play.fill")
                        .font(.system(size: 13, weight: .light))
                        .foregroundColor(
                            context.state.isPaused
                                ? .secondary
                                : Color(hex: context.attributes.accentHex)
                        )
                }
                DynamicIslandExpandedRegion(.center) {
                    if context.state.isPaused {
                        Text(timerFormatted(context.state.pausedRemaining))
                            .font(.system(size: 30, weight: .thin, design: .rounded))
                            .monospacedDigit()
                            .foregroundColor(.white)
                    } else {
                        Text(context.state.endDate, style: .timer)
                            .font(.system(size: 30, weight: .thin, design: .rounded))
                            .monospacedDigit()
                            .foregroundColor(.white)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    let accent = Color(hex: context.attributes.accentHex)
                    let progress = expandedProgress(context.state, total: context.attributes.totalDuration)
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .tint(accent)
                        .scaleEffect(x: 1, y: 0.55)
                        .padding(.horizontal, 4)
                }
            } compactLeading: {
                Image(systemName: "timer")
                    .font(.system(size: 14, weight: .light))
                    .foregroundColor(Color(hex: context.attributes.accentHex))
            } compactTrailing: {
                if context.state.isPaused {
                    Text(timerFormatted(context.state.pausedRemaining))
                        .font(.system(.caption, design: .rounded).monospacedDigit())
                        .foregroundColor(.secondary)
                } else {
                    Text(context.state.endDate, style: .timer)
                        .font(.system(.caption, design: .rounded).monospacedDigit())
                        .frame(maxWidth: 50)
                }
            } minimal: {
                Image(systemName: "timer")
                    .foregroundColor(Color(hex: context.attributes.accentHex))
            }
            .keylineTint(Color(hex: context.attributes.accentHex))
        }
    }
}

// MARK: - Lock Screen / StandBy / Banner View

struct TimerLockScreenView: View {
    let context: ActivityViewContext<TimerActivityAttributes>

    private var accent: Color { Color(hex: context.attributes.accentHex) }

    var body: some View {
        HStack(spacing: 18) {
            Image(systemName: "timer")
                .font(.system(size: 34, weight: .ultraLight))
                .foregroundColor(accent)

            VStack(alignment: .leading, spacing: 6) {
                if context.state.isPaused {
                    Text(timerFormatted(context.state.pausedRemaining))
                        .font(.system(size: 28, weight: .thin, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(.white)
                } else {
                    Text(context.state.endDate, style: .timer)
                        .font(.system(size: 28, weight: .thin, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(.white)
                }

                ProgressView(value: expandedProgress(context.state, total: context.attributes.totalDuration))
                    .progressViewStyle(.linear)
                    .tint(accent)

                Text(context.state.isPaused ? "PAUSED" : "COUNTING DOWN")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(2)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding(16)
    }
}

// MARK: - Helpers

private func timerFormatted(_ seconds: TimeInterval) -> String {
    let t = Int(seconds.rounded(.up))
    let h = t / 3600, m = (t % 3600) / 60, s = t % 60
    return h > 0
        ? String(format: "%d:%02d:%02d", h, m, s)
        : String(format: "%d:%02d", m, s)
}

private func expandedProgress(
    _ state: TimerActivityAttributes.ContentState,
    total: TimeInterval
) -> Double {
    guard total > 0 else { return 0 }
    let remaining = state.isPaused
        ? state.pausedRemaining
        : max(0, state.endDate.timeIntervalSinceNow)
    return min(1, remaining / total)
}

// MARK: - Color (mirrors ContentView.swift — needed because this is a separate target)

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
        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: Double(a) / 255)
    }
}
