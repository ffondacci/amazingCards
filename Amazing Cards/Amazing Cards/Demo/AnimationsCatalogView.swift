import CardCore
import CardFX
import CardPack
import CardUI
import SwiftUI

/// Every motion brick: tilt, flip, float, shake, sweep, dissolve, ripple,
/// fan, swipe stack, tear, chromatic split.
enum AnimationDemo: String, CaseIterable, Identifiable {
    case tilt, flip, idleFloat, shake, sweep, dissolve, ripple, fan, swipeStack, tear, chromatic, transition

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tilt: "Tilt & gyroscope"
        case .flip: "Flip"
        case .idleFloat: "Idle float"
        case .shake: "Shake"
        case .sweep: "Light sweep"
        case .dissolve: "Dissolve"
        case .ripple: "Ripple"
        case .fan: "Hand fan"
        case .swipeStack: "Swipe stack"
        case .tear: "Tear"
        case .chromatic: "Chromatic split"
        case .transition: "Dissolve transition"
        }
    }

    var summary: String {
        switch self {
        case .tilt: "CardMotionStage: showcase circle on appear, drag to tilt, springs back, gyroscope on device."
        case .flip: "FlippableCardView: pop flip on a soft spring, foil reacts to the turn."
        case .idleFloat: "cardIdleFloat: endless levitation with phaseAnimator."
        case .shake: "cardShake: keyframe shake on a trigger."
        case .sweep: "cardSweep: animatable light band."
        case .dissolve: "cardDissolve: noise burn in and out."
        case .ripple: "cardRipple: distortion from the tap point."
        case .fan: "CardFanView: cards held like a hand."
        case .swipeStack: "CardSwipeStack: throw cards out, next one springs in."
        case .tear: "tearable: rip from any edge, snaps back below the threshold."
        case .chromatic: "RGB split following the tilt."
        case .transition: "transition(.cardDissolve()) on insert and remove."
        }
    }

    var symbol: String {
        switch self {
        case .tilt: "rotate.3d"
        case .flip: "arrow.trianglehead.2.clockwise.rotate.90"
        case .idleFloat: "water.waves"
        case .shake: "waveform.path"
        case .sweep: "light.beacon.max"
        case .dissolve: "aqi.medium"
        case .ripple: "dot.radiowaves.left.and.right"
        case .fan: "hand.raised.fingers.spread"
        case .swipeStack: "rectangle.on.rectangle.angled"
        case .tear: "scissors"
        case .chromatic: "camera.filters"
        case .transition: "sparkles"
        }
    }
}

struct AnimationsCatalogView: View {
    var body: some View {
        NavigationStack {
            List(AnimationDemo.allCases) { demo in
                NavigationLink(value: demo) {
                    Label {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(demo.title).font(.headline)
                            Text(demo.summary).font(.caption).foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: demo.symbol).foregroundStyle(.yellow)
                    }
                    .padding(.vertical, 4)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color(white: 0.06))
            .navigationTitle("Animations")
            .navigationDestination(for: AnimationDemo.self) { demo in
                AnimationDemoView(demo: demo)
            }
        }
    }
}

struct AnimationDemoView: View {
    let demo: AnimationDemo
    @State private var isFaceUp = false
    @State private var shakeCount = 0
    @State private var sweep = 0.0
    @State private var dissolve = 0.0
    @State private var rippleElapsed = 0.0
    @State private var rippleCenter = CGPoint.zero
    @State private var selectedFan: CardID?
    @State private var stackIndex = 0
    @State private var tearState = TearState()
    @State private var tearCount = 0
    @State private var showsCard = true

    private let card = SampleLibrary.starryNight
    private let foilCard = SampleLibrary.pillars

    var body: some View {
        VStack(spacing: 18) {
            stage
                .frame(maxWidth: 460)
                .padding(.horizontal, 28)
                .frame(maxHeight: .infinity)
            controls
                .padding(.horizontal)
                .padding(.bottom, 12)
            Text(demo.summary)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
                .padding(.bottom, 8)
        }
        .padding(.top, 8)
        .background(Color(white: 0.06).ignoresSafeArea())
        .navigationTitle(demo.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var stage: some View {
        switch demo {
        case .tilt:
            InteractiveCardView(card: foilCard, showcase: true)
        case .flip:
            CardMotionStage(interaction: .none, animates: false) {
                FlippableCardView(card: foilCard, isFaceUp: $isFaceUp)
            }
        case .idleFloat:
            CardView(card: card)
                .cardMotionIdle(animates: false)
                .cardIdleFloat(amplitude: 8)
                .shadow(color: .black.opacity(0.5), radius: 20, y: 16)
        case .shake:
            CardView(card: card)
                .cardMotionIdle(animates: false)
                .cardShake(trigger: shakeCount, amplitude: 14)
        case .sweep:
            CardView(card: card)
                .cardMotionIdle(animates: false)
                .cardSweep(progress: sweep, intensity: 0.9, width: 0.14, angle: 30)
        case .dissolve:
            CardView(card: card)
                .cardMotionIdle(animates: false)
                .cardDissolve(progress: dissolve, edgeColor: .gold)
        case .ripple:
            CardView(card: foilCard)
                .cardMotionIdle(animates: true)
                .cardRipple(center: rippleCenter, elapsed: rippleElapsed, amplitude: 14, frequency: 0.1)
                .onTapGesture { location in
                    rippleCenter = location
                    rippleElapsed = 0
                    withAnimation(.linear(duration: 2.2)) { rippleElapsed = 2.2 }
                }
        case .fan:
            CardFanView(cards: Array(SampleLibrary.all.prefix(5)), selectedID: selectedFan) { card in
                selectedFan = selectedFan == card.id ? nil : card.id
            }
            .cardMotionIdle(animates: false)
        case .swipeStack:
            CardSwipeStack(cards: SampleLibrary.all, index: $stackIndex)
        case .tear:
            CardView(card: card)
                .cardMotionIdle(animates: false)
                .tearable(TearConfiguration(direction: .any, maxGap: 30, roughness: 6, breakThreshold: 0.75), state: tearState) {
                    tearCount += 1
                }
                .id(tearCount)
                .sensoryFeedback(.success, trigger: tearCount)
        case .chromatic:
            CardMotionStage(animates: false) {
                CardView(card: card).cardEffect(.chromatic(amount: 10))
            }
        case .transition:
            ZStack {
                if showsCard {
                    CardView(card: foilCard)
                        .cardMotionIdle(animates: false)
                        .transition(.cardDissolve(edgeColor: .aurora))
                }
            }
            .aspectRatio(CardMetrics.aspectRatio, contentMode: .fit)
        }
    }

    @ViewBuilder
    private var controls: some View {
        switch demo {
        case .flip:
            Button("Flip") {
                withAnimation(.cardFlip) { isFaceUp.toggle() }
            }
            .buttonStyle(.borderedProminent)
        case .shake:
            Button("Shake") { shakeCount += 1 }.buttonStyle(.borderedProminent)
        case .sweep:
            Button("Sweep") {
                sweep = 0
                withAnimation(.easeInOut(duration: 1.2)) { sweep = 1 }
            }
            .buttonStyle(.borderedProminent)
        case .dissolve:
            HStack {
                Button("Burn") { withAnimation(.easeIn(duration: 1.2)) { dissolve = 1 } }
                Button("Restore") { withAnimation(.easeOut(duration: 1.2)) { dissolve = 0 } }
            }
            .buttonStyle(.borderedProminent)
        case .swipeStack:
            HStack {
                Text("\(min(stackIndex + 1, SampleLibrary.all.count)) / \(SampleLibrary.all.count)")
                Button("Reset") { stackIndex = 0 }
            }
            .buttonStyle(.bordered)
        case .tear:
            Button("Reset") {
                tearState = TearState()
                tearCount += 1
            }
            .buttonStyle(.bordered)
        case .transition:
            Button(showsCard ? "Remove" : "Insert") {
                withAnimation(.easeInOut(duration: 1.1)) { showsCard.toggle() }
            }
            .buttonStyle(.borderedProminent)
        case .ripple:
            Text("Tap the card").font(.subheadline).foregroundStyle(.secondary)
        case .tilt, .idleFloat, .fan, .chromatic:
            EmptyView()
        }
    }
}
