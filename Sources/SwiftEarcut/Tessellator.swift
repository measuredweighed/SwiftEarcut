/// Triangulates polygons while holding on to its working buffers, so a run of calls
/// allocates only the arrays it returns. Worth reaching for when triangulating many
/// polygons — a renderer walking a tile's worth of geometry, say.
///
/// Not `Sendable`, and deliberately so: it hands out interior pointers into buffers it
/// mutates. Use one per thread, or one per task.
public final class Tessellator {

  private let nodes: UnsafeMutablePointer<Nodes>
  private let scratch: UnsafeMutablePointer<Scratch>
  private let blocks: UnsafeMutablePointer<BlockIndex>
  private let triangles: UnsafeMutablePointer<TriangleBuffer>
  private var steiners: [Int32] = []

  public init(reservingVertices vertices: Int = 0) {
    nodes = .allocate(capacity: 1)
    scratch = .allocate(capacity: 1)
    blocks = .allocate(capacity: 1)
    triangles = .allocate(capacity: 1)
    nodes.initialize(to: Nodes(minimumCapacity: Int32(vertices)))
    scratch.initialize(to: Scratch(minimumCapacity: Int32(vertices)))
    blocks.initialize(to: BlockIndex())
    triangles.initialize(to: TriangleBuffer(minimumCapacity: 3 * vertices))
  }

  deinit {
    nodes.pointee.deallocate()
    scratch.pointee.deallocate()
    blocks.pointee.deallocate()
    triangles.pointee.deallocate()
    nodes.deallocate()
    scratch.deallocate()
    blocks.deallocate()
    triangles.deallocate()
  }

  /// Triangulates `data`, returning triplets of vertex indices.
  /// See ``Earcut/tessellate(_:holeIndices:dim:)`` for the argument shape.
  public func tessellate(_ data: [Double], holeIndices: [Int] = [], dim: Int = 2) -> [UInt32] {
    guard !data.isEmpty else { return [] }
    return data.withUnsafeBufferPointer { buffer in
      run(buffer, holeIndices, dim)
      return triangles.pointee.makeArray()
    }
  }

  /// Triangulates `data` into `output`, reusing its storage. With a `Tessellator` and an
  /// `output` array that are both reused, a steady-state run of calls allocates nothing.
  public func tessellate(
    _ data: [Double],
    holeIndices: [Int] = [],
    dim: Int = 2,
    into output: inout [UInt32])
  {
    guard !data.isEmpty else {
      output.removeAll(keepingCapacity: true)
      return
    }
    data.withUnsafeBufferPointer { run($0, holeIndices, dim) }
    triangles.pointee.write(into: &output)
  }

  private func run(_ data: UnsafeBufferPointer<Double>, _ holeIndices: [Int], _ dim: Int) {
    nodes.pointee.removeAll()
    triangles.pointee.removeAll()
    steiners.removeAll(keepingCapacity: true)
    nodes.pointee.reserve(Int32(data.count / dim + 2 * holeIndices.count + 8))

    earcut(data, holeIndices, dim, &nodes.pointee, &scratch.pointee, blocks,
           &triangles.pointee, &steiners)
  }
}
