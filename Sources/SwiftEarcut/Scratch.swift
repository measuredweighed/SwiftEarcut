/// Working buffers for the z-order sort, sized once per triangulation and reused
/// across the ring re-indexing that every `earcutLinked` performs.
struct Scratch {
  var order: UnsafeMutablePointer<Int32>
  var orderBuffer: UnsafeMutablePointer<Int32>
  var zValues: UnsafeMutablePointer<UInt32>
  var zBuffer: UnsafeMutablePointer<UInt32>
  var counts: UnsafeMutablePointer<UInt32>
  var capacity: Int32

  init(minimumCapacity: Int32 = 0) {
    let capacity = Swift.max(minimumCapacity, 64)
    self.order = .allocate(capacity: Int(capacity))
    self.orderBuffer = .allocate(capacity: Int(capacity))
    self.zValues = .allocate(capacity: Int(capacity))
    self.zBuffer = .allocate(capacity: Int(capacity))
    self.counts = .allocate(capacity: 256)
    self.capacity = capacity
  }

  /// Contents are rewritten on every use, so growth discards rather than copies.
  mutating func reserve(_ n: Int32) {
    guard n > capacity else { return }
    let capacity = Swift.max(n, self.capacity * 2)
    order.deallocate()
    orderBuffer.deallocate()
    zValues.deallocate()
    zBuffer.deallocate()
    order = .allocate(capacity: Int(capacity))
    orderBuffer = .allocate(capacity: Int(capacity))
    zValues = .allocate(capacity: Int(capacity))
    zBuffer = .allocate(capacity: Int(capacity))
    self.capacity = capacity
  }

  func deallocate() {
    order.deallocate()
    orderBuffer.deallocate()
    zValues.deallocate()
    zBuffer.deallocate()
    counts.deallocate()
  }
}

/// Output accumulator. Array.append would pay a uniqueness and a capacity check per index,
/// three times per triangle, none of which hoist out of the slicing loop.
struct TriangleBuffer {
  private var base: UnsafeMutablePointer<UInt32>
  private var count: Int
  private var capacity: Int

  init(minimumCapacity: Int) {
    let capacity = Swift.max(minimumCapacity, 64)
    self.base = .allocate(capacity: capacity)
    self.count = 0
    self.capacity = capacity
  }

  func deallocate() {
    base.deallocate()
  }

  @inline(__always)
  mutating func append(_ a: UInt32, _ b: UInt32, _ c: UInt32) {
    if count + 3 > capacity { grow() }
    base[count] = a
    base[count + 1] = b
    base[count + 2] = c
    count += 3
  }

  @inline(never)
  private mutating func grow() {
    let capacity = self.capacity * 2
    let fresh = UnsafeMutablePointer<UInt32>.allocate(capacity: capacity)
    fresh.moveInitialize(from: base, count: count)
    base.deallocate()
    self.base = fresh
    self.capacity = capacity
  }

  mutating func removeAll() {
    count = 0
  }

  func makeArray() -> [UInt32] {
    Array(UnsafeBufferPointer(start: base, count: count))
  }

  func write(into output: inout [UInt32]) {
    output.removeAll(keepingCapacity: true)
    output.append(contentsOf: UnsafeBufferPointer(start: base, count: count))
  }
}
