/// A vertex in a circular doubly linked polygon ring.
///
/// Trivial and 40 bytes with no padding, so the arena is a flat `memcpy`-relocatable
/// block: no ARC, no weak references, no per-vertex allocation. Declaration order is
/// load-bearing — Swift lays fields out as written, and moving `i` first pads to 48.
struct Node {
  var x: Double
  var y: Double
  var i: UInt32
  var z: UInt32
  var prev: Int32
  var next: Int32
  var prevZ: Int32
  var nextZ: Int32
}

/// Bump arena of `Node`s addressed by `Int32`, with `-1` for null.
///
/// Indices are stable across a reallocation; only `base` is invalidated. Functions that
/// take `inout Nodes` may mutate the arena, but only `reserve` can move it — see the
/// pointer-lifetime rules in Earcut.swift.
struct Nodes {
  var base: UnsafeMutablePointer<Node>
  var count: Int32
  var capacity: Int32

  init(minimumCapacity: Int32) {
    let capacity = Swift.max(minimumCapacity, 16)
    self.base = UnsafeMutablePointer<Node>.allocate(capacity: Int(capacity))
    self.count = 0
    self.capacity = capacity
  }

  func deallocate() {
    base.deallocate()
  }

  @inline(never)
  mutating func reserve(_ extra: Int32) {
    #if EARCUT_STRESS_ARENA
    let needed = count + extra
    let newCapacity = Swift.max(needed, 16)
    #else
    guard capacity - count < extra else { return }
    let needed = count + extra
    let newCapacity = Swift.max(capacity * 2, Swift.max(needed, 16))
    #endif
    let fresh = UnsafeMutablePointer<Node>.allocate(capacity: Int(newCapacity))
    fresh.moveInitialize(from: base, count: Int(count))
    base.deallocate()
    base = fresh
    capacity = newCapacity
  }

  @inline(__always)
  mutating func append(_ i: UInt32, _ x: Double, _ y: Double) -> Int32 {
    assert(count < capacity, "reserve() must precede append()")
    let index = count
    base[Int(index)] = Node(x: x, y: y, i: i, z: 0, prev: -1, next: -1, prevZ: -1, nextZ: -1)
    count = index + 1
    return index
  }
}
