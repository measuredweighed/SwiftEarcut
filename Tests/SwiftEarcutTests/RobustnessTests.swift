import XCTest
@testable import SwiftEarcut

final class RobustnessTests: XCTestCase {
  func testHoleOutsideOuterRingBoundingBox() {
    var vertices = [Double]()
    let n = 100
    for k in 0..<n {
      let a = 2 * Double.pi * Double(k) / Double(n)
      vertices.append(10 * cos(a))
      vertices.append(10 * sin(a))
    }
    vertices += [-5, 0, 0, -50, 0, 50]
    let result = Earcut.tessellate(vertices, holeIndices: [n], dim: 2)
    XCTAssertFalse(result.isEmpty)
  }

  func testEmptyHoleRing() {
    let square: [Double] = [0, 0, 10, 0, 10, 10, 0, 10]
    XCTAssertEqual(Earcut.tessellate(square, holeIndices: [4], dim: 2).count, 6)
  }

  func testNodeLayoutIsUnpadded() {
    XCTAssertEqual(MemoryLayout<Node>.stride, 40)
  }
}

final class TessellatorTests: XCTestCase {

  private static func fixture(_ name: String) -> [[[Double]]] {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .appendingPathComponent("fixtures/\(name).json")
    return try! JSONDecoder().decode([[[Double]]].self, from: try! Data(contentsOf: url))
  }

  /// A reused Tessellator must give the same answer as a fresh one, in any order, so that
  /// nothing leaks between runs through the arena, block index or steiner table.
  func testReuseMatchesFreshAcrossFixtures() {
    let names = ["water", "dude", "touching-holes3", "steiner", "issue16", "hilbert",
                 "degenerate", "water3b", "self-tangent-2", "empty-square"]
    let tessellator = Tessellator()
    for name in names + names.reversed() {
      let flat = Earcut.flatten(Self.fixture(name))
      XCTAssertEqual(
        tessellator.tessellate(flat.vertices, holeIndices: flat.holes, dim: flat.dimensions),
        Earcut.tessellate(flat.vertices, holeIndices: flat.holes, dim: flat.dimensions),
        name)
    }
  }

  func testTessellateIntoReusesOutput() {
    let flat = Earcut.flatten(Self.fixture("dude"))
    let tessellator = Tessellator()
    var output: [UInt32] = [99, 98, 97]
    tessellator.tessellate(flat.vertices, holeIndices: flat.holes, dim: flat.dimensions, into: &output)
    XCTAssertEqual(output, Earcut.tessellate(flat.vertices, holeIndices: flat.holes, dim: flat.dimensions))

    tessellator.tessellate([], into: &output)
    XCTAssertEqual(output, [])
  }
}
