import XCTest
@testable import SwiftEarcut

final class EarcutTests: XCTestCase {

  func testEmpty() {
    XCTAssertEqual(Earcut.tessellate(data: [], holeIndices: []), [])
  }

  func testIndices2D() {
    XCTAssertEqual(Earcut.tessellate(data: [10, 0, 0, 50, 60, 60, 70, 10]), [1, 0, 3, 3, 2, 1])
  }

  func testIndices3D() {
    XCTAssertEqual(
      Earcut.tessellate(data: [10, 0, 0, 0, 50, 0, 60, 60, 0, 70, 10, 0], dim: 3), [1, 0, 3, 3, 2, 1])
  }

  func testInfiniteLoop() {
    _ = Earcut.tessellate(
      data: [1, 2, 2, 2, 1, 2, 1, 1, 1, 2, 4, 1, 5, 1, 3, 2, 4, 2, 4, 1], holeIndices: [5], dim: 3)
  }
}
