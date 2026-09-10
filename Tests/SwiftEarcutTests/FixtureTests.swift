import XCTest
@testable import SwiftEarcut

final class FixtureTests: XCTestCase {

  struct Expected: Decodable {
    let triangles: [String: Int]
    let errors: [String: Double]
    let errorsWithRotation: [String: Double]

    enum CodingKeys: String, CodingKey {
      case triangles, errors
      case errorsWithRotation = "errors-with-rotation"
    }
  }

  /// Fixtures whose output has not yet been brought up to earcut 3.2.3. Shrinks to empty
  /// as the port lands; the suite fails if one starts passing without being removed.
  static let pendingUpstreamPort: Set<String> = [
    "bad-hole",
    "earcut",
    "eberly-6",
    "filtered-bridge-jhl",
    "infinite-loop-jhl",
    "issue111",
    "issue147",
    "issue16",
    "issue52",
    "touching-holes2",
    "touching-holes3",
    "touching-holes5",
    "touching-holes6",
    "touching4",
    "water",
    "water-huge",
    "water-huge2",
    "water-huge3",
    "water2",
    "water4",
  ]

  static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()

  static let expected: Expected = {
    let data = try! Data(contentsOf: root.appendingPathComponent("expected.json"))
    return try! JSONDecoder().decode(Expected.self, from: data)
  }()

  static func rings(_ name: String) -> [[[Double]]]? {
    guard
      let data = try? Data(contentsOf: root.appendingPathComponent("fixtures/\(name).json")),
      let rings = try? JSONSerialization.jsonObject(with: data) as? [[[Double]]]
    else { return nil }
    return rings
  }

  func check(_ name: String) -> String? {
    guard let rings = Self.rings(name) else { return "missing fixture" }
    guard let expectedTriangles = Self.expected.triangles[name] else { return "no expected entry" }

    let flat = Earcut.flatten(data: rings)
    let indices = Earcut.tessellate(data: flat.vertices, holeIndices: flat.holes, dim: flat.dim)
    let count = indices.count / 3
    if count != expectedTriangles {
      return "expected \(expectedTriangles) triangles, got \(count)"
    }
    guard count > 0 else { return nil }

    let tolerance = Self.expected.errors[name] ?? 1e-14
    let deviation = Earcut.deviation(
      data: flat.vertices, holeIndices: flat.holes, dim: flat.dim, indices: indices)
    if !(deviation < tolerance) {
      return "deviation \(deviation) exceeded \(tolerance)"
    }
    return nil
  }

  func testFixtures() {
    var unexpectedFailures = [String]()
    var unexpectedPasses = [String]()

    for name in Self.expected.triangles.keys.sorted() {
      let failure = check(name)
      let isPending = Self.pendingUpstreamPort.contains(name)
      if let failure, !isPending {
        unexpectedFailures.append("\(name): \(failure)")
      } else if failure == nil, isPending {
        unexpectedPasses.append(name)
      }
    }

    XCTAssertEqual(unexpectedFailures, [], "fixtures regressed")
    XCTAssertEqual(unexpectedPasses, [], "now matching upstream — remove from pendingUpstreamPort")
  }
}
