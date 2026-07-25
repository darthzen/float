import SwiftUI

/// Float's launch view: ripple rings expanding from a single suspended mote.
///
/// Design intent — the ripple *is* the loading indicator. Nothing spins and
/// nothing counts, so an unknown load time never reads as a stall.
///
/// Rings and mote share one loop (`period`), which is what produces the
/// "breathing" cadence. Phase is derived from the timeline date rather than
/// held in view state, so the view stays consistent with the app's one-clock
/// rule; swap `now` for `AnimationClock.simTime` if that is already running
/// this early.
struct SplashView: View {

    var tagline: String = "Finding a quiet part of the sky"
    var showsProgress: Bool = true

    /// Shared loop length for rings and mote.
    private let period: Double = 6.2
    private let ringCount = 3
    /// The rings are flattened — a surface seen at a shallow angle, not a bullseye.
    private let ringSize = CGSize(width: 520, height: 300)
    /// Exposed so the exit transition can carry the last ring past the window bounds.
    let ringScaleRange: ClosedRange<Double> = 0.24...1.75

    var body: some View {
        TimelineView(.animation) { context in
            let now = context.date.timeIntervalSinceReferenceDate
            let loop = (now / period).truncatingRemainder(dividingBy: 1)

            ZStack {
                starfield

                ZStack {
                    // Static guide ring: keeps the composition from emptying out
                    // between pulses.
                    Ellipse()
                        .strokeBorder(Color(red: 0.55, green: 0.75, blue: 1).opacity(0.09), lineWidth: 1)
                        .frame(width: ringSize.width, height: ringSize.height)

                    ForEach(0..<ringCount, id: \.self) { i in
                        let phase = (loop + Double(i) / Double(ringCount))
                            .truncatingRemainder(dividingBy: 1)
                        ripple(phase: phase, index: i)
                    }

                    mote(loop: loop)
                }
                .offset(y: drift(now) - 24) // group sits slightly above centre

                VStack(spacing: 22) {
                    Text("FLOAT")
                        .font(.system(size: 46, weight: .light))
                        .tracking(21)                       // ≈ 0.46em
                        .padding(.leading, 21)              // balances the trailing track
                        .foregroundStyle(Color(red: 0.93, green: 0.95, blue: 0.98))
                        .shadow(color: Color(red: 0.59, green: 0.77, blue: 1).opacity(0.25), radius: 20)

                    Text(tagline.uppercased())
                        .font(.system(size: 13, design: .monospaced))
                        .tracking(2.6)
                        .foregroundStyle(Color(red: 0.75, green: 0.82, blue: 0.94).opacity(0.58))
                }
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, showsProgress ? 210 : 170)

                if showsProgress {
                    progressHairline(now: now)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                        .padding(.bottom, 96)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(background)
        }
    }

    // MARK: - Pieces

    private var background: some View {
        RadialGradient(
            stops: [
                .init(color: Color(red: 0.086, green: 0.137, blue: 0.247), location: 0),
                .init(color: Color(red: 0.039, green: 0.059, blue: 0.129), location: 0.46),
                .init(color: Color(red: 0.016, green: 0.024, blue: 0.051), location: 1)
            ],
            center: UnitPoint(x: 0.5, y: 0.48),
            startRadius: 0,
            endRadius: 640
        )
        .ignoresSafeArea()
    }

    /// Deterministic star field — seeded so the launch view is identical every time.
    private var starfield: some View {
        Canvas { ctx, size in
            var seed: UInt64 = 20260725
            func rnd() -> Double {
                seed = seed &* 6364136223846793005 &+ 1442695040888963407
                return Double(seed >> 11) / Double(1 << 53)
            }
            for _ in 0..<160 {
                let x = rnd() * size.width
                let y = rnd() * size.height
                let r = 0.5 + rnd() * 1.4
                let a = 0.28 + rnd() * 0.5
                ctx.fill(
                    Path(ellipseIn: CGRect(x: x, y: y, width: r * 2, height: r * 2)),
                    with: .color(.white.opacity(a))
                )
            }
        }
        .blur(radius: 0.3)
        .ignoresSafeArea()
    }

    private func ripple(phase: Double, index: Int) -> some View {
        // Ease-out expansion, with a quick fade in and a long fade out.
        let eased = 1 - pow(1 - phase, 2.2)
        let scale = ringScaleRange.lowerBound
            + (ringScaleRange.upperBound - ringScaleRange.lowerBound) * eased
        let opacity: Double = {
            if phase < 0.14 { return (phase / 0.14) * 0.9 }
            return 0.9 * (1 - (phase - 0.14) / 0.86)
        }() * (1 - Double(index) * 0.16)

        return Ellipse()
            .strokeBorder(Color(red: 0.66, green: 0.83, blue: 1).opacity(0.55), lineWidth: 2)
            .frame(width: ringSize.width, height: ringSize.height)
            .shadow(color: Color(red: 0.43, green: 0.67, blue: 1).opacity(0.18), radius: 20)
            .scaleEffect(scale)
            .opacity(opacity)
    }

    private func mote(loop: Double) -> some View {
        let pulse = sin(loop * 2 * .pi)
        return Circle()
            .fill(
                RadialGradient(
                    stops: [
                        .init(color: .white, location: 0),
                        .init(color: Color(red: 0.84, green: 0.90, blue: 1), location: 0.38),
                        .init(color: Color(red: 0.59, green: 0.77, blue: 1).opacity(0), location: 1)
                    ],
                    center: .center, startRadius: 0, endRadius: 23
                )
            )
            .frame(width: 46, height: 46)
            .shadow(color: Color(red: 0.55, green: 0.75, blue: 1).opacity(0.3), radius: 35)
            .scaleEffect(1 + pulse * 0.08)
            .opacity(0.89 + pulse * 0.11)
    }

    /// Slow vertical drift — 12 s, intentionally out of sync with the ripple loop.
    private func drift(_ now: Double) -> CGFloat {
        CGFloat(sin(now / 12 * 2 * .pi) * 6)
    }

    private func progressHairline(now: Double) -> some View {
        let t = (now / 2.6).truncatingRemainder(dividingBy: 1)
        let travel = -0.66 + 3.32 * t   // matches the CSS sweep: -100% → 340%

        return ZStack(alignment: .leading) {
            Capsule().fill(Color(red: 0.66, green: 0.83, blue: 1).opacity(0.14))
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.66, green: 0.83, blue: 1).opacity(0),
                            Color(red: 0.78, green: 0.89, blue: 1).opacity(0.9),
                            Color(red: 0.66, green: 0.83, blue: 1).opacity(0)
                        ],
                        startPoint: .leading, endPoint: .trailing
                    )
                )
                .frame(width: 66)
                .offset(x: 220 * travel)
        }
        .frame(width: 220, height: 1.5)
        .clipShape(Capsule())
    }
}

#Preview(windowStyle: .plain) {
    SplashView()
        .frame(width: 1280, height: 800)
}
