import XCTest
@testable import SwiftEarcut

/// Pins the exact triangulation output of the pre-arena implementation so the arena
/// rewrite can be proven behaviour-preserving. Removed once behaviour intentionally
/// moves to earcut 3.2.3.
final class GoldenTests: XCTestCase {

  static let fixturesDirectory = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .appendingPathComponent("fixtures")

  static let goldenURL = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .appendingPathComponent("golden-2.2.4.json")

  static func fixtureNames() -> [String] {
    let names = (try? FileManager.default.contentsOfDirectory(atPath: fixturesDirectory.path)) ?? []
    return names.filter { $0.hasSuffix(".json") }.map { String($0.dropLast(5)) }.sorted()
  }

  static func tessellate(_ name: String) -> [Int]? {
    guard
      let data = try? Data(contentsOf: fixturesDirectory.appendingPathComponent("\(name).json")),
      let rings = try? JSONSerialization.jsonObject(with: data) as? [[[Double]]],
      let first = rings.first?.first, !first.isEmpty
    else { return nil }
    let flat = Earcut.flatten(data: rings)
    return Earcut.tessellate(data: flat.vertices, holeIndices: flat.holes, dim: flat.dim)
  }

  func testWriteGolden() throws {
    try XCTSkipIf(ProcessInfo.processInfo.environment["EARCUT_WRITE_GOLDEN"] == nil)
    var golden = [String: [Int]]()
    for name in Self.fixtureNames() {
      golden[name] = try XCTUnwrap(Self.tessellate(name), "could not tessellate \(name)")
    }
    let data = try JSONSerialization.data(withJSONObject: golden, options: [.sortedKeys])
    try data.write(to: Self.goldenURL)
    print("wrote \(golden.count) fixtures to \(Self.goldenURL.path)")
  }

  func testMatchesGolden() throws {
    let data = try Data(contentsOf: Self.goldenURL)
    let golden = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: [Int]])
    XCTAssertFalse(golden.isEmpty)
    for (name, expected) in golden {
      XCTAssertEqual(Self.tessellate(name), expected, "triangulation changed for \(name)")
    }
  }
}
