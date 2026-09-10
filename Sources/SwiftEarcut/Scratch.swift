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
