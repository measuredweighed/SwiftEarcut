import XCTest
@testable import SwiftEarcut

/// Writes every fixture's triangle indices to the path in EARCUT_DUMP, for diffing against
/// upstream earcut's own output when syncing to a new release.
final class DumpTests: XCTestCase {
  func testDumpIndices() throws {
    try XCTSkipIf(ProcessInfo.processInfo.environment["EARCUT_DUMP"] == nil)
    let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("fixtures")
    var out = [String: [UInt32]]()
    for file in try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted() where file.hasSuffix(".json") {
      let name = String(file.dropLast(5))
      let data = try Data(contentsOf: dir.appendingPathComponent(file))
      guard let rings = try? JSONDecoder().decode([[[Double]]].self, from: data),
            let f = rings.first?.first, !f.isEmpty else { continue }
      out[name] = (0 ... 3).flatMap { quarter -> [UInt32] in
        let flat = Earcut.flatten(FixtureTests.rotated(rings, quarter))
        return Earcut.tessellate(flat.vertices, holeIndices: flat.holes, dim: flat.dimensions)
      }
    }
    try JSONSerialization.data(withJSONObject: out, options: [.sortedKeys])
      .write(to: URL(fileURLWithPath: ProcessInfo.processInfo.environment["EARCUT_DUMP"]!))
  }
}
