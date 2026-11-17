import SpriteKit
import WinterCore

/// Draws accumulated snow.
///
/// Each pile is one sprite. Its texture is a single row of pixels describing every column:
/// where the snow's top is, where its underside is (lower inside a rounded window corner), and
/// whether the column is visible. A fragment shader turns that into a mound with an antialiased
/// outline, soft shading toward the base, a faint grain, and a thin cool halo so white snow still
/// reads on a white window. Updating a pile uploads one small row; nothing is re-tessellated, and a
/// pile that has not changed costs nothing.
final class PileRenderer {
    /// Sprite height and how far below the surface line it starts (room for rounded corners)
    static let spriteH = 80.0
    static let base = 16.0
    /// Extra texels either side of the surface for snow that bulges past a square edge
    static let pad = 2
    // 8-bit encoding of the two heights
    static let topBias = 16.0
    static let topRange = 72.0
    static let underRange = 24.0

    private final class PileNode {
        let sprite: SKSpriteNode
        let texture: SKMutableTexture
        let texels: Int
        var version: UInt64 = 0
        var stamp = 0
        init(sprite: SKSpriteNode, texture: SKMutableTexture, texels: Int) {
            self.sprite = sprite
            self.texture = texture
            self.texels = texels
        }
    }

    private let parent: SKNode
    private let shader: SKShader
    private let shadeUniform = SKUniform(name: "u_shade", float: 0.75)
    private let haloUniform = SKUniform(name: "u_halo", float: 0.14)
    private var nodes: [Int: PileNode] = [:]
    private var stamp = 0
    private var dead: [Int] = []

    var lightBackground = false {
        didSet {
            guard lightBackground != oldValue else { return }
            shadeUniform.floatValue = lightBackground ? 0.9 : 0.75
            haloUniform.floatValue = lightBackground ? 0.34 : 0.14
        }
    }

    init(parent: SKNode) {
        self.parent = parent
        shader = SKShader(source: PileRenderer.source, uniforms: [shadeUniform, haloUniform])
    }

    // R = top of the snow, G = how far its underside is below the surface line (both in px), B = visible
    private static let source = """
    void main() {
        vec4 d = texture2D(u_texture, vec2(v_tex_coord.x, 0.5));
        d.r = d.r * \(topRange) - \(topBias);
        d.g = d.g * \(underRange);
        float y = v_tex_coord.y * \(spriteH) - \(base);
        float present = smoothstep(0.25, 0.9, d.r + d.g) * d.b;
        float top = clamp(d.r - y + 0.5, 0.0, 1.0);
        float bottom = clamp(y + d.g + 0.5, 0.0, 1.0);
        float body = top * bottom * present;
        float depth = d.r - y;
        float shade = smoothstep(0.5, 7.0, depth) * u_shade;
        vec3 col = mix(vec3(1.0, 1.0, 1.0), vec3(0.74, 0.82, 0.95), shade);
        float g = fract(sin(dot(floor(vec2(v_tex_coord.x * 3000.0, y * 2.0)), vec2(12.9898, 78.233))) * 43758.5453);
        col -= (g - 0.5) * 0.04;
        float halo = clamp(1.0 - (y - d.r) / 2.0, 0.0, 1.0) * (1.0 - top) * bottom * present * u_halo;
        float a = body * 0.97;
        vec3 rgb = col * a + vec3(0.42, 0.52, 0.70) * halo * (1.0 - a);
        gl_FragColor = vec4(rgb, a + halo * (1.0 - a));
    }
    """

    /// Show every surface that reaches into `display`; hide the rest
    func sync(_ surfaces: SurfaceManager, display: Rect) {
        stamp += 1
        for s in surfaces.windows { show(s, display: display) }
        for s in surfaces.limbo { show(s, display: display) }
        if let d = surfaces.dock, d.onScreen { show(d, display: display) }
        for g in surfaces.grounds { show(g, display: display) }

        dead.removeAll(keepingCapacity: true)
        for (id, node) in nodes where node.stamp != stamp {
            node.sprite.isHidden = true
            // A hidden window keeps its node; a surface that no longer exists gives it up
            if surfaces.surface(id: id) == nil { dead.append(id) }
        }
        for id in dead {
            nodes[id]?.sprite.removeFromParent()
            nodes[id] = nil
        }
    }

    private func show(_ s: Surface, display: Rect) {
        let f = s.field
        // Skip piles that lie wholly on another display
        guard f.maxX > display.minX, f.minX < display.maxX,
              f.topY + f.maxH > display.minY, f.topY - PileRenderer.base < display.maxY else { return }
        let texels = f.count + 2 * PileRenderer.pad
        var node = nodes[s.id]
        if node == nil || node!.texels != texels {
            node?.sprite.removeFromParent()
            let texture = SKMutableTexture(size: CGSize(width: texels, height: 1))
            texture.filteringMode = .linear
            let sprite = SKSpriteNode(texture: texture,
                                      size: CGSize(width: Double(texels) * SnowField.colW, height: PileRenderer.spriteH))
            sprite.anchorPoint = .zero
            sprite.zPosition = 5
            sprite.shader = shader
            parent.addChild(sprite)
            node = PileNode(sprite: sprite, texture: texture, texels: texels)
            nodes[s.id] = node
        }
        guard let n = node else { return }
        n.stamp = stamp
        n.sprite.isHidden = false
        n.sprite.position = CGPoint(x: f.minX - Double(PileRenderer.pad) * SnowField.colW, y: f.topY - PileRenderer.base)
        if n.version != f.version {
            n.version = f.version
            write(f, to: n, overhang: s.kind == .window && f.cornerRadius < 1)
        }
    }

    private func write(_ f: SnowField, to node: PileNode, overhang: Bool) {
        let count = f.count
        let texels = node.texels
        node.texture.modifyPixelData { raw, length in
            guard let raw, length >= texels * 4 else { return }
            let px = raw.bindMemory(to: UInt8.self, capacity: texels * 4)
            @inline(__always) func byte(_ v: Double) -> UInt8 { UInt8(max(0, min(255, (v * 255).rounded()))) }
            // Snow at each end, averaged over two columns, drives the bulge past a square edge
            let left = count > 1 ? (f.h[0] + f.h[1]) * 0.5 : f.h[0]
            let right = count > 1 ? (f.h[count - 1] + f.h[count - 2]) * 0.5 : f.h[0]
            for t in 0..<texels {
                let i = t - PileRenderer.pad
                var top = 0.0, under = 0.0, vis = true
                if i >= 0 && i < count {
                    // Light smoothing so the outline is a curve, not a staircase of columns
                    let a = f.h[max(0, i - 1)], b = f.h[i], c = f.h[min(count - 1, i + 1)]
                    let h = f.caps[i] > 0 ? (a + 2 * b + c) * 0.25 : 0
                    top = f.base[i] + h
                    under = -f.base[i]
                    vis = f.visible[i]
                    if overhang {
                        if i == 0 { under += min(3, left * 0.4) * 0.6 }
                        if i == count - 1 { under += min(3, right * 0.4) * 0.6 }
                    }
                } else if overhang {
                    let edge = i < 0 ? left : right
                    let far = i < -1 || i > count
                    top = edge * (far ? 0.28 : 0.74)
                    under = min(3, edge * 0.4) * (far ? 0.4 : 1)
                    vis = f.visible[i < 0 ? 0 : count - 1]
                }
                px[t * 4] = byte((top + PileRenderer.topBias) / PileRenderer.topRange)
                px[t * 4 + 1] = byte(under / PileRenderer.underRange)
                px[t * 4 + 2] = vis ? 255 : 0
                px[t * 4 + 3] = 255
            }
        }
    }
}
