import XCTest
@testable import SwiftEarcut

final class RefineTests: XCTestCase {

  private func fixture(_ name: String) -> (vertices: [Double], holes: [Int], dimensions: Int) {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .appendingPathComponent("fixtures/\(name).json")
    let rings = try! JSONDecoder().decode([[[Double]]].self, from: try! Data(contentsOf: url))
    return Earcut.flatten(rings)
  }

  private func perimeter(_ t: [UInt32], _ c: [Double], _ dim: Int) -> Double {
    var total = 0.0
    for i in stride(from: 0, to: t.count, by: 3) {
      for k in 0 ..< 3 {
        let p = Int(t[i + k]) * dim, q = Int(t[i + (k + 1) % 3]) * dim
        total += ((c[p] - c[q]) * (c[p] - c[q]) + (c[p + 1] - c[q + 1]) * (c[p + 1] - c[q + 1])).squareRoot()
      }
    }
    return total
  }

  /// Counts interior edges whose opposite vertex falls inside the adjacent triangle's
  /// circumcircle — the edges a Delaunay triangulation would have flipped.
  private func illegalEdges(_ t: [UInt32], _ c: [Double], _ dim: Int) -> Int {
    var twin = [String: Int]()
    var illegal = 0
    for e in 0 ..< t.count {
      let a = t[e], b = t[e - e % 3 + (e + 1) % 3]
      let key = a < b ? "\(a)-\(b)" : "\(b)-\(a)"
      if let s = twin.removeValue(forKey: key) {
        let ar = e - e % 3 + (e + 2) % 3, bl = s - s % 3 + (s + 2) % 3
        let p0 = Int(t[ar]) * dim, pr = Int(t[e]) * dim
        let pl = Int(t[e - e % 3 + (e + 1) % 3]) * dim, p1 = Int(t[bl]) * dim
        if !inCircle(c[p0], c[p0 + 1], c[pr], c[pr + 1], c[pl], c[pl + 1], c[p1], c[p1 + 1]),
           orient(c[p0], c[p0 + 1], c[pr], c[pr + 1], c[p1], c[p1 + 1]) > 0,
           orient(c[p0], c[p0 + 1], c[p1], c[p1 + 1], c[pl], c[pl + 1]) > 0
        { illegal += 1 }
      } else {
        twin[key] = e
      }
    }
    return illegal
  }

  private static let names = [
    "water", "water2", "water3", "water4", "dude", "rain", "hilbert", "eberly-6",
    "issue35", "self-touching", "boxy", "simplified-us-border", "touching-holes3",
    "water-huge", "water-huge2", "outside-ring", "issue34",
  ]

  func testLeavesNoIllegalEdges() {
    for name in Self.names {
      let f = fixture(name)
      var t = Earcut.tessellate(f.vertices, holeIndices: f.holes, dim: f.dimensions)
      Earcut.refine(&t, coords: f.vertices, dim: f.dimensions)
      XCTAssertEqual(illegalEdges(t, f.vertices, f.dimensions), 0, name)
    }
  }

  func testPreservesAreaAndTriangleCount() {
    for name in Self.names {
      let f = fixture(name)
      let base = Earcut.tessellate(f.vertices, holeIndices: f.holes, dim: f.dimensions)
      var refined = base
      Earcut.refine(&refined, coords: f.vertices, dim: f.dimensions)

      XCTAssertEqual(refined.count, base.count, name)
      XCTAssertEqual(Set(refined), Set(base), "\(name) vertex set changed")
      let before = Earcut.deviation(f.vertices, holeIndices: f.holes, dim: f.dimensions, triangles: base)
      let after = Earcut.deviation(f.vertices, holeIndices: f.holes, dim: f.dimensions, triangles: refined)
      XCTAssertEqual(after, before, accuracy: max(before, 1e-9), "\(name) area changed")
    }
  }

  func testShortensTotalPerimeter() {
    var improved = 0
    for name in Self.names {
      let f = fixture(name)
      let base = Earcut.tessellate(f.vertices, holeIndices: f.holes, dim: f.dimensions)
      var refined = base
      Earcut.refine(&refined, coords: f.vertices, dim: f.dimensions)

      let before = perimeter(base, f.vertices, f.dimensions)
      let after = perimeter(refined, f.vertices, f.dimensions)
      XCTAssertLessThanOrEqual(after, before * 1.0000001, name)
      if after < before * 0.999 { improved += 1 }
    }
    XCTAssertGreaterThan(improved, Self.names.count / 2, "refinement barely changed anything")
  }

  func testMatchesTessellatorOverload() {
    let f = fixture("dude")
    let tessellator = Tessellator()
    var a = Earcut.tessellate(f.vertices, holeIndices: f.holes, dim: f.dimensions)
    var b = a
    Earcut.refine(&a, coords: f.vertices, dim: f.dimensions)
    for _ in 0 ..< 3 { tessellator.refine(&b, coords: f.vertices, dim: f.dimensions) }
    XCTAssertEqual(a, b)
  }

  func testIgnoresDegenerateInput() {
    var empty = [UInt32]()
    Earcut.refine(&empty, coords: [])
    XCTAssertEqual(empty, [])

    var single: [UInt32] = [0, 1, 2]
    Earcut.refine(&single, coords: [0, 0, 1, 0, 0, 1])
    XCTAssertEqual(single, [0, 1, 2])
  }
}
