// Copyright © 2018 measuredweighed. All rights reserved.
// Use of this source code is governed by MIT and ISC licenses (mapbox).
// The LICENSE files are distributed with this software package.
//
// A Swift Earcut port of Mapbox's earcut.js
// https://github.com/mapbox/earcut

import Foundation

// Pointer lifetime: functions taking `inout Nodes` may mutate the arena, and those that
// call `reserve` may move it. Everything else takes a bare `UnsafeMutablePointer<Node>`
// and so cannot reallocate by construction. A pointer bound from `nodes.base` is dead
// after any `reserve`; the two places that matters are marked inline.

public enum Earcut {

  /// Returns the indices of the points shaping the triangles.
  /// - Parameter data: Vertices is a flat array of vertex coordinates like [x0,y0, x1,y1, x2,y2, ...].
  /// - Parameter holeIndices: if any (e.g. [5, 8] for a 12-vertex input would mean one hole with vertices 5–7 and another with 8–11).
  /// - Parameter dim: Number of coordinates per vertex in the input array (2 by default). Only two are used for triangulation (x and y), and the rest are ignored.
  /// - Returns: Array of point indices, where each group of three vertex indices forms a triangle.
  /// - Warning: Earcut is a 2D triangulation algorithm, and **handles 3D data as if it was projected onto the XY plane** (with Z component ignored).
  /// # Note #
  /// Whether the outer ring or the holes are closed (identical first and last corner point) does not have to be considered (see example).
  /// # Example #
  /// ```swift
  /// Earcut.tessellate([
  ///       0.0,0.0,0.0, 9.0,0.0,0.0, 6.0,8.0,0.0, 5.0,3.0,0.0, 2.0,8.0,0.0, 0.0,8.0,0.0,
  ///       6.0,2.0,0.0, 7.0,1.0,0.0, 7.0,3.0,0.0, 6.0,3.0,0.0, 5.0,2.0,0.0, 6.0,2.0,0.0,
  ///   ],
  ///   holeIndices: [6],
  ///   dim: 3
  /// )
  /// ```
  public static func tessellate(_ data: [Double], holeIndices: [Int] = [], dim: Int = 2) -> [UInt32] {
    var triangles = [UInt32]()
    guard data.count > 0 else { return triangles }

    let hasHoles = holeIndices.count > 0
    let outerLen = hasHoles ? holeIndices[0] * dim : data.count

    var nodes = Nodes(minimumCapacity: Int32(data.count / dim + 2 * holeIndices.count + 8))
    defer { nodes.deallocate() }
    var scratch = Scratch()
    defer { scratch.deallocate() }
    let blocks = UnsafeMutablePointer<BlockIndex>.allocate(capacity: 1)
    blocks.initialize(to: BlockIndex())
    defer { blocks.pointee.deallocate(); blocks.deallocate() }
    var steiners = [Int32]()

    var outerNode = linkedList(&nodes, data, 0, outerLen, dim, true)
    guard outerNode >= 0 else { return triangles }
    guard nodes.base[Int(outerNode)].next != nodes.base[Int(outerNode)].prev else { return triangles }

    var minX: Double = 0, maxX: Double = 0, minY: Double = 0, maxY: Double = 0
    var invSize: Double = 0

    if hasHoles {
      outerNode = eliminateHoles(&nodes, data, holeIndices, outerNode, dim, &steiners, blocks)
    }

    // if the shape is not too simple, we'll use z-order curve hash later; calculate polygon bbox
    if data.count > 80 * dim {
      minX = data[0]
      maxX = minX
      minY = data[1]
      maxY = minY

      for i in stride(from: dim, to: outerLen, by: dim) {
        let x = data[i]
        let y = data[i + 1]
        if x < minX { minX = x }
        if y < minY { minY = y }
        if x > maxX { maxX = x }
        if y > maxY { maxY = y }
      }

      invSize = max(maxX - minX, maxY - minY)
      invSize = invSize != 0 ? 32767 / invSize : 0
    }

    earcutLinked(&nodes, outerNode, &triangles, minX, minY, invSize, steiners, &scratch)

    return triangles
  }

  /// Converts a multi-dimensional array of vertices (e.g. GeoJSON Polygon) to the format expected by the ``tessellate(_:holeIndices:dim:)`` method. Returns (1) flattened array of Doubles with the vertices coordinate components, (2) indices of potential holes in the polygon, and  (3) the coordinate's dimension.
  /// - Parameter data:Multi-dimensional array with vertices, like [[exterior],[hole0],[hole1]] and [[[x0,y0,z0],[x1,y1,z1],[x2,y2,z2]],[[x3,y3,z3],[x4,y4,z4],[x5,y5,z5]], ...]
  /// - Returns: `vertices`: Array of double values containing the coordinate components of all vertices. `holes`: Indices of the polygon's holes, if any. `dim`: Number of coordinates per vertex.
  public static func flatten(_ data: [[[Double]]]) -> (vertices: [Double], holes: [Int], dimensions: Int) {
    let dim = data[0][0].count

    var holeIndex = 0
    var result: (vertices: [Double], holes: [Int], dimensions: Int) = ([Double](), [Int](), dim)
    for i in 0 ..< data.count {
      for j in 0 ..< data[i].count {
        for d in 0 ..< dim {
          result.vertices.append(data[i][j][d])
        }
      }
      if i > 0 {
        holeIndex += data[i - 1].count
        result.holes.append(holeIndex)
      }
    }

    return result
  }

  /// Returns the relative difference between the total area of triangles and the area of the input polygon, used to verify correctness of triangulation.
  /// - Parameter data: Flat array of vertex coordinates.
  /// - Parameter holeIndices: If any (e.g. [5, 8] for a 12-vertex input would mean one hole with vertices 5–7 and another with 8–11).
  /// - Parameter dim: Number of coordinates per vertex in the input array (2 by default).
  /// - Parameter triangles: Array of point indices produced by ``tessellate(_:holeIndices:dim:)``.
  /// - Returns: Percentage difference between the polygon area and its triangulation area. 0 means the triangulation is fully correct.
  public static func deviation(
    _ data: [Double],
    holeIndices: [Int] = [],
    dim: Int = 2,
    triangles: [UInt32])
    -> Double
  {
    let hasHoles = holeIndices.count > 0
    let outerLen = hasHoles ? holeIndices[0] * dim : data.count

    var polygonArea = abs(signedArea(data, 0, outerLen, dim))
    if hasHoles {
      let len = holeIndices.count
      for i in 0 ..< len {
        let start = holeIndices[i] * dim
        let end = i < len - 1 ? holeIndices[i + 1] * dim : data.count
        polygonArea -= abs(signedArea(data, start, end, dim))
      }
    }

    var trianglesArea: Double = 0
    for i in stride(from: 0, to: triangles.count, by: 3) {
      let a = Int(triangles[i]) * dim
      let b = Int(triangles[i + 1]) * dim
      let c = Int(triangles[i + 2]) * dim
      trianglesArea += abs(
        (data[a] - data[c]) * (data[b + 1] - data[a + 1]) -
          (data[a] - data[b]) * (data[c + 1] - data[a + 1]))
    }

    // with no triangles, a polygon area within shoelace roundoff of zero - which scales with
    // the squared coordinate magnitude - means the input was degenerate, not mistriangulated
    if trianglesArea == 0 {
      var maximum: Double = 0
      for i in stride(from: 0, to: data.count, by: dim) {
        maximum = max(maximum, abs(data[i]), abs(data[i + 1]))
      }
      return abs(polygonArea) <= Double(data.count) * maximum * maximum * .ulpOfOne ? 0 : 1
    }
    return abs((trianglesArea - polygonArea) / polygonArea)
  }
}

extension Earcut {

  @available(*, deprecated, renamed: "tessellate(_:holeIndices:dim:)",
             message: "Indices are now [UInt32]. Use tessellate(_:holeIndices:dim:).")
  public static func tessellate(data: [Double], holeIndices: [Int] = [], dim: Int = 2) -> [Int] {
    tessellate(data, holeIndices: holeIndices, dim: dim).map(Int.init)
  }

  @available(*, deprecated, renamed: "flatten(_:)",
             message: "The dim tuple element is now named dimensions. Use flatten(_:).")
  public static func flatten(data: [[[Double]]]) -> (vertices: [Double], holes: [Int], dim: Int) {
    let result = flatten(data)
    return (result.vertices, result.holes, result.dimensions)
  }

  @available(*, deprecated, renamed: "deviation(_:holeIndices:dim:triangles:)",
             message: "Indices are now [UInt32]. Use deviation(_:holeIndices:dim:triangles:).")
  public static func deviation(
    data: [Double],
    holeIndices: [Int] = [],
    dim: Int = 2,
    indices: [Int])
    -> Double
  {
    deviation(data, holeIndices: holeIndices, dim: dim, triangles: indices.map(UInt32.init))
  }
}

// MARK: - Ring construction

private func linkedList(
  _ nodes: inout Nodes,
  _ data: [Double],
  _ start: Int,
  _ end: Int,
  _ dim: Int,
  _ clockwise: Bool)
  -> Int32
{
  guard end > start else { return -1 }
  nodes.reserve(Int32((end - start) / dim))

  var last: Int32 = -1
  if clockwise == (signedArea(data, start, end, dim) > 0) {
    for i in stride(from: start, to: end, by: dim) {
      last = insertNode(&nodes, UInt32(i / dim), data[i], data[i + 1], last)
    }
  } else {
    for i in stride(from: end - dim, through: start, by: -dim) {
      last = insertNode(&nodes, UInt32(i / dim), data[i], data[i + 1], last)
    }
  }

  guard last >= 0 else { return -1 }
  let n = nodes.base
  if equals(n, last, n[Int(last)].next) {
    removeNode(n, last)
    return n[Int(last)].next
  }
  return last
}

@inline(__always)
private func insertNode(_ nodes: inout Nodes, _ i: UInt32, _ x: Double, _ y: Double, _ last: Int32) -> Int32 {
  let p = nodes.append(i, x, y)
  let n = nodes.base

  if last < 0 {
    n[Int(p)].prev = p
    n[Int(p)].next = p
  } else {
    let lastNext = n[Int(last)].next
    n[Int(p)].next = lastNext
    n[Int(p)].prev = last
    if lastNext >= 0 { n[Int(lastNext)].prev = p }
    n[Int(last)].next = p
  }
  return p
}

@inline(__always)
private func removeNode(
  _ n: UnsafeMutablePointer<Node>,
  _ p: Int32,
  _ blocks: UnsafeMutablePointer<BlockIndex>? = nil)
{
  let node = n[Int(p)]
  if node.next >= 0 { n[Int(node.next)].prev = node.prev }
  if node.prev >= 0 { n[Int(node.prev)].next = node.next }
  if node.prevZ >= 0 { n[Int(node.prevZ)].nextZ = node.nextZ }
  if node.nextZ >= 0 { n[Int(node.nextZ)].prevZ = node.prevZ }
  blocks?.pointee.grow(n, head: node.prev, tail: node.next)
}

private func getLeftmost(_ n: UnsafeMutablePointer<Node>, _ start: Int32) -> Int32 {
  var p = start
  var leftMost = start
  repeat {
    if n[Int(p)].x < n[Int(leftMost)].x
      || (n[Int(p)].x == n[Int(leftMost)].x && n[Int(p)].y < n[Int(leftMost)].y)
    {
      leftMost = p
    }
    p = n[Int(p)].next
  } while p != start

  return leftMost
}

@inline(__always)
private func isSteiner(_ steiners: [Int32], _ p: Int32) -> Bool {
  steiners.isEmpty ? false : steiners.contains(p)
}

/// Sweeps the whole ring to a fixpoint when `end == start`, otherwise heals only the
/// window up to `end`. Reports whether anything was removed, which drives the retry ladder.
private func filterPoints(
  _ n: UnsafeMutablePointer<Node>,
  _ start: Int32,
  _ end: Int32,
  _ steiners: [Int32],
  _ blocks: UnsafeMutablePointer<BlockIndex>? = nil)
  -> (end: Int32, removed: Bool)
{
  let full = end == start
  var end = end
  var p = start
  var again = false
  var removed = false

  repeat {
    again = false
    let next = n[Int(p)].next

    if p != next, !isSteiner(steiners, p),
       equals(n, p, next) || area(n, n[Int(p)].prev, p, next) == 0
    {
      if full || p == end { end = n[Int(p)].prev }
      removed = true
      removeNode(n, p, blocks)
      p = n[Int(p)].prev
      again = true
    } else if full || p != end {
      p = next
      again = !full
    }
  } while again || p != end

  return (end, removed)
}

// MARK: - Ear slicing

private func earcutLinked(
  _ nodes: inout Nodes,
  _ ear: Int32,
  _ triangles: inout [UInt32],
  _ minX: Double,
  _ minY: Double,
  _ invSize: Double,
  _ steiners: [Int32],
  _ scratch: inout Scratch)
{
  var ear = ear
  let n = nodes.base

  if invSize > 0 {
    scratch.reserve(nodes.count)
    indexCurve(n, ear, minX, minY, invSize, &scratch)
  }

  var stop = ear
  var cured = false

  while n[Int(ear)].prev != n[Int(ear)].next {
    let prev = n[Int(ear)].prev
    let next = n[Int(ear)].next

    if area(n, prev, ear, next) < 0,
       invSize > 0 ? isEarHashed(n, ear, minX, minY, invSize) : isEar(n, ear)
    {
      triangles.append(n[Int(prev)].i)
      triangles.append(n[Int(ear)].i)
      triangles.append(n[Int(next)].i)

      removeNode(n, ear)
      ear = next
      stop = next

      continue
    }

    ear = next

    // if we looped through the whole remaining polygon and can't find any more ears
    if ear == stop {
      let filtered = filterPoints(n, ear, ear, steiners)
      ear = filtered.end
      if filtered.removed {
        stop = ear
        continue
      }

      if !cured {
        ear = cureLocalIntersections(n, ear, &triangles, steiners)
        stop = ear
        cured = true
        continue
      }

      // `n` is dead below this point: splitEarcut reserves.
      splitEarcut(&nodes, ear, &triangles, minX, minY, invSize, steiners, &scratch)
      break
    }
  }
}

private func isEar(_ n: UnsafeMutablePointer<Node>, _ ear: Int32) -> Bool {
  let a = n[Int(ear)].prev
  let b = ear
  let c = n[Int(ear)].next

  let ax = n[Int(a)].x, bx = n[Int(b)].x, cx = n[Int(c)].x
  let ay = n[Int(a)].y, by = n[Int(b)].y, cy = n[Int(c)].y

  // triangle bbox; min & max are calculated like this for speed
  let x0 = ax < bx ? (ax < cx ? ax : cx) : (bx < cx ? bx : cx),
      y0 = ay < by ? (ay < cy ? ay : cy) : (by < cy ? by : cy),
      x1 = ax > bx ? (ax > cx ? ax : cx) : (bx > cx ? bx : cx),
      y1 = ay > by ? (ay > cy ? ay : cy) : (by > cy ? by : cy)

  var p = n[Int(c)].next
  while p != a {
    let px = n[Int(p)].x, py = n[Int(p)].y
    if px >= x0, px <= x1, py >= y0, py <= y1, !(ax == px && ay == py),
       pointInTriangle(ax, ay, bx, by, cx, cy, px, py),
       area(n, n[Int(p)].prev, p, n[Int(p)].next) >= 0 { return false }
    p = n[Int(p)].next
  }

  return true
}

private func isEarHashed(
  _ n: UnsafeMutablePointer<Node>,
  _ ear: Int32,
  _ minX: Double,
  _ minY: Double,
  _ invSize: Double)
  -> Bool
{
  let a = n[Int(ear)].prev
  let b = ear
  let c = n[Int(ear)].next

  let ax = n[Int(a)].x, bx = n[Int(b)].x, cx = n[Int(c)].x
  let ay = n[Int(a)].y, by = n[Int(b)].y, cy = n[Int(c)].y

  let x0 = ax < bx ? (ax < cx ? ax : cx) : (bx < cx ? bx : cx),
      y0 = ay < by ? (ay < cy ? ay : cy) : (by < cy ? by : cy),
      x1 = ax > bx ? (ax > cx ? ax : cx) : (bx > cx ? bx : cx),
      y1 = ay > by ? (ay > cy ? ay : cy) : (by > cy ? by : cy)

  let minZ = zOrder(x0, y0, minX, minY, invSize)
  let maxZ = zOrder(x1, y1, minX, minY, invSize)

  var p = n[Int(ear)].prevZ
  while p >= 0, n[Int(p)].z >= minZ {
    let px = n[Int(p)].x, py = n[Int(p)].y
    if px >= x0, px <= x1, py >= y0, py <= y1, p != c, !(ax == px && ay == py),
       pointInTriangle(ax, ay, bx, by, cx, cy, px, py),
       area(n, n[Int(p)].prev, p, n[Int(p)].next) >= 0 { return false }
    p = n[Int(p)].prevZ
  }

  var q = n[Int(ear)].nextZ
  while q >= 0, n[Int(q)].z <= maxZ {
    let qx = n[Int(q)].x, qy = n[Int(q)].y
    if qx >= x0, qx <= x1, qy >= y0, qy <= y1, q != c, !(ax == qx && ay == qy),
       pointInTriangle(ax, ay, bx, by, cx, cy, qx, qy),
       area(n, n[Int(q)].prev, q, n[Int(q)].next) >= 0 { return false }
    q = n[Int(q)].nextZ
  }

  return true
}

@inline(never)
private func cureLocalIntersections(
  _ n: UnsafeMutablePointer<Node>,
  _ start: Int32,
  _ triangles: inout [UInt32],
  _ steiners: [Int32])
  -> Int32
{
  var start = start
  var p = start
  var cured = false
  repeat {
    let a = n[Int(p)].prev
    let b = n[Int(n[Int(p)].next)].next

    if intersects(n, a, p, n[Int(p)].next, b, includeBoundary: false),
       locallyInside(n, a, b), locallyInside(n, b, a)
    {
      triangles.append(n[Int(a)].i)
      triangles.append(n[Int(p)].i)
      triangles.append(n[Int(b)].i)

      removeNode(n, p)
      removeNode(n, n[Int(p)].next)

      p = b
      start = b
      cured = true
    }
    p = n[Int(p)].next
  } while p != start

  return cured ? filterPoints(n, p, p, steiners).end : p
}

/// try splitting polygon into two and triangulate them independently
@inline(never)
private func splitEarcut(
  _ nodes: inout Nodes,
  _ start: Int32,
  _ triangles: inout [UInt32],
  _ minX: Double,
  _ minY: Double,
  _ invSize: Double,
  _ steiners: [Int32],
  _ scratch: inout Scratch)
{
  nodes.reserve(2)
  let n = nodes.base

  var a = start
  repeat {
    var b = n[Int(n[Int(a)].next)].next
    while b != n[Int(a)].prev {
      if n[Int(a)].i != n[Int(b)].i, isValidDiagonal(n, a, b) {
        var c = splitPolygon(&nodes, a, b)

        a = filterPoints(n, a, n[Int(a)].next, steiners).end
        c = filterPoints(n, c, n[Int(c)].next, steiners).end

        // `n` is dead below this point: earcutLinked may reserve.
        earcutLinked(&nodes, a, &triangles, minX, minY, invSize, steiners, &scratch)
        earcutLinked(&nodes, c, &triangles, minX, minY, invSize, steiners, &scratch)
        return
      }
      b = n[Int(b)].next
    }
    a = n[Int(a)].next
  } while a != start
}

// MARK: - Holes

private struct HoleKey: Comparable {
  let node: Int32
  let x: Double
  let y: Double
  let slope: Double
  let order: Int32

  init(_ n: UnsafeMutablePointer<Node>, _ node: Int32, _ order: Int32) {
    let next = n[Int(node)].next
    let x = n[Int(node)].x
    let y = n[Int(node)].y
    let slope = (n[Int(next)].y - y) / (n[Int(next)].x - x)
    self.node = node
    self.x = x
    self.y = y
    self.slope = slope.isNaN ? 0 : slope
    self.order = order
  }

  static func < (a: HoleKey, b: HoleKey) -> Bool {
    if a.x != b.x { return a.x < b.x }
    if a.y != b.y { return a.y < b.y }
    if a.slope != b.slope { return a.slope < b.slope }
    return a.order < b.order
  }
}

private func eliminateHoles(
  _ nodes: inout Nodes,
  _ data: [Double],
  _ holeIndices: [Int],
  _ outerNode: Int32,
  _ dim: Int,
  _ steiners: inout [Int32],
  _ blocks: UnsafeMutablePointer<BlockIndex>)
  -> Int32
{
  var outerNode = outerNode
  var queue = [HoleKey]()
  let len = holeIndices.count

  for i in 0 ..< len {
    let start = holeIndices[i] * dim
    let end = i < len - 1 ? holeIndices[i + 1] * dim : data.count
    let list = linkedList(&nodes, data, start, end, dim, false)
    guard list >= 0 else { continue }

    let n = nodes.base
    if list == n[Int(list)].next { steiners.append(list) }
    queue.append(HoleKey(n, getLeftmost(n, list), Int32(queue.count)))
  }

  queue.sort()

  blocks.pointee.reset(maxNodes: Int32(data.count / dim), holes: Int32(len))
  blocks.pointee.indexSegment(nodes.base, outerNode, outerNode)

  for key in queue {
    outerNode = eliminateHole(&nodes, key.node, outerNode, steiners, blocks)
  }

  return filterPoints(nodes.base, outerNode, outerNode, steiners).end
}

private func eliminateHole(
  _ nodes: inout Nodes,
  _ hole: Int32,
  _ outerNode: Int32,
  _ steiners: [Int32],
  _ blocks: UnsafeMutablePointer<BlockIndex>)
  -> Int32
{
  let bridge = findHoleBridge(nodes.base, hole, outerNode, blocks)
  guard bridge >= 0 else { return outerNode }

  nodes.reserve(2)
  let bridgeReverse = splitPolygon(&nodes, bridge, hole)
  let n = nodes.base

  // in ring order the splice runs bridge -> hole -> bridgeReverse -> bridge2 -> bridge's
  // old next, so this covers the hole's edges and both new slit edges
  let bridge2 = n[Int(bridgeReverse)].next
  blocks.pointee.indexSegment(n, bridge, n[Int(bridge2)].next)

  _ = filterPoints(n, bridgeReverse, n[Int(bridgeReverse)].next, steiners, blocks)
  return filterPoints(n, bridge, n[Int(bridge)].next, steiners, blocks).end
}

/// David Eberly's algorithm for finding a bridge between hole and outer polygon
private func findHoleBridge(
  _ n: UnsafeMutablePointer<Node>,
  _ hole: Int32,
  _ outerNode: Int32,
  _ blocks: UnsafeMutablePointer<BlockIndex>)
  -> Int32
{
  let hx = n[Int(hole)].x
  let hy = n[Int(hole)].y
  var qx = -Double.infinity
  var m: Int32 = -1

  if equals(n, hole, outerNode) { return outerNode }

  // find a segment intersected by a ray from the hole's leftmost point to the left;
  // segment's endpoint with lesser x will be potential connection point
  for block in 0 ..< blocks.pointee.count {
    let bounds = blocks.pointee.box(block)
    if hy < bounds.minY || hy > bounds.maxY || bounds.minX > hx || bounds.maxX <= qx { continue }

    let stop = blocks.pointee.liveStop(n, block)
    var p = blocks.pointee.liveHead(n, block)
    repeat {
      if n[Int(n[Int(p)].prev)].next == p {
        let next = n[Int(p)].next
        if equals(n, hole, next) { return next }
        if hy <= n[Int(p)].y, hy >= n[Int(next)].y, n[Int(next)].y != n[Int(p)].y {
          let x = n[Int(p)].x
            + (hy - n[Int(p)].y) * (n[Int(next)].x - n[Int(p)].x) / (n[Int(next)].y - n[Int(p)].y)
          if x <= hx, x > qx {
            qx = x
            m = n[Int(p)].x < n[Int(next)].x ? p : next

            // hole touches outer segment; pick leftmost endpoint
            if x == hx { return m }
          }
        }
      }
      p = n[Int(p)].next
    } while p != stop
  }

  guard m >= 0 else { return -1 }

  // look for points inside the triangle of hole point, segment intersection and endpoint;
  // if there are no points found, we have a valid connection;
  // otherwise choose the point of the minimum angle with the ray as connection point
  let mx = n[Int(m)].x
  let my = n[Int(m)].y
  let minY = min(hy, my)
  let maxY = max(hy, my)
  var tanMin = Double.infinity

  for block in 0 ..< blocks.pointee.count {
    let bounds = blocks.pointee.box(block)
    if bounds.maxX < mx || bounds.minX > hx || bounds.maxY < minY || bounds.minY > maxY { continue }

    let stop = blocks.pointee.liveStop(n, block)
    var p = blocks.pointee.liveHead(n, block)
    repeat {
      let px = n[Int(p)].x, py = n[Int(p)].y
      if n[Int(n[Int(p)].prev)].next == p, hx >= px, px >= mx, hx != px,
         pointInTriangle(hy < my ? hx : qx, hy, mx, my, hy < my ? qx : hx, hy, px, py)
      {
        let tan = abs(hy - py) / (hx - px)
        let next = n[Int(p)].next

        // a hole point sitting on p's horizontal edge is a valid T-junction bridge even
        // though locallyInside rejects it as collinear
        if locallyInside(n, p, hole) || (py == hy && n[Int(next)].y == hy && n[Int(next)].x > hx),
           tan < tanMin
             || (tan == tanMin && (px > n[Int(m)].x
                   || (px == n[Int(m)].x && sectorContainsSector(n, m, p))))
        {
          m = p
          tanMin = tan
        }
      }
      p = n[Int(p)].next
    } while p != stop
  }

  return m
}

private func sectorContainsSector(_ n: UnsafeMutablePointer<Node>, _ m: Int32, _ p: Int32) -> Bool {
  area(n, n[Int(m)].prev, m, n[Int(p)].prev) < 0 && area(n, n[Int(p)].next, m, n[Int(m)].next) < 0
}

// MARK: - Z-order hashing

private func indexCurve(
  _ n: UnsafeMutablePointer<Node>,
  _ start: Int32,
  _ minX: Double,
  _ minY: Double,
  _ invSize: Double,
  _ scratch: inout Scratch)
{
  let order = scratch.order
  var p = start
  var count: Int32 = 0
  repeat {
    // z may still hold a block index left over from hole elimination
    n[Int(p)].z = zOrder(n[Int(p)].x, n[Int(p)].y, minX, minY, invSize)
    order[Int(count)] = p
    count += 1
    p = n[Int(p)].next
  } while p != start

  sortNodes(n, count, &scratch)

  let sorted = scratch.order
  var prev: Int32 = -1
  for k in 0 ..< Int(count) {
    let node = sorted[k]
    n[Int(node)].prevZ = prev
    if prev >= 0 { n[Int(prev)].nextZ = node }
    prev = node
  }
  if prev >= 0 { n[Int(prev)].nextZ = -1 }
}

/// Insertion sort below the point where building a histogram pays for itself,
/// otherwise a four-pass LSD radix sort over z's 30 bits.
private func sortNodes(_ n: UnsafeMutablePointer<Node>, _ count: Int32, _ scratch: inout Scratch) {
  let order = scratch.order

  if count <= 32 {
    for i in 1 ..< Int(count) {
      let node = order[i]
      let z = n[Int(node)].z
      var j = i - 1
      while j >= 0, n[Int(order[j])].z > z {
        order[j + 1] = order[j]
        j -= 1
      }
      order[j + 1] = node
    }
    return
  }

  let zValues = scratch.zValues, zBuffer = scratch.zBuffer
  let buffer = scratch.orderBuffer, counts = scratch.counts
  for i in 0 ..< Int(count) { zValues[i] = n[Int(order[i])].z }

  radixPass(count, order, zValues, buffer, zBuffer, 0, counts)
  radixPass(count, buffer, zBuffer, order, zValues, 8, counts)
  radixPass(count, order, zValues, buffer, zBuffer, 16, counts)
  radixPass(count, buffer, zBuffer, order, zValues, 24, counts)
}

@inline(never)
private func radixPass(
  _ count: Int32,
  _ source: UnsafeMutablePointer<Int32>,
  _ sourceZ: UnsafeMutablePointer<UInt32>,
  _ destination: UnsafeMutablePointer<Int32>,
  _ destinationZ: UnsafeMutablePointer<UInt32>,
  _ shift: UInt32,
  _ counts: UnsafeMutablePointer<UInt32>)
{
  counts.update(repeating: 0, count: 256)
  for i in 0 ..< Int(count) { counts[Int((sourceZ[i] >> shift) & 0xFF)] += 1 }

  var sum: UInt32 = 0
  for bucket in 0 ..< 256 {
    let c = counts[bucket]
    counts[bucket] = sum
    sum += c
  }

  for i in 0 ..< Int(count) {
    let z = sourceZ[i]
    let bucket = Int((z >> shift) & 0xFF)
    let position = Int(counts[bucket])
    counts[bucket] = UInt32(position + 1)
    destination[position] = source[i]
    destinationZ[position] = z
  }
}

/// The bbox is measured over the outer ring only, so merged hole vertices can fall outside it.
/// Clamping is monotone per axis, preserving the containment `z(x0,y0) <= z(p) <= z(x1,y1)`
/// that `isEarHashed` prunes on; the unclamped conversion traps.
@inline(__always)
private func zClamp(_ v: Double) -> UInt32 {
  v > 0 ? (v < 32767 ? UInt32(v) : 32767) : 0
}

@inline(__always)
private func zOrder(_ x: Double, _ y: Double, _ minX: Double, _ minY: Double, _ invSize: Double) -> UInt32 {
  var x = zClamp((x - minX) * invSize)
  var y = zClamp((y - minY) * invSize)

  x = (x | (x << 8)) & 0x00FF00FF
  x = (x | (x << 4)) & 0x0F0F0F0F
  x = (x | (x << 2)) & 0x33333333
  x = (x | (x << 1)) & 0x55555555

  y = (y | (y << 8)) & 0x00FF00FF
  y = (y | (y << 4)) & 0x0F0F0F0F
  y = (y | (y << 2)) & 0x33333333
  y = (y | (y << 1)) & 0x55555555

  return x | (y << 1)
}

// MARK: - Geometry

@inline(__always)
private func pointInTriangle(
  _ ax: Double, _ ay: Double,
  _ bx: Double, _ by: Double,
  _ cx: Double, _ cy: Double,
  _ px: Double, _ py: Double)
  -> Bool
{
  (cx - px) * (ay - py) >= (ax - px) * (cy - py) &&
    (ax - px) * (by - py) >= (bx - px) * (ay - py) &&
    (bx - px) * (cy - py) >= (cx - px) * (by - py)
}

private func isValidDiagonal(_ n: UnsafeMutablePointer<Node>, _ a: Int32, _ b: Int32) -> Bool {
  let zeroLength = equals(n, a, b)
    && area(n, n[Int(a)].prev, a, n[Int(a)].next) > 0
    && area(n, n[Int(b)].prev, b, n[Int(b)].next) > 0

  return n[Int(n[Int(a)].next)].i != n[Int(b)].i
    && (zeroLength
      || (locallyInside(n, a, b) && locallyInside(n, b, a)
        && (area(n, n[Int(a)].prev, a, n[Int(b)].prev) != 0 || area(n, a, n[Int(b)].prev, b) != 0)))
    && !intersectsPolygon(n, a, b)
    && (zeroLength || middleInside(n, a, b))
}

@inline(__always)
private func area(_ n: UnsafeMutablePointer<Node>, _ p: Int32, _ q: Int32, _ r: Int32) -> Double {
  (n[Int(q)].y - n[Int(p)].y) * (n[Int(r)].x - n[Int(q)].x)
    - (n[Int(q)].x - n[Int(p)].x) * (n[Int(r)].y - n[Int(q)].y)
}

@inline(__always)
private func equals(_ n: UnsafeMutablePointer<Node>, _ p: Int32, _ q: Int32) -> Bool {
  n[Int(p)].x == n[Int(q)].x && n[Int(p)].y == n[Int(q)].y
}

private func intersects(
  _ n: UnsafeMutablePointer<Node>,
  _ p1: Int32, _ q1: Int32,
  _ p2: Int32, _ q2: Int32,
  includeBoundary: Bool = true)
  -> Bool
{
  let o1 = area(n, p1, q1, p2)
  let o2 = area(n, p1, q1, q2)
  let o3 = area(n, p2, q2, p1)
  let o4 = area(n, p2, q2, q1)

  if ((o1 > 0 && o2 < 0) || (o1 < 0 && o2 > 0)) && ((o3 > 0 && o4 < 0) || (o3 < 0 && o4 > 0)) {
    return true
  }

  guard includeBoundary else { return false }

  if o1 == 0, onSegment(n, p1, p2, q1) { return true }
  if o2 == 0, onSegment(n, p1, q2, q1) { return true }
  if o3 == 0, onSegment(n, p2, p1, q2) { return true }
  if o4 == 0, onSegment(n, p2, q1, q2) { return true }

  return false
}

/// for collinear points p, q, r, check if point q lies on segment pr
@inline(__always)
private func onSegment(_ n: UnsafeMutablePointer<Node>, _ p: Int32, _ q: Int32, _ r: Int32) -> Bool {
  n[Int(q)].x <= max(n[Int(p)].x, n[Int(r)].x) && n[Int(q)].x >= min(n[Int(p)].x, n[Int(r)].x)
    && n[Int(q)].y <= max(n[Int(p)].y, n[Int(r)].y) && n[Int(q)].y >= min(n[Int(p)].y, n[Int(r)].y)
}

private func intersectsPolygon(_ n: UnsafeMutablePointer<Node>, _ a: Int32, _ b: Int32) -> Bool {
  let ax = n[Int(a)].x, ay = n[Int(a)].y, bx = n[Int(b)].x, by = n[Int(b)].y
  let minX = min(ax, bx), maxX = max(ax, bx)
  let minY = min(ay, by), maxY = max(ay, by)

  var p = a
  repeat {
    let next = n[Int(p)].next
    let px = n[Int(p)].x, py = n[Int(p)].y
    let nx = n[Int(next)].x, ny = n[Int(next)].y

    if (px > maxX && nx > maxX) || (px < minX && nx < minX)
      || (py > maxY && ny > maxY) || (py < minY && ny < minY)
    {
      p = next
      continue
    }

    if n[Int(p)].i != n[Int(a)].i, n[Int(next)].i != n[Int(a)].i,
       n[Int(p)].i != n[Int(b)].i, n[Int(next)].i != n[Int(b)].i,
       intersects(n, p, next, a, b)
    {
      return true
    }
    p = next
  } while p != a

  return false
}

/// check if a polygon diagonal is locally inside the polygon
@inline(__always)
private func locallyInside(_ n: UnsafeMutablePointer<Node>, _ a: Int32, _ b: Int32) -> Bool {
  area(n, n[Int(a)].prev, a, n[Int(a)].next) < 0
    ? area(n, a, b, n[Int(a)].next) >= 0 && area(n, a, n[Int(a)].prev, b) >= 0
    : area(n, a, b, n[Int(a)].prev) < 0 || area(n, a, n[Int(a)].next, b) < 0
}

/// check if the middle point of a polygon diagonal is inside the polygon
private func middleInside(_ n: UnsafeMutablePointer<Node>, _ a: Int32, _ b: Int32) -> Bool {
  var p = a
  var inside = false
  let px = (n[Int(a)].x + n[Int(b)].x) / 2
  let py = (n[Int(a)].y + n[Int(b)].y) / 2
  repeat {
    let next = n[Int(p)].next
    if (n[Int(p)].y > py) != (n[Int(next)].y > py), n[Int(next)].y != n[Int(p)].y,
       px < (n[Int(next)].x - n[Int(p)].x) * (py - n[Int(p)].y) / (n[Int(next)].y - n[Int(p)].y) + n[Int(p)].x
    {
      inside = !inside
    }

    p = next
  } while p != a
  return inside
}

/// link two polygon vertices with a bridge; if the vertices belong to the same ring, it splits polygon into two;
/// if one belongs to the outer ring and another to a hole, it merges it into a single ring
private func splitPolygon(_ nodes: inout Nodes, _ a: Int32, _ b: Int32) -> Int32 {
  precondition(nodes.capacity - nodes.count >= 2, "splitPolygon must not reallocate")
  let av = nodes.base[Int(a)]
  let bv = nodes.base[Int(b)]
  let a2 = nodes.append(av.i, av.x, av.y)
  let b2 = nodes.append(bv.i, bv.x, bv.y)

  let n = nodes.base
  let an = n[Int(a)].next
  let bp = n[Int(b)].prev

  n[Int(a)].next = b
  n[Int(b)].prev = a

  n[Int(a2)].next = an
  if an >= 0 { n[Int(an)].prev = a2 }

  n[Int(b2)].next = a2
  n[Int(a2)].prev = b2

  if bp >= 0 { n[Int(bp)].next = b2 }
  n[Int(b2)].prev = bp

  return b2
}

private func signedArea(_ data: [Double], _ start: Int, _ end: Int, _ dim: Int) -> Double {
  var sum: Double = 0
  var j = end - dim
  for i in stride(from: start, to: end, by: dim) {
    sum += (data[j] - data[i]) * (data[i + 1] + data[j + 1])
    j = i
  }
  return sum
}
