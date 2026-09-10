#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif
import Foundation
import SwiftEarcut

func now() -> Double {
  var ts = timespec()
  clock_gettime(CLOCK_MONOTONIC, &ts)
  return Double(ts.tv_sec) + Double(ts.tv_nsec) * 1e-9
}

struct Fixture {
  let name: String
  let vertices: [Double]
  let holes: [Int]
  let dimensions: Int
}

func fixtureDirectory() -> URL {
  if let arg = CommandLine.arguments.dropFirst().first(where: { !$0.hasPrefix("-") }) {
    return URL(fileURLWithPath: arg)
  }
  return URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .appendingPathComponent("Tests/SwiftEarcutTests/fixtures")
}

func loadFixtures(_ directory: URL) -> [Fixture] {
  let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
  return names.filter { $0.hasSuffix(".json") && $0 != "expected.json" && !$0.hasPrefix("golden") }
    .sorted()
    .compactMap { name -> Fixture? in
      guard
        let data = try? Data(contentsOf: directory.appendingPathComponent(name)),
        let rings = try? JSONDecoder().decode([[[Double]]].self, from: data),
        let first = rings.first?.first, !first.isEmpty
      else { return nil }
      let flat = Earcut.flatten(rings)
      return Fixture(name: String(name.dropLast(5)), vertices: flat.vertices, holes: flat.holes, dimensions: flat.dimensions)
    }
}

func measure(_ fixture: Fixture, budget: Double, reuse: Bool) -> (opsPerSec: Double, triangles: Int) {
  let tessellator = Tessellator(reservingVertices: fixture.vertices.count / fixture.dimensions)
  var output = [UInt32]()

  @inline(__always)
  func once() {
    if reuse {
      tessellator.tessellate(
        fixture.vertices, holeIndices: fixture.holes, dim: fixture.dimensions, into: &output)
    } else {
      output = Earcut.tessellate(fixture.vertices, holeIndices: fixture.holes, dim: fixture.dimensions)
    }
  }

  for _ in 0..<3 { once() }
  let triangles = output.count / 3

  var ops = 0
  let start = now()
  var elapsed = 0.0
  repeat {
    once()
    ops += 1
    elapsed = now() - start
  } while elapsed < budget
  return (Double(ops) / elapsed, triangles)
}

let quick = CommandLine.arguments.contains("--quick")
let reuse = CommandLine.arguments.contains("--reuse")
let budget = quick ? 0.06 : 0.3
let fixtures = loadFixtures(fixtureDirectory())

guard !fixtures.isEmpty else {
  FileHandle.standardError.write(Data("no fixtures found at \(fixtureDirectory().path)\n".utf8))
  exit(1)
}

func pad(_ s: String, _ width: Int) -> String {
  s.count >= width ? s : s + String(repeating: " ", count: width - s.count)
}

func padLeft(_ s: String, _ width: Int) -> String {
  s.count >= width ? s : String(repeating: " ", count: width - s.count) + s
}

print(reuse ? "reusing a Tessellator" : "fresh Earcut.tessellate per call")
print(pad("fixture", 24) + padLeft("verts", 8) + padLeft("tris", 8) + padLeft("ops/sec", 14) + padLeft("us/op", 12))
print(String(repeating: "-", count: 66))

var totalMicros = 0.0
for fixture in fixtures {
  let (ops, triangles) = measure(fixture, budget: budget, reuse: reuse)
  let micros = 1_000_000 / ops
  totalMicros += micros
  print(pad(fixture.name, 24)
    + padLeft("\(fixture.vertices.count / fixture.dimensions)", 8)
    + padLeft("\(triangles)", 8)
    + padLeft(String(format: "%.1f", ops), 14)
    + padLeft(String(format: "%.2f", micros), 12))
}

print(String(repeating: "-", count: 66))
print(pad("TOTAL", 24) + padLeft(String(format: "%.2f us", totalMicros), 30) + "  across \(fixtures.count) fixtures")

if CommandLine.arguments.contains("--refine") {
  print("\n" + pad("fixture", 24) + padLeft("perimeter drop", 16) + padLeft("refine us", 12))
  print(String(repeating: "-", count: 52))
  func perimeter(_ t: [UInt32], _ c: [Double], _ dim: Int) -> Double {
    var total = 0.0
    for i in stride(from: 0, to: t.count, by: 3) {
      for k in 0..<3 {
        let p = Int(t[i + k]) * dim, q = Int(t[i + (k + 1) % 3]) * dim
        total += ((c[p]-c[q])*(c[p]-c[q]) + (c[p+1]-c[q+1])*(c[p+1]-c[q+1])).squareRoot()
      }
    }
    return total
  }
  for f in fixtures where f.vertices.count / f.dimensions > 200 {
    let base = Earcut.tessellate(f.vertices, holeIndices: f.holes, dim: f.dimensions)
    guard !base.isEmpty else { continue }
    var refined = base
    Earcut.refine(&refined, coords: f.vertices, dim: f.dimensions)
    var ops = 0
    let start = now()
    var elapsed = 0.0
    repeat {
      var t = base
      Earcut.refine(&t, coords: f.vertices, dim: f.dimensions)
      ops += 1
      elapsed = now() - start
    } while elapsed < 0.2
    let drop = 1 - perimeter(refined, f.vertices, f.dimensions) / perimeter(base, f.vertices, f.dimensions)
    print(pad(f.name, 24) + padLeft(String(format: "%.1f%%", drop * 100), 16)
      + padLeft(String(format: "%.2f", 1_000_000 * elapsed / Double(ops)), 12))
  }
}
