/// Bounding boxes over runs of consecutive ring edges, so the leftward ray scan in
/// `findHoleBridge` can skip a whole run at a time instead of walking the merged ring.
///
/// Grown append-only: the outer ring seeds it, then each merged hole appends a segment.
/// Segments are independent runs rather than a tiling of the ring, because splices land
/// mid-ring. `filterPoints` only drops collinear or coincident points, so a stale box stays
/// a conservative superset of its live edges and can never cause a false skip.
struct BlockIndex {
  static let edgesPerBlock: Int32 = 16

  private var bbox: UnsafeMutablePointer<Double>
  private var head: UnsafeMutablePointer<Int32>
  private var stop: UnsafeMutablePointer<Int32>
  private(set) var count: Int32 = 0
  private var capacity: Int32 = 0

  init() {
    bbox = .allocate(capacity: 0)
    head = .allocate(capacity: 0)
    stop = .allocate(capacity: 0)
  }

  func deallocate() {
    bbox.deallocate()
    head.deallocate()
    stop.deallocate()
  }

  mutating func reset(maxNodes: Int32, holes: Int32) {
    let blocks = (maxNodes + 2 * holes + Self.edgesPerBlock - 1) / Self.edgesPerBlock + holes + 2
    if blocks > capacity {
      bbox.deallocate()
      head.deallocate()
      stop.deallocate()
      bbox = .allocate(capacity: Int(blocks) * 4)
      head = .allocate(capacity: Int(blocks))
      stop = .allocate(capacity: Int(blocks))
      capacity = blocks
    }
    count = 0
  }

  @inline(__always)
  func box(_ block: Int32) -> (minX: Double, minY: Double, maxX: Double, maxY: Double) {
    let g = Int(block) * 4
    return (bbox[g], bbox[g + 1], bbox[g + 2], bbox[g + 3])
  }

  /// Indexes the run `from ..< to`, or the whole ring when they are equal.
  mutating func indexSegment(_ n: UnsafeMutablePointer<Node>, _ from: Int32, _ to: Int32) {
    var p = from
    repeat {
      let block = count
      count += 1
      head[Int(block)] = p

      var minX = n[Int(p)].x, minY = n[Int(p)].y
      var maxX = minX, maxY = minY
      var edges: Int32 = 0
      repeat {
        let next = n[Int(p)].next
        n[Int(p)].z = UInt32(block)
        let x = n[Int(next)].x, y = n[Int(next)].y
        if x < minX { minX = x }
        if x > maxX { maxX = x }
        if y < minY { minY = y }
        if y > maxY { maxY = y }
        p = next
        edges += 1
      } while edges < Self.edgesPerBlock && p != to

      stop[Int(block)] = p
      let g = Int(block) * 4
      bbox[g] = minX
      bbox[g + 1] = minY
      bbox[g + 2] = maxX
      bbox[g + 3] = maxY
    } while p != to
  }

  /// When `filterPoints` heals an edge, the replacement can reach past the frozen box of
  /// the block that owns it, so widen that box to keep the ray prune conservative.
  @inline(__always)
  mutating func grow(_ n: UnsafeMutablePointer<Node>, head owner: Int32, tail: Int32) {
    let g = Int(n[Int(owner)].z) * 4
    let x = n[Int(tail)].x, y = n[Int(tail)].y
    if x < bbox[g] { bbox[g] = x }
    if y < bbox[g + 1] { bbox[g + 1] = y }
    if x > bbox[g + 2] { bbox[g + 2] = x }
    if y > bbox[g + 3] { bbox[g + 3] = y }
  }

  /// A block's endpoints can be removed while holes merge; advance past dead nodes so the
  /// walk neither starts nor stops on one.
  @inline(__always)
  mutating func liveHead(_ n: UnsafeMutablePointer<Node>, _ block: Int32) -> Int32 {
    var p = head[Int(block)]
    while n[Int(n[Int(p)].prev)].next != p { p = n[Int(p)].next }
    head[Int(block)] = p
    return p
  }

  @inline(__always)
  mutating func liveStop(_ n: UnsafeMutablePointer<Node>, _ block: Int32) -> Int32 {
    var p = stop[Int(block)]
    while n[Int(n[Int(p)].prev)].next != p { p = n[Int(p)].next }
    stop[Int(block)] = p
    return p
  }
}
