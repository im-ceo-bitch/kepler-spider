import SwiftUI
import SceneKit
import UIKit

// Spyder Originals 01. The protocol is a strict, versioned text envelope.
// It travels through the EXISTING encrypted message path; no media CDN,
// remote rendering, extra permissions, or new server API is required.
enum SpyderOriginal: String, CaseIterable, Identifiable {
    case watcher, blink, threat, webDrop, crawl, phantom, webCast, retreat

    static let prefix = "spyder:originals:v1:"
    var id: String { rawValue }
    var payload: String { Self.prefix + rawValue }

    static func decode(_ message: String) -> Self? {
        guard message.hasPrefix(prefix), message.utf8.count <= 60 else { return nil }
        return Self(rawValue: String(message.dropFirst(prefix.count)))
    }

    var title: String {
        switch self {
        case .watcher: return "Watcher"
        case .blink: return "Blink"
        case .threat: return "Threat"
        case .webDrop: return "Web Drop"
        case .crawl: return "Crawl"
        case .phantom: return "Phantom"
        case .webCast: return "Web Cast"
        case .retreat: return "Retreat"
        }
    }

    var subtitle: String {
        switch self {
        case .watcher: return "Наблюдает из тени"
        case .blink: return "Незаметное движение глаз"
        case .threat: return "Принимает защитную стойку"
        case .webDrop: return "Спускается на паутине"
        case .crawl: return "Бесшумно передвигается"
        case .phantom: return "Растворяется в темноте"
        case .webCast: return "Выпускает нить паутины"
        case .retreat: return "Исчезает в глубине"
        }
    }

    var symbol: String {
        switch self {
        case .watcher: return "eye"
        case .blink: return "eye.slash"
        case .threat: return "bolt.shield"
        case .webDrop: return "arrow.down"
        case .crawl: return "figure.walk.motion"
        case .phantom: return "moon.stars"
        case .webCast: return "circle.hexagongrid"
        case .retreat: return "arrow.uturn.backward"
        }
    }
}

/// GPU-rendered, procedural 3D spider. Geometry and animation are generated on
/// the user's device; no GIF, video, emoji font, or downloaded model involved.
struct SpyderOriginalView: View {
    let original: SpyderOriginal
    let size: CGFloat
    var animated = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        SpyderOriginalScene(original: original,
                            play: animated && !reduceMotion && scenePhase == .active &&
                                  !ProcessInfo.processInfo.isLowPowerModeEnabled)
            .frame(width: size, height: size)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Spyder Originals: \(original.title). \(original.subtitle)")
    }
}

private struct SpyderOriginalScene: UIViewRepresentable {
    let original: SpyderOriginal
    let play: Bool

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero)
        view.scene = SpyderCreatureFactory.make(original)
        view.pointOfView = view.scene?.rootNode.childNode(withName: "originals-camera", recursively: false)
        view.backgroundColor = .clear
        view.isOpaque = false
        view.autoenablesDefaultLighting = false
        view.allowsCameraControl = false
        view.antialiasingMode = .multisampling4X
        view.preferredFramesPerSecond = 30
        view.rendersContinuously = false // SceneKit advances frames while isPlaying.
        view.isPlaying = play
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        if view.scene?.rootNode.name != original.rawValue {
            view.isPlaying = false
            view.scene = SpyderCreatureFactory.make(original)
            view.pointOfView = view.scene?.rootNode.childNode(withName: "originals-camera", recursively: false)
        }
        view.isPlaying = play
        if !play { view.setNeedsDisplay() }
    }

    static func dismantleUIView(_ view: SCNView, coordinator: ()) {
        view.isPlaying = false
        view.scene = nil
    }
}

private enum SpyderCreatureFactory {
    private static func material(_ color: UIColor, metallic: CGFloat = 0.15, rough: CGFloat = 0.6) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = color
        m.metalness.contents = metallic
        m.roughness.contents = rough
        m.isDoubleSided = true
        return m
    }

    private static let armor = material(UIColor(red: 0.052, green: 0.065, blue: 0.075, alpha: 1), metallic: 0.62, rough: 0.35)
    private static let abdomen = material(UIColor(red: 0.025, green: 0.031, blue: 0.041, alpha: 1), metallic: 0.26, rough: 0.52)
    private static let joint = material(UIColor(red: 0.13, green: 0.15, blue: 0.17, alpha: 1), metallic: 0.60, rough: 0.40)
    private static let eye = material(UIColor(red: 0.23, green: 0.32, blue: 0.36, alpha: 1), metallic: 0.82, rough: 0.08)
    private static let silk = material(UIColor(red: 0.58, green: 0.64, blue: 0.68, alpha: 1), metallic: 0.12, rough: 0.23)

    private static func ellipsoid(_ name: String, _ position: SCNVector3, _ scale: SCNVector3,
                                  _ surface: SCNMaterial) -> SCNNode {
        let sphere = SCNSphere(radius: 1)
        sphere.segmentCount = 22
        sphere.firstMaterial = surface
        let node = SCNNode(geometry: sphere)
        node.name = name
        node.position = position
        node.scale = scale
        return node
    }

    private static func segment(from a: SCNVector3, to b: SCNVector3,
                                radius: CGFloat, surface: SCNMaterial) -> SCNNode {
        let dx = b.x - a.x, dy = b.y - a.y, dz = b.z - a.z
        let length = sqrt(dx * dx + dy * dy + dz * dz)
        let cylinder = SCNCylinder(radius: radius, height: CGFloat(length))
        cylinder.radialSegmentCount = 8
        cylinder.firstMaterial = surface
        let node = SCNNode(geometry: cylinder)
        node.position = SCNVector3((a.x + b.x) / 2, (a.y + b.y) / 2, (a.z + b.z) / 2)
        let axis = SCNVector3(dz, 0, -dx) // cross((0,1,0), b-a)
        let angle = acos(max(-1, min(1, dy / max(length, 0.0001))))
        node.rotation = SCNVector4(axis.x, axis.y, axis.z, angle)
        return node
    }

    private static func oscillate(_ positive: SCNAction, _ negative: SCNAction) -> SCNAction {
        .repeatForever(.sequence([positive, negative]))
    }

    static func make(_ original: SpyderOriginal) -> SCNScene {
        let scene = SCNScene()
        scene.rootNode.name = original.rawValue
        scene.background.contents = UIColor.clear
        let body = SCNNode()
        body.name = "originals-01-creature"
        scene.rootNode.addChildNode(body)

        // Anatomical silhouette: cephalothorax, abdomen, pedipalps and four
        // pairs of articulated, tapered legs. No human/cartoon facial features.
        body.addChildNode(ellipsoid("abdomen", SCNVector3(0, -0.02, -0.57),
                                    SCNVector3(0.63, 0.42, 0.77), abdomen))
        body.addChildNode(ellipsoid("carapace", SCNVector3(0, 0.04, 0.28),
                                    SCNVector3(0.52, 0.32, 0.54), armor))
        body.addChildNode(ellipsoid("neck", SCNVector3(0, -0.09, -0.11),
                                    SCNVector3(0.28, 0.20, 0.28), joint))
        // Eight small reflective eyes; no exaggerated cartoon-like pupils.
        for side in [-1.0, 1.0] {
            for (index, point) in [
                SCNVector3(0.14, 0.18, 0.76),
                SCNVector3(0.28, 0.21, 0.70),
                SCNVector3(0.37, 0.17, 0.58),
                SCNVector3(0.43, 0.10, 0.40)
            ].enumerated() {
                // Animate an unscaled parent, not the ellipsoid itself:
                // SCNAction.scale(to: 1) would otherwise inflate the eye to
                // a full unit sphere on the first blink.
                let eyeJoint = SCNNode()
                eyeJoint.position = SCNVector3(Float(side) * point.x, point.y, point.z)
                eyeJoint.addChildNode(ellipsoid("eye-\(index)", SCNVector3Zero,
                    SCNVector3(index == 0 ? 0.076 : 0.048, 0.035, 0.032), eye))
                body.addChildNode(eyeJoint)
                if index == 0 {
                    let close = SCNAction.scale(to: 0.12, duration: 0.09)
                    let open = SCNAction.scale(to: 1, duration: 0.14)
                    eyeJoint.runAction(.repeatForever(.sequence([
                        .wait(duration: original == .blink ? 0.8 : 3.2), close, open
                    ])))
                }
            }
        }
        // Chelicerae (fangs), short pedipalps.
        for side in [-1.0, 1.0] {
            let x = Float(side)
            body.addChildNode(ellipsoid("palp", SCNVector3(x * 0.21, -0.19, 0.69),
                                        SCNVector3(0.14, 0.13, 0.27), armor))
            body.addChildNode(segment(from: SCNVector3(x * 0.12, -0.22, 0.82),
                                       to: SCNVector3(x * 0.15, -0.42, 0.88),
                                       radius: 0.03, surface: joint))
        }
        for side in [-1.0, 1.0] {
            let sign = Float(side)
            for index in 0..<4 {
                let z = Float(0.51 - Double(index) * 0.34)
                let hip = SCNVector3(sign * 0.39, -0.08, z)
                let elbow = SCNVector3(sign * (1.00 + Float(index) * 0.10),
                                       Float(0.35 - Double(index) * 0.055),
                                       z + Float(0.32 - Double(index) * 0.12))
                let foot = SCNVector3(sign * (1.31 + Float(index) * 0.13),
                                      -0.68, z + Float(0.66 - Double(index) * 0.32))
                let tip = SCNVector3(sign * (1.35 + Float(index) * 0.13),
                                     -0.72, foot.z + 0.08)
                let limb = SCNNode()
                limb.name = "leg-\(side)-\(index)"
                limb.position = hip
                func local(_ p: SCNVector3) -> SCNVector3 {
                    SCNVector3(p.x - hip.x, p.y - hip.y, p.z - hip.z)
                }
                let base = SCNVector3Zero
                limb.addChildNode(segment(from: base, to: local(elbow), radius: 0.062, surface: armor))
                limb.addChildNode(ellipsoid("joint", local(elbow), SCNVector3(0.088, 0.088, 0.088), joint))
                limb.addChildNode(segment(from: local(elbow), to: local(foot), radius: 0.037, surface: armor))
                limb.addChildNode(segment(from: local(foot), to: local(tip), radius: 0.018, surface: joint))
                body.addChildNode(limb)
                let amplitude: CGFloat = original == .crawl ? 0.09 : (original == .threat ? 0.085 : 0.025)
                let move = SCNAction.rotateBy(x: 0, y: 0, z: CGFloat(side) * amplitude, duration: 0.7 + Double(index) * 0.10)
                let back = SCNAction.rotateBy(x: 0, y: 0, z: -CGFloat(side) * amplitude, duration: 0.7 + Double(index) * 0.10)
                limb.runAction(.repeatForever(.sequence([.wait(duration: Double(index) * 0.13), move, back])))
            }
        }

        let idle = oscillate(.moveBy(x: 0, y: 0.026, z: 0, duration: 1.4),
                             .moveBy(x: 0, y: -0.026, z: 0, duration: 1.4))
        switch original {
        case .watcher, .blink:
            body.runAction(idle)
        case .threat:
            body.runAction(oscillate(.rotateBy(x: -0.14, y: 0, z: 0, duration: 0.65),
                                     .rotateBy(x: 0.14, y: 0, z: 0, duration: 1.1)))
        case .webDrop:
            body.addChildNode(segment(from: SCNVector3(0, 0.31, -0.55),
                                      to: SCNVector3(0, 2.1, -0.55), radius: 0.010, surface: silk))
            body.position.y = 0.20
            body.runAction(oscillate(.moveBy(x: 0, y: -0.40, z: 0, duration: 1.8),
                                     .moveBy(x: 0, y: 0.40, z: 0, duration: 1.8)))
        case .crawl:
            body.runAction(oscillate(.moveBy(x: -0.25, y: 0, z: 0.08, duration: 0.85),
                                     .moveBy(x: 0.25, y: 0, z: -0.08, duration: 0.85)))
        case .phantom:
            body.runAction(.repeatForever(.sequence([
                .fadeOpacity(to: 0.13, duration: 1.2), .fadeOpacity(to: 1, duration: 1.2),
                .wait(duration: 0.5)
            ])))
        case .webCast:
            let thread = segment(from: SCNVector3(0, -0.28, 0.92),
                                 to: SCNVector3(0, -0.77, 1.66), radius: 0.013, surface: silk)
            thread.opacity = 0
            body.addChildNode(thread)
            thread.runAction(.repeatForever(.sequence([
                .fadeOpacity(to: 0.9, duration: 0.18), .wait(duration: 0.50),
                .fadeOpacity(to: 0, duration: 0.45), .wait(duration: 0.65)
            ])))
            body.runAction(idle)
        case .retreat:
            body.runAction(oscillate(.moveBy(x: 0, y: 0, z: -0.7, duration: 1.05),
                                     .moveBy(x: 0, y: 0, z: 0.7, duration: 1.05)))
        }

        let camera = SCNNode()
        camera.camera = SCNCamera()
        camera.camera?.fieldOfView = 42
        camera.camera?.zNear = 0.1
        camera.camera?.zFar = 40
        camera.position = SCNVector3(0, 1.1, 5.0)
        camera.look(at: SCNVector3(0, -0.05, 0))
        scene.rootNode.addChildNode(camera)
        camera.name = "originals-camera"
        for (position, color, intensity) in [
            (SCNVector3(-3, 4, 4), UIColor(white: 0.88, alpha: 1), CGFloat(1200)),
            (SCNVector3(3, 2, -3), UIColor(red: 0.35, green: 0.53, blue: 0.62, alpha: 1), CGFloat(1400)),
            (SCNVector3(0, -2, 4), UIColor(white: 0.38, alpha: 1), CGFloat(350))
        ] {
            let light = SCNNode()
            light.light = SCNLight()
            light.light?.type = .omni
            light.light?.color = color
            light.light?.intensity = intensity
            light.position = position
            scene.rootNode.addChildNode(light)
        }
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.color = UIColor(white: 0.16, alpha: 1)
        scene.rootNode.addChildNode(ambient)
        return scene
    }
}

struct SpyderOriginalsPicker: View {
    let canSend: Bool
    let onSend: (SpyderOriginal) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selection: SpyderOriginal = .watcher

    private let columns = [GridItem(.flexible(), spacing: 9), GridItem(.flexible(), spacing: 9)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    VStack(spacing: 4) {
                        SpyderOriginalView(original: selection, size: 178)
                            .id(selection)
                            .frame(height: 184)
                        Text(selection.title.uppercased())
                            .font(.system(size: 15, weight: .bold, design: .monospaced))
                            .tracking(2.5)
                        Text(selection.subtitle)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.black, in: RoundedRectangle(cornerRadius: 25))
                    LazyVGrid(columns: columns, spacing: 9) {
                        ForEach(SpyderOriginal.allCases) { original in
                            Button {
                                selection = original
                                UISelectionFeedbackGenerator().selectionChanged()
                            } label: {
                                HStack(spacing: 9) {
                                    Image(systemName: original.symbol)
                                        .font(.system(size: 17, weight: .light))
                                        .frame(width: 23)
                                    Text(original.title)
                                        .font(.system(size: 12, weight: .semibold))
                                        .lineLimit(1)
                                    Spacer(minLength: 0)
                                }
                                .foregroundStyle(selection == original ? Color.white : WalletTheme.ink)
                                .padding(12)
                                .background(selection == original ? Color(white: 0.16) : WalletTheme.surface,
                                            in: RoundedRectangle(cornerRadius: 14))
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(selection == original ? .isSelected : [])
                        }
                    }
                    Button {
                        onSend(selection)
                        dismiss()
                    } label: {
                        Text("Отправить · \(selection.title)")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.black)
                    .disabled(!canSend)
                    Text("Собственная 3D-анимация Spyder. Получатель увидит её, если его приложение поддерживает Originals 01.")
                        .font(.system(size: 11))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
                .padding(16)
            }
            .background(WalletTheme.canvas)
            .navigationTitle("Spyder Originals 01")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Готово") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
    }
}
