import SwiftUI
import RealityKit
import UIKit

/// 3D solar-system view of the user's circle: the user is the sun,
/// each connection is a planet on one of three orbital rings (family /
/// close / broader). Replaces the 2.5D `CircleMandalaView`.
///
/// Solar mode is intentionally always-cosmic regardless of light/dark
/// mode — the parent page paints its background pure black to match,
/// and the sky dome is set to pure black so the RealityView and the
/// surrounding chrome read as one continuous backdrop.
struct CircleSolarSystemView: View {
    let connections: [Connection]
    /// Phase 6 — invoked when the user taps a planet or its avatar
    /// moon. Routes to chat / detail at the call site.
    let onTap: (UUID) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sceneHolder = SceneHolder()
    @State private var azimuth: Float = Self.defaultAzimuth
    @State private var elevation: Float = Self.defaultElevation
    @State private var distance: Float = Self.defaultDistance
    @GestureState private var dragDelta: CGSize = .zero
    @GestureState private var pinchScale: CGFloat = 1.0

    private static let dragSensitivity: Float = 0.0055      // rad per point
    private static let minDistance: Float = 1.6
    private static let maxDistance: Float = 8.5
    private static let minElevation: Float = -1.30          // rad, ~-74°
    private static let maxElevation: Float = 1.30           // rad, ~+74°
    private static let defaultAzimuth: Float = 0
    private static let defaultElevation: Float = 0.15
    private static let defaultDistance: Float = 3.9

    var body: some View {
        RealityView { content in
            content.add(sceneHolder.scene.root)
            // Don't touch the sky dome here — the scene's init
            // applied the procedural starfield/nebula already, and
            // overriding with a flat color would erase it.
            sceneHolder.scene.setConnections(connections)
            sceneHolder.scene.applyCameraState(
                azimuth: liveAzimuth,
                elevation: liveElevation,
                distance: liveDistance)
            MotionPreferences.reduceMotion = reduceMotion
        } update: { _ in
            // Camera tracks gesture state. Connections are diffed via
            // the .onChange below so we don't rebuild planets every
            // gesture frame.
            sceneHolder.scene.applyCameraState(
                azimuth: liveAzimuth,
                elevation: liveElevation,
                distance: liveDistance)
            MotionPreferences.reduceMotion = reduceMotion
        }
        .onChange(of: connections) { _, newConnections in
            sceneHolder.scene.setConnections(newConnections)
        }
        .onChange(of: reduceMotion) { _, newValue in
            MotionPreferences.reduceMotion = newValue
        }
        .simultaneousGesture(dragGesture)
        .simultaneousGesture(magnifyGesture)
        .simultaneousGesture(doubleTapGesture)
        .simultaneousGesture(planetTapGesture)
        .accessibilityRepresentation {
            // VoiceOver navigates this hidden representation rather
            // than the RealityView. Each connection becomes a
            // discoverable, tappable element with name + relation +
            // recency announced — without this, the whole 3D scene
            // is one opaque "image" element.
            accessibilityList
        }
    }

    // MARK: - Live gesture state

    /// Live azimuth combines the committed value with the in-flight
    /// drag delta — horizontal pan rotates around Y. Modulo 2π so
    /// repeated rotations don't accumulate float precision loss.
    private var liveAzimuth: Float {
        let raw = azimuth - Float(dragDelta.width) * Self.dragSensitivity
        return raw.truncatingRemainder(dividingBy: .pi * 2)
    }

    private var liveElevation: Float {
        clamp(
            elevation - Float(dragDelta.height) * Self.dragSensitivity,
            min: Self.minElevation,
            max: Self.maxElevation)
    }

    /// Pinch-out (scale > 1) zooms in (smaller distance), pinch-in
    /// zooms out — matches Photos / Maps convention.
    private var liveDistance: Float {
        clamp(
            distance / Float(pinchScale),
            min: Self.minDistance,
            max: Self.maxDistance)
    }

    // MARK: - Gestures

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 4)
            .updating($dragDelta) { value, state, _ in
                state = value.translation
            }
            .onEnded { value in
                let raw = azimuth - Float(value.translation.width) * Self.dragSensitivity
                azimuth = raw.truncatingRemainder(dividingBy: .pi * 2)
                elevation = clamp(
                    elevation - Float(value.translation.height) * Self.dragSensitivity,
                    min: Self.minElevation,
                    max: Self.maxElevation)
            }
    }

    private var magnifyGesture: some Gesture {
        // iOS 18+ replacement for the deprecated `MagnificationGesture`.
        // `MagnifyGesture.Value` is a struct, so the scale comes from
        // `.magnification` rather than the raw value.
        MagnifyGesture()
            .updating($pinchScale) { value, state, _ in
                state = value.magnification
            }
            .onEnded { value in
                distance = clamp(
                    distance / Float(value.magnification),
                    min: Self.minDistance,
                    max: Self.maxDistance)
            }
    }

    private var doubleTapGesture: some Gesture {
        TapGesture(count: 2)
            .onEnded {
                // Spring back to the default framing — matches the
                // double-tap reset convention from Photos / Maps and
                // gives the user a discoverable escape from any
                // disorienting camera state. Reduce Motion → cut
                // directly instead of springing.
                if reduceMotion {
                    azimuth = Self.defaultAzimuth
                    elevation = Self.defaultElevation
                    distance = Self.defaultDistance
                } else {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                        azimuth = Self.defaultAzimuth
                        elevation = Self.defaultElevation
                        distance = Self.defaultDistance
                    }
                }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
    }

    private var planetTapGesture: some Gesture {
        SpatialTapGesture()
            .targetedToAnyEntity()
            .onEnded { value in
                // Walk up the hit entity's parent chain looking for
                // a tappable carrier. Either the planet or its avatar
                // moon counts — they both map to the same
                // connection id, so users can hit whichever's closer
                // to their finger.
                var entity: Entity? = value.entity
                while let e = entity {
                    if let planet = e as? PlanetEntity {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        onTap(planet.connectionId)
                        return
                    }
                    if let moon = e as? AvatarMoonEntity {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        onTap(moon.connectionId)
                        return
                    }
                    entity = e.parent
                }
            }
    }

    // MARK: - Accessibility

    /// Hidden SwiftUI list that VoiceOver navigates instead of the
    /// 3D scene. Each connection is a Button with a descriptive label
    /// (name, relation, recency) so the visualization is reachable
    /// without sight.
    @ViewBuilder
    private var accessibilityList: some View {
        VStack(spacing: 0) {
            Text("Solar circle visualization. \(connections.count) connections.")
                .accessibilityAddTraits(.isHeader)
            ForEach(connections) { conn in
                Button {
                    onTap(conn.id)
                } label: {
                    Text(accessibilityLabel(for: conn))
                }
                .accessibilityHint("Double tap to open chat or details")
            }
        }
    }

    private func accessibilityLabel(for connection: Connection) -> String {
        var parts: [String] = [connection.displayLabel, connection.relationLabel.lowercased()]
        if connection.unreadCount > 0 {
            parts.append("\(connection.unreadCount) unread")
        }
        if let date = FriendsDates.parse(connection.lastMessageAt) {
            let hours = Date().timeIntervalSince(date) / 3600
            if hours <= 48 {
                parts.append("active recently")
            } else if hours <= 720 {
                parts.append("active this month")
            }
        }
        return parts.joined(separator: ", ")
    }

    // MARK: - Helpers

    private func clamp(_ value: Float, min lower: Float, max upper: Float) -> Float {
        Swift.min(upper, Swift.max(lower, value))
    }

    /// `@State` requires its value to be initialized at declaration,
    /// but `SolarSystemScene` is `@MainActor`-isolated so it can't
    /// run in a property initializer outside the main actor. Wrapping
    /// it in a class lets us defer construction to the first body
    /// evaluation (which IS main-actor) while keeping a stable
    /// reference across re-renders.
    @MainActor
    private final class SceneHolder {
        let scene: SolarSystemScene
        init() { self.scene = SolarSystemScene() }
    }
}
