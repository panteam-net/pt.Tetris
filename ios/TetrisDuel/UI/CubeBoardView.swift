import UIKit

private struct Face {
    let depth: Double
    let points: [CGPoint]
    let color: UIColor
}

/// Native UIKit/Core Graphics projection of lit 3D cube geometry. Gameplay
/// remains on the same 10 × 20 plane as the Python version.
private struct CubeProjection {
    let center: CGPoint
    let scale: CGFloat
    let yaw: Double
    let pitch: Double

    func transform(_ p: SIMD3<Double>) -> SIMD3<Double> {
        let x = cos(yaw) * p.x + sin(yaw) * p.z
        let z = -sin(yaw) * p.x + cos(yaw) * p.z
        return SIMD3(x, cos(pitch) * p.y - sin(pitch) * z, sin(pitch) * p.y + cos(pitch) * z)
    }
    
    func project(_ point: SIMD3<Double>) -> CGPoint {
        let p = transform(point)
        let perspective = 85 / (85 - p.z)
        return CGPoint(x: center.x + CGFloat(p.x * perspective) * scale,
                       y: center.y - CGFloat(p.y * perspective) * scale)
    }
    
    func cube(x: Double, y: Double, color: UIColor, active: Bool = false) -> [Face] {
        let w = 0.92, h = 0.92, d = 0.86
        let vertices: [SIMD3<Double>] = [SIMD3(x,y,0),SIMD3(x+w,y,0),SIMD3(x+w,y+h,0),SIMD3(x,y+h,0),
                                       SIMD3(x,y,d),SIMD3(x+w,y,d),SIMD3(x+w,y+h,d),SIMD3(x,y+h,d)]
        let definitions: [([Int], SIMD3<Double>, CGFloat)] = [
            ([4,5,6,7], SIMD3(0,0,1), 1), ([3,7,6,2], SIMD3(0,1,0), 1.20),
            ([0,4,7,3], SIMD3(-1,0,0), 0.60), ([1,2,6,5], SIMD3(1,0,0), 0.76)
        ]
        return definitions.compactMap { indices, normal, light in
            guard transform(normal).z > 0 else { return nil }
            let points = indices.map { vertices[$0] }
            return Face(depth: points.reduce(0) { $0 + transform($1).z } / 4,
                        points: points.map(project), color: color.shaded(light * (active ? 1.06 : 1)))
        }
    }
}

private extension UIColor {
    func shaded(_ factor: CGFloat) -> UIColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return UIColor(red: min(1, r*factor), green: min(1, g*factor), blue: min(1, b*factor), alpha: a)
    }
}

private func polygon(_ points: [CGPoint], fill: UIColor?, stroke: UIColor?, width: CGFloat = 0.6) {
    guard let first = points.first else { return }
    let path = UIBezierPath(); path.move(to: first)
    points.dropFirst().forEach { path.addLine(to: $0) }; path.close()
    if let fill = fill { fill.setFill(); path.fill() }
    if let stroke = stroke { stroke.setStroke(); path.lineWidth = width; path.stroke() }
}

final class CubeBoardView: UIView {
    var seat = 0 { didSet { setNeedsDisplay() } }
    var snapshot: BoardSnapshot? {
        didSet { if snapshot != oldValue { setNeedsDisplay() } }
    }
    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = true; backgroundColor = Theme.panel; contentMode = .redraw
        isAccessibilityElement = true
        accessibilityLabel = L10n.text("board.accessibility.label")
    }
    required init?(coder: NSCoder) { fatalError("Use init(frame:)") }

    override func draw(_ rect: CGRect) {
        guard let snapshot = snapshot, bounds.width > 0, bounds.height > 0 else { return }
        let scale = min((bounds.width - 22) / 11.5, (bounds.height - 14) / 21.6)
        guard scale > 0 else { return }
        let camera = CubeProjection(center: CGPoint(x: bounds.midX, y: bounds.midY), scale: scale,
                                    yaw: seat == 0 ? 0.22 : -0.22, pitch: 0.16)
        polygon([SIMD3(-5.15,-10.15,-0.18),SIMD3(5.15,-10.15,-0.18),SIMD3(5.15,10.15,-0.18),SIMD3(-5.15,10.15,-0.18)]
                .map(camera.project), fill: Theme.well, stroke: Theme.line)
        let grid = UIBezierPath()
        for x in 0...10 {
            grid.move(to: camera.project(SIMD3(Double(x)-5,-10,-0.1)))
            grid.addLine(to: camera.project(SIMD3(Double(x)-5,10,-0.1)))
        }
        for y in 0...20 {
            grid.move(to: camera.project(SIMD3(-5,Double(y)-10,-0.1)))
            grid.addLine(to: camera.project(SIMD3(5,Double(y)-10,-0.1)))
        }
        Theme.line.withAlphaComponent(0.5).setStroke(); grid.lineWidth = 0.45; grid.stroke()
        if snapshot.alive {
            for cell in snapshot.piece.cells(dy: snapshot.ghostY-snapshot.piece.y) where cell.y >= Rules.hidden {
                let x = Double(cell.x)-4.96, y = 10-Double(cell.y-Rules.hidden)-0.96
                polygon([SIMD3(x,y,0.85),SIMD3(x+0.92,y,0.85),SIMD3(x+0.92,y+0.92,0.85),SIMD3(x,y+0.92,0.85)]
                        .map(camera.project), fill: Theme.color(snapshot.piece.kind).withAlphaComponent(0.10),
                        stroke: Theme.color(snapshot.piece.kind).withAlphaComponent(0.50))
            }
        }
        var faces: [Face] = []
        for row in Rules.hidden..<Rules.height {
            for column in 0..<Rules.width {
                if let kind = Tetromino(rawValue: snapshot.grid[row*Rules.width+column]) {
                    faces += camera.cube(x: Double(column)-4.96, y: 10-Double(row-Rules.hidden)-0.96, color: Theme.color(kind))
                }
            }
        }
        if snapshot.alive {
            for cell in snapshot.piece.cells() where cell.y >= Rules.hidden {
                faces += camera.cube(x: Double(cell.x)-4.96, y: 10-Double(cell.y-Rules.hidden)-0.96,
                                     color: Theme.color(snapshot.piece.kind), active: true)
            }
        }
        for face in faces.sorted(by: { $0.depth < $1.depth }) {
            polygon(face.points, fill: face.color, stroke: UIColor.white.withAlphaComponent(0.24))
        }
        let rail = UIBezierPath()
        rail.move(to: camera.project(SIMD3(-5.2,-10.25,0.6)))
        rail.addLine(to: camera.project(SIMD3(5.2,-10.25,0.6)))
        Theme.accent(seat).withAlphaComponent(0.7).setStroke(); rail.lineWidth = 3; rail.stroke()
        if snapshot.incoming > 0 {
            let height = min(bounds.height-30, CGFloat(snapshot.incoming)*scale)
            let meter = UIBezierPath(roundedRect: CGRect(x: bounds.width-7, y: bounds.height-15-height, width: 4, height: height), cornerRadius: 2)
            Theme.color(.z).setFill(); meter.fill()
        }
        accessibilityValue = L10n.format(
            "board.accessibility.value",
            snapshot.lines,
            snapshot.level,
            snapshot.incoming
        )
    }
}

final class PiecePreview: UIView {
    var kind: Tetromino? { didSet { if kind != oldValue { setNeedsDisplay() } } }
    var dimmed = false { didSet { if dimmed != oldValue { setNeedsDisplay() } } }
    override init(frame: CGRect) { super.init(frame: frame); backgroundColor = .clear; contentMode = .redraw }
    required init?(coder: NSCoder) { fatalError("Use init(frame:)") }
    override func draw(_ rect: CGRect) {
        guard let kind = kind else { return }
        let cells = kind.cells[0]
        let midX = Double((cells.map(\.x).min() ?? 0) + (cells.map(\.x).max() ?? 0) + 1) / 2
        let midY = Double((cells.map(\.y).min() ?? 0) + (cells.map(\.y).max() ?? 0) + 1) / 2
        let camera = CubeProjection(center: CGPoint(x: bounds.midX, y: bounds.midY),
                                    scale: min(bounds.width/4.8, bounds.height/3), yaw: 0.24, pitch: 0.2)
        let color = Theme.color(kind).withAlphaComponent(dimmed ? 0.35 : 1)
        let faces = cells.flatMap { camera.cube(x: Double($0.x)-midX+0.04, y: midY-Double($0.y)-0.96, color: color) }
        for face in faces.sorted(by: { $0.depth < $1.depth }) {
            polygon(face.points, fill: face.color, stroke: UIColor.white.withAlphaComponent(0.15))
        }
    }
}
