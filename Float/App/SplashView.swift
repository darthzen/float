import SwiftUI

/// Float's launch view: a single suspended mote inside frozen ripple rings.
///
/// **Deliberately static — do not reintroduce animation here.** This view was
/// originally a `TimelineView(.animation)` whose ripples, mote pulse, drift and
/// progress sweep all derived their phase from the timeline date. The scene load
/// blocks the main thread in bursts, so the timeline stopped ticking and the
/// animation froze and jumped rather than reading as motion — worse than no
/// motion at all. Moving the ~150 MP stereo HEIC decode off the main actor
/// (see `SpatialImageEnvironment.loadEyes`) removed one large stall but not the
/// stutter; the rest is RealityKit's own main-thread work uploading the texture,
/// which the app cannot relocate. Any main-thread-driven animation on this
/// screen will freeze the same way, so the composition is a still frame and the
/// status line carries the "something is happening" job instead.
struct SplashView: View {

    var tagline: String = "Finding a quiet part of the sky"
    var statusText: String = "Loading starmaps…"
    var showsProgress: Bool = true

    private let ringCount = 3
    /// The rings are flattened — a surface seen at a shallow angle, not a bullseye.
    private let ringSize = CGSize(width: 520, height: 300)
    /// Frozen phases for the three rings, spread across the old loop so the
    /// still frame keeps the layered-ripple silhouette.
    private let ringPhases: [Double] = [0.16, 0.49, 0.82]
    private let ringScaleRange: ClosedRange<Double> = 0.24...1.75

    var body: some View {
        ZStack {
            starfield

            ZStack {
                // Static guide ring: keeps the composition from emptying out.
                Ellipse()
                    .strokeBorder(Color(red: 0.55, green: 0.75, blue: 1).opacity(0.09), lineWidth: 1)
                    .frame(width: ringSize.width, height: ringSize.height)

                ForEach(0..<ringCount, id: \.self) { i in
                    ripple(phase: ringPhases[i], index: i)
                }

                mote
            }
            .offset(y: -24) // group sits slightly above centre

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
            .padding(.bottom, showsProgress ? 190 : 170)

            if showsProgress {
                // Static text, and no bar. While the ~100 MB stereo HEIC decodes and
                // uploads there is no honest progress fraction to report, and a bar
                // that stalls at 40% reads worse than one that never claimed to know.
                // This just names what the wait IS.
                Text(statusText.uppercased())
                    .font(.system(size: 12, design: .monospaced))
                    .tracking(2.2)
                    .foregroundStyle(Color(red: 0.72, green: 0.80, blue: 0.93).opacity(0.72))
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 112)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(background)
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

    /// One ring frozen at `phase` of the old expansion curve.
    private func ripple(phase: Double, index: Int) -> some View {
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

    private var mote: some View {
        Circle()
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
    }
}

#Preview(windowStyle: .plain) {
    SplashView()
        .frame(width: 1280, height: 800)
}
