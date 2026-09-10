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

  static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()

  static let expected: Expected = {
    let data = try! Data(contentsOf: root.appendingPathComponent("expected.json"))
    return try! JSONDecoder().decode(Expected.self, from: data)
  }()

  /// JSONDecoder, not JSONSerialization: the latter rounds some fixture decimals to the
  /// wrong double, which shifts the measured deviation well past upstream's tolerances.
  static func rings(_ name: String) -> [[[Double]]]? {
    guard let data = try? Data(contentsOf: root.appendingPathComponent("fixtures/\(name).json")) else {
      return nil
    }
    return try? JSONDecoder().decode([[[Double]]].self, from: data)
  }

  func check(_ name: String) -> String? {
    guard let rings = Self.rings(name) else { return "missing fixture" }
    guard let expectedTriangles = Self.expected.triangles[name] else { return "no expected entry" }

    let flat = Earcut.flatten(rings)
    let indices = Earcut.tessellate(flat.vertices, holeIndices: flat.holes, dim: flat.dimensions)
    let count = indices.count / 3
    if count != expectedTriangles {
      return "expected \(expectedTriangles) triangles, got \(count)"
    }
    guard count > 0 else { return nil }

    let tolerance = Self.expected.errors[name] ?? 1e-14
    let deviation = Earcut.deviation(
      flat.vertices, holeIndices: flat.holes, dim: flat.dimensions, triangles: indices)
    if !(deviation < tolerance) {
      return "deviation \(deviation) exceeded \(tolerance)"
    }
    return nil
  }

  func testFixtures() {
    let failures = Self.expected.triangles.keys.sorted().compactMap { name in
      check(name).map { "\(name): \($0)" }
    }
    XCTAssertEqual(failures, [])
  }
}
