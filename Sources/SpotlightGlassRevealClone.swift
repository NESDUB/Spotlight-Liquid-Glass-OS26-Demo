import SwiftUI

// Standalone macOS 26 SwiftUI Spotlight Liquid Glass clone.
// Purpose: clone the Spotlight-style Liquid Glass reveal from the reference video.
// This file is intentionally standalone.
//
// MEASURED STRUCTURE APPLIED
// Confirmed from the measurement board:
// - Full active rail: 1280px -> 640pt @2x
// - Active search capsule: 768px -> 384pt @2x
// - Accessory buttons: 108px -> 54pt @2x
// - Search-to-button gap: 20px -> 10pt @2x
// - Inter-button gaps: 20px -> 10pt @2x
//
// Structural rule:
// Passive mode full search width == active mode total rail width.
//
// IMPORTANT BUG GUARDRAIL
// This preserves the known no-artifact behavior structure from the baseline:
// - accessory glass circles remain inside the time-gated GlassEffectContainer
// - coalescence is high only during the reveal and low at rest
// - symbols render as a separate foreground layer
// - the bridge is structurally removed when blobOpacity reaches zero
//
// Do not reintroduce the bad branch where the buttons were moved outside the
// container and the bridge was masked/narrowed. That branch caused the transient
// mid-capsule ghosting artifact.

@available(macOS 26.0, *)
public struct SpotlightGlassRevealClone: View {
    @State private var isPointerActive = false
    @State private var hideTask: Task<Void, Never>?
    @State private var revealStart = Date()

    public init() {}

    public var body: some View {
        ZStack {
            CloneBackground()

            VStack(spacing: 20) {
                Spacer()

                SpotlightRevealSurface(
                    isActive: isPointerActive,
                    revealStart: revealStart
                )
                .frame(width: 640, height: 92, alignment: .leading)
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                    case .active:
                        activateAccessoryRail()
                    case .ended:
                        scheduleAccessoryRailHide()
                    }
                }
                .onTapGesture {
                    if isPointerActive {
                        deactivateAccessoryRail()
                    } else {
                        activateAccessoryRail()
                    }
                }

                Text("Move the pointer over the rail, or click to toggle")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.48))

                Spacer()
            }
            .padding(40)
        }
        .frame(width: 820, height: 460)
    }

    private func activateAccessoryRail() {
        hideTask?.cancel()
        hideTask = nil

        if !isPointerActive {
            revealStart = Date()
            withAnimation(.spring(response: 0.44, dampingFraction: 0.62, blendDuration: 0.08)) {
                isPointerActive = true
            }
        }
    }

    private func scheduleAccessoryRailHide() {
        hideTask?.cancel()
        hideTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled else { return }
            deactivateAccessoryRail()
        }
    }

    private func deactivateAccessoryRail() {
        hideTask?.cancel()
        hideTask = nil
        withAnimation(.spring(response: 0.38, dampingFraction: 0.76, blendDuration: 0.05)) {
            isPointerActive = false
        }
    }
}

@available(macOS 26.0, *)
private struct SpotlightRevealSurface: View {
    let isActive: Bool
    let revealStart: Date
    @Namespace private var glassNamespace

    // Confirmed @2x screenshot-derived dimensions.
    private let passiveSearchWidth: CGFloat = 640
    private let activeSearchWidth: CGFloat = 384
    private let capsuleHeight: CGFloat = 56
    private let buttonDiameter: CGFloat = 54
    private let buttonGap: CGFloat = 10

    private var searchWidth: CGFloat {
        isActive ? activeSearchWidth : passiveSearchWidth
    }

    private var accessoryStartX: CGFloat {
        activeSearchWidth + buttonGap
    }

    var body: some View {
        TimelineView(.animation) { context in
            let elapsed = max(0, context.date.timeIntervalSince(revealStart))
            let blobOpacity = blobOpacityForElapsedTime(elapsed)
            let coalescence = coalescenceForElapsedTime(elapsed)

            ZStack(alignment: .leading) {
                // Time-gated coalescence.
                // High only during extrusion; low at rest.
                // This prevents the permanent "glass sausage" failure while preserving
                // the no-artifact baseline layering behavior.
                GlassEffectContainer(spacing: isActive ? 6 + 32 * coalescence : 0) {
                    ZStack(alignment: .leading) {
                        // 1. Primary object: a leading-edge-anchored search capsule.
                        SearchCapsule(width: searchWidth, height: capsuleHeight)
                            .glassEffectID("spotlight-search-capsule", in: glassNamespace)
                            .zIndex(2)

                        // 2. Temporary wavy/coalesced glass mass.
                        // This approximates the brief connected blob visible before the buttons separate.
                        if blobOpacity > 0.001 {
                            AccessoryRevealBlob()
                                .frame(width: 238, height: 58)
                                .offset(x: accessoryStartX - 22, y: 17)
                                .opacity(blobOpacity)
                                .scaleEffect(x: 0.62 + 0.38 * coalescence, y: 0.74 + 0.26 * coalescence, anchor: .leading)
                                .glassEffect(.regular, in: AccessoryRevealBlob())
                                .glassEffectID("spotlight-accessory-blob", in: glassNamespace)
                                .glassEffectTransition(.materialize)
                                .allowsHitTesting(false)
                                .zIndex(1)
                        }

                        // 3. Four staggered trailing accessory glass circles.
                        if isActive {
                            ForEach(Array(accessories.enumerated()), id: \.offset) { index, _ in
                                TrailingAccessoryGlassCircle(
                                    glassEffectID: "spotlight-accessory-\(index)",
                                    glassNamespace: glassNamespace
                                )
                                .frame(width: buttonDiameter, height: buttonDiameter)
                                .position(
                                    x: buttonCenterX(index: index),
                                    y: 44
                                )
                                .opacity(buttonOpacity(index: index, elapsed: elapsed))
                                .scaleEffect(buttonScale(index: index, elapsed: elapsed), anchor: .center)
                                .offset(x: buttonJutOffset(index: index, elapsed: elapsed))
                                .zIndex(3)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                }

                // Symbols render as a separate foreground layer to avoid SF Symbol
                // blur/capture during glass morphing.
                if isActive {
                    ForEach(Array(accessories.enumerated()), id: \.offset) { index, accessory in
                        Image(systemName: accessory.systemName)
                            .font(.system(size: 24, weight: .medium))
                            .symbolRenderingMode(.monochrome)
                            .foregroundStyle(.white.opacity(0.9))
                            .frame(width: buttonDiameter, height: buttonDiameter)
                            .position(
                                x: buttonCenterX(index: index),
                                y: 44
                            )
                            .offset(x: buttonJutOffset(index: index, elapsed: elapsed))
                            .opacity(symbolOpacity(index: index, elapsed: elapsed))
                            .allowsHitTesting(false)
                            .zIndex(4)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }

    private var accessories: [AccessoryDescriptor] {
        [
            AccessoryDescriptor(systemName: "app.badge"),
            AccessoryDescriptor(systemName: "folder"),
            AccessoryDescriptor(systemName: "square.stack.3d.up"),
            AccessoryDescriptor(systemName: "doc.on.doc")
        ]
    }

    private func buttonCenterX(index: Int) -> CGFloat {
        accessoryStartX + buttonDiameter / 2 + CGFloat(index) * (buttonDiameter + buttonGap)
    }

    private func buttonDelay(index: Int) -> TimeInterval {
        0.12 + TimeInterval(index) * 0.055
    }

    private func localProgress(index: Int, elapsed: TimeInterval) -> CGFloat {
        guard isActive else { return 0 }
        let duration: TimeInterval = 0.28
        let raw = (elapsed - buttonDelay(index: index)) / duration
        return min(1, max(0, CGFloat(raw)))
    }

    private func easedProgress(index: Int, elapsed: TimeInterval) -> CGFloat {
        let p = localProgress(index: index, elapsed: elapsed)
        return p * p * (3 - 2 * p)
    }

    private func buttonOpacity(index: Int, elapsed: TimeInterval) -> CGFloat {
        isActive ? easedProgress(index: index, elapsed: elapsed) : 0
    }

    private func symbolOpacity(index: Int, elapsed: TimeInterval) -> CGFloat {
        let delay = buttonDelay(index: index) + 0.12
        let duration: TimeInterval = 0.16
        let raw = (elapsed - delay) / duration
        let p = min(1, max(0, CGFloat(raw)))
        return p * p * (3 - 2 * p)
    }

    private func buttonScale(index: Int, elapsed: TimeInterval) -> CGFloat {
        let p = easedProgress(index: index, elapsed: elapsed)
        return isActive ? (0.36 + 0.64 * p) : 0.36
    }

    private func buttonJutOffset(index: Int, elapsed: TimeInterval) -> CGFloat {
        let p = easedProgress(index: index, elapsed: elapsed)
        // Negative start value makes each button begin tucked into the trailing side,
        // then jut outward into its final position.
        let start = CGFloat(-42 + index * -7)
        return isActive ? start * (1 - p) : start
    }

    private func coalescenceForElapsedTime(_ elapsed: TimeInterval) -> CGFloat {
        guard isActive else { return 0 }

        if elapsed < 0.08 { return CGFloat(elapsed / 0.08) }
        if elapsed < 0.22 { return 1 }
        if elapsed < 0.46 { return CGFloat(1 - ((elapsed - 0.22) / 0.24)) }
        return 0
    }

    private func blobOpacityForElapsedTime(_ elapsed: TimeInterval) -> CGFloat {
        guard isActive else { return 0 }

        // The blob peaks early, then fades as the individual circular buttons resolve.
        if elapsed < 0.06 { return CGFloat(elapsed / 0.06) * 0.46 }
        if elapsed < 0.18 { return 0.46 }
        if elapsed < 0.42 { return 0.46 * CGFloat(1 - ((elapsed - 0.18) / 0.24)) }
        return 0
    }
}

@available(macOS 26.0, *)
private struct SearchCapsule: View {
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        HStack(spacing: 17) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 23, weight: .medium))
                .foregroundStyle(.white.opacity(0.72))

            Text("Spotlight Search")
                .font(.system(size: 22, weight: .regular, design: .rounded))
                .foregroundStyle(.white.opacity(0.64))

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 21)
        .frame(width: width, height: height, alignment: .leading)
        .glassEffect(.regular.interactive(), in: Capsule())
        .overlay {
            Capsule()
                .stroke(
                    LinearGradient(
                        colors: [
                            .white.opacity(0.34),
                            .white.opacity(0.08),
                            .white.opacity(0.22)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.7
                )
        }
        .shadow(color: .black.opacity(0.38), radius: 18, x: 0, y: 10)
    }
}

@available(macOS 26.0, *)
private struct TrailingAccessoryGlassCircle: View {
    let glassEffectID: String
    let glassNamespace: Namespace.ID

    var body: some View {
        Circle()
            .fill(.clear)
            .glassEffect(.regular.interactive(), in: Circle())
            .glassEffectID(glassEffectID, in: glassNamespace)
            .glassEffectTransition(.materialize)
            .overlay {
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [
                                .white.opacity(0.38),
                                .white.opacity(0.08),
                                .white.opacity(0.24)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.75
                    )
            }
            .shadow(color: .black.opacity(0.34), radius: 13, x: 0, y: 8)
    }
}

private struct AccessoryRevealBlob: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()

        let minX = rect.minX
        let maxX = rect.maxX
        let midY = rect.midY
        let top = rect.minY + 5
        let bottom = rect.maxY - 5

        path.move(to: CGPoint(x: minX + 18, y: midY))

        path.addCurve(
            to: CGPoint(x: minX + 55, y: top + 3),
            control1: CGPoint(x: minX + 20, y: top + 15),
            control2: CGPoint(x: minX + 34, y: top + 4)
        )
        path.addCurve(
            to: CGPoint(x: minX + 104, y: top + 8),
            control1: CGPoint(x: minX + 72, y: top - 5),
            control2: CGPoint(x: minX + 91, y: top + 2)
        )
        path.addCurve(
            to: CGPoint(x: minX + 153, y: top + 6),
            control1: CGPoint(x: minX + 118, y: top + 16),
            control2: CGPoint(x: minX + 137, y: top - 2)
        )
        path.addCurve(
            to: CGPoint(x: maxX - 18, y: midY),
            control1: CGPoint(x: maxX - 54, y: top + 14),
            control2: CGPoint(x: maxX - 24, y: top + 10)
        )
        path.addCurve(
            to: CGPoint(x: minX + 153, y: bottom - 6),
            control1: CGPoint(x: maxX - 24, y: bottom - 10),
            control2: CGPoint(x: maxX - 54, y: bottom - 14)
        )
        path.addCurve(
            to: CGPoint(x: minX + 104, y: bottom - 8),
            control1: CGPoint(x: minX + 137, y: bottom + 2),
            control2: CGPoint(x: minX + 118, y: bottom - 16)
        )
        path.addCurve(
            to: CGPoint(x: minX + 55, y: bottom - 3),
            control1: CGPoint(x: minX + 91, y: bottom - 2),
            control2: CGPoint(x: minX + 72, y: bottom + 5)
        )
        path.addCurve(
            to: CGPoint(x: minX + 18, y: midY),
            control1: CGPoint(x: minX + 34, y: bottom - 4),
            control2: CGPoint(x: minX + 20, y: bottom - 15)
        )

        path.closeSubpath()
        return path
    }
}

private struct AccessoryDescriptor {
    let systemName: String
}

private struct CloneBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.018, green: 0.018, blue: 0.024),
                    Color(red: 0.034, green: 0.032, blue: 0.045),
                    Color(red: 0.010, green: 0.010, blue: 0.014)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [
                    Color.white.opacity(0.08),
                    Color.clear
                ],
                center: .topTrailing,
                startRadius: 20,
                endRadius: 460
            )

            RadialGradient(
                colors: [
                    Color.purple.opacity(0.10),
                    Color.clear
                ],
                center: .bottomLeading,
                startRadius: 30,
                endRadius: 520
            )
        }
        .ignoresSafeArea()
    }
}

@available(macOS 26.0, *)
#Preview("Spotlight Glass Reveal Clone") {
    SpotlightGlassRevealClone()
}
