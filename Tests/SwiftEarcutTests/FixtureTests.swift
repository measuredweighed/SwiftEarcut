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

  /// Exact quarter turns, so the rotation itself introduces no rounding and any change in
  /// the result is the algorithm reacting to orientation.
  static func rotated(_ rings: [[[Double]]], _ quarter: Int) -> [[[Double]]] {
    guard quarter != 0 else { return rings }
    return rings.map { ring in
      ring.map { point in
        var p = point
        let x = point[0], y = point[1]
        switch quarter {
        case 1: p[0] = -y; p[1] = x
        case 2: p[0] = -x; p[1] = -y
        default: p[0] = y; p[1] = -x
        }
        return p
      }
    }
  }

  func check(_ name: String, quarter: Int = 0) -> String? {
    guard let source = Self.rings(name) else { return "missing fixture" }
    guard let expectedTriangles = Self.expected.triangles[name] else { return "no expected entry" }

    let rings = Self.rotated(source, quarter)
    let flat = Earcut.flatten(rings)
    let indices = Earcut.tessellate(flat.vertices, holeIndices: flat.holes, dim: flat.dimensions)
    let count = indices.count / 3

    // Which ears are available depends on orientation, so the triangle count is only fixed
    // for the unrotated fixture - upstream's counts vary the same way. Rotated runs are held
    // to the area check alone.
    if quarter == 0, count != expectedTriangles {
      return "expected \(expectedTriangles) triangles, got \(count)"
    }
    guard count > 0 else { return nil }

    let tolerance = quarter == 0
      ? Self.expected.errors[name] ?? 1e-14
      : Self.expected.errorsWithRotation[name] ?? Self.expected.errors[name] ?? 1e-14
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

  func testFixturesUnderRotation() {
    var failures = [String]()
    for name in Self.expected.triangles.keys.sorted() {
      for quarter in 1 ... 3 {
        if let failure = check(name, quarter: quarter) {
          failures.append("\(name) @\(quarter * 90)°: \(failure)")
        }
      }
    }
    XCTAssertEqual(failures, [])
  }
}
