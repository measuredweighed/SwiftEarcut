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
    let result = Earcut.tessellate(data: vertices, holeIndices: [n], dim: 2)
    XCTAssertFalse(result.isEmpty)
  }
}
