struct RefineScratch {
  private(set) var edgeStack: UnsafeMutablePointer<Int32>
  private(set) var twin: UnsafeMutablePointer<Int32>
  private(set) var queued: UnsafeMutablePointer<UInt8>
  private(set) var table: UnsafeMutablePointer<Int32>
  private(set) var stamp: UnsafeMutablePointer<UInt32>
  private(set) var mask: UInt32 = 0
  private(set) var generation: UInt32 = 0
  private var edgeCapacity = 0
  private var tableCapacity = 0

  init() {
    edgeStack = .allocate(capacity: 0)
    twin = .allocate(capacity: 0)
    queued = .allocate(capacity: 0)
    table = .allocate(capacity: 0)
    stamp = .allocate(capacity: 0)
  }

  func deallocate() {
    edgeStack.deallocate()
    twin.deallocate()
    queued.deallocate()
    table.deallocate()
    stamp.deallocate()
  }

  mutating func prepare(edges n: Int) {
    if n > edgeCapacity {
      edgeStack.deallocate()
      twin.deallocate()
      queued.deallocate()
      edgeStack = .allocate(capacity: n)
      twin = .allocate(capacity: n)
      queued = .allocate(capacity: n)
      queued.update(repeating: 0, count: n)
      edgeCapacity = n
    }

    var size = 1
    while size < n * 4 { size <<= 1 }
    if size > tableCapacity {
      table.deallocate()
      stamp.deallocate()
      table = .allocate(capacity: size)
      stamp = .allocate(capacity: size)
      stamp.update(repeating: 0, count: size)
      tableCapacity = size
      generation = 0
    }
    mask = UInt32(size - 1)

    // bumping the generation is what empties the hash; on wraparound it must be cleared
    generation &+= 1
    if generation == 0 {
      stamp.update(repeating: 0, count: tableCapacity)
      generation = 1
    }
  }
}

extension Earcut {

  /// Refines a triangulation toward the constrained Delaunay triangulation, in place,
  /// by legalizing every interior edge with Lawson flips. Maximizes the minimum angle and
  /// removes most slivers, for roughly 40% on top of the triangulation itself.
  ///
  /// Accepts ``tessellate(_:holeIndices:dim:)`` output, or any manifold triangle-index array
  /// over `coords`. The predicates are non-robust, so float input is fine and the worst case
  /// is an edge left not-quite-Delaunay, never an invalid mesh.
  /// - Parameter triangles: Triangle indices, mutated in place.
  /// - Parameter coords: The flat vertex coordinates the indices refer to.
  /// - Parameter dim: Number of coordinates per vertex in `coords`.
  public static func refine(_ triangles: inout [UInt32], coords: [Double], dim: Int = 2) {
    guard triangles.count >= 6 else { return }
    var scratch = RefineScratch()
    defer { scratch.deallocate() }
    coords.withUnsafeBufferPointer { c in
      triangles.withUnsafeMutableBufferPointer { t in
        legalize(t, c, dim, &scratch)
      }
    }
  }
}

extension Tessellator {

  /// Reuses this tessellator's scratch across calls; see ``Earcut/refine(_:coords:dim:)``.
  public func refine(_ triangles: inout [UInt32], coords: [Double], dim: Int = 2) {
    guard triangles.count >= 6 else { return }
    coords.withUnsafeBufferPointer { c in
      triangles.withUnsafeMutableBufferPointer { t in
        legalize(t, c, dim, &refineScratch.pointee)
      }
    }
  }
}

func legalize(
  _ t: UnsafeMutableBufferPointer<UInt32>,
  _ coords: UnsafeBufferPointer<Double>,
  _ dim: Int,
  _ scratch: inout RefineScratch)
{
  let n = t.count
  scratch.prepare(edges: n)

  let twin = scratch.twin, stack = scratch.edgeStack, queued = scratch.queued
  let table = scratch.table, stamp = scratch.stamp
  let mask = scratch.mask, generation = scratch.generation
  twin.update(repeating: -1, count: n)

  // Pair up half-edges through an undirected-edge hash. Each pair seeds the stack as it is
  // linked, which folds the usual "push every interior edge" pass into the build.
  var top = 0
  for e in 0 ..< n {
    let a = t[e], b = t[nextHalfEdge(e)]
    let lo = a < b ? a : b
    let hi = a < b ? b : a
    var h = Int(((lo &* 0x9E37_79B1) ^ (hi &* 0x85EB_CA6B)) & mask)

    while stamp[h] == generation {
      let s = table[h]
      // -1 marks a slot whose pair is already linked
      if s != -1 {
        let sa = t[Int(s)], sb = t[nextHalfEdge(Int(s))]
        if (sa == lo && sb == hi) || (sa == hi && sb == lo) {
          twin[e] = Int32(s)
          twin[Int(s)] = Int32(e)
          table[h] = -1
          queued[Int(s)] = 1
          stack[top] = s
          top += 1
          break
        }
      }
      h = (h + 1) & Int(mask)
    }
    if stamp[h] != generation {
      table[h] = Int32(e)
      stamp[h] = generation
    }
  }

  while top > 0 {
    top -= 1
    let a = Int(stack[top])
    queued[a] = 0
    let b = Int(twin[a])
    if b == -1 { continue }

    let a0 = a - a % 3
    let b0 = b - b % 3
    let ar = a0 + (a + 2) % 3
    let al = a0 + (a + 1) % 3
    let bl = b0 + (b + 2) % 3
    let br = b0 + (b + 1) % 3
    let p0 = Int(t[ar]), pr = Int(t[a]), pl = Int(t[al]), p1 = Int(t[bl])

    let x0 = coords[p0 * dim], y0 = coords[p0 * dim + 1]
    let xr = coords[pr * dim], yr = coords[pr * dim + 1]
    let xl = coords[pl * dim], yl = coords[pl * dim + 1]
    let x1 = coords[p1 * dim], y1 = coords[p1 * dim + 1]

    // inCircle first: most interior edges are already Delaunay, which short-circuits the
    // two convexity tests. A reflex quad must not flip - it would push a triangle outside
    // the polygon - and boundary edges self-protect through twin == -1.
    guard !inCircle(x0, y0, xr, yr, xl, yl, x1, y1),
          orient(x0, y0, xr, yr, x1, y1) > 0,
          orient(x0, y0, x1, y1, xl, yl) > 0
    else { continue }

    t[a] = UInt32(p1)
    t[b] = UInt32(p0)

    let hbl = twin[bl], har = twin[ar]
    twin[a] = hbl
    if hbl != -1 { twin[Int(hbl)] = Int32(a) }
    twin[b] = har
    if har != -1 { twin[Int(har)] = Int32(b) }
    twin[ar] = Int32(bl)
    twin[bl] = Int32(ar)

    if hbl != -1, queued[a] == 0 { queued[a] = 1; stack[top] = Int32(a); top += 1 }
    if har != -1, queued[b] == 0 { queued[b] = 1; stack[top] = Int32(b); top += 1 }
    if twin[al] != -1, queued[al] == 0 { queued[al] = 1; stack[top] = Int32(al); top += 1 }
    if twin[br] != -1, queued[br] == 0 { queued[br] = 1; stack[top] = Int32(br); top += 1 }
  }
}

@inline(__always)
private func nextHalfEdge(_ e: Int) -> Int {
  e - e % 3 + (e + 1) % 3
}

@inline(__always)
func orient(
  _ ax: Double, _ ay: Double,
  _ bx: Double, _ by: Double,
  _ cx: Double, _ cy: Double)
  -> Double
{
  (bx - ax) * (cy - ay) - (by - ay) * (cx - ax)
}

/// Whether `p` lies inside or on the circumcircle of `(a, b, c)`. The sign is negated
/// against the usual predicate to suit earcut's winding.
@inline(__always)
func inCircle(
  _ ax: Double, _ ay: Double,
  _ bx: Double, _ by: Double,
  _ cx: Double, _ cy: Double,
  _ px: Double, _ py: Double)
  -> Bool
{
  let dx = ax - px, dy = ay - py
  let ex = bx - px, ey = by - py
  let fx = cx - px, fy = cy - py
  let ap = dx * dx + dy * dy
  let bp = ex * ex + ey * ey
  let cp = fx * fx + fy * fy

  // A near-cocircular quad is a legal tie, but roundoff can call both an edge and its flip
  // illegal and loop forever. The determinant's error is bounded well below 9e-16*(ap+bp+cp)^2,
  // so this margin keeps every executed flip illegal in exact arithmetic and flipping terminates.
  let s = ap + bp + cp
  return dx * (ey * cp - bp * fy) - dy * (ex * cp - bp * fx) + ap * (ex * fy - ey * fx) <= 1e-13 * s * s
}
