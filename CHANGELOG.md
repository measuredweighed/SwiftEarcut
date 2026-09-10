# Changelog

All notable changes to this project are documented here.
This project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.0.0]

Brings the port up to Mapbox [earcut 3.2.3](https://github.com/mapbox/earcut) from 2.2.4, and
rewrites the internals around a flat node arena.

### Breaking

- `tessellate` returns `[UInt32]` rather than `[Int]` — half the output size, and directly
  uploadable as a GPU index buffer.
- Argument labels follow upstream: the leading `data:` label is gone, `flatten` returns
  `dimensions` rather than `dim`, and `deviation` takes `triangles:` rather than `indices:`.
  Every 1.x signature remains as a deprecated shim with a rename fix-it.
- Triangle output differs from 1.x, because the underlying algorithm moved from earcut 2.2.4
  to 3.2.3. Triangulations are equally valid but not identical:
  `tessellate([10, 0, 0, 50, 60, 60, 70, 10])` now returns `[1, 0, 3, 1, 3, 2]` rather than
  `[1, 0, 3, 3, 2, 1]`.
- Requires Swift 6.0, and builds in Swift 6 language mode. Deployment targets are unchanged
  (macOS 10.15, iOS 13, tvOS 13, watchOS 6, Mac Catalyst 13).

### Added

- `refine(_:coords:dim:)`, upstream's constrained Delaunay post-pass. Legalizes every interior
  edge with Lawson flips, maximizing the minimum angle and removing most slivers. Total edge
  length falls 21–58% across the test fixtures. Accepts any manifold triangle-index array.
- `Tessellator`, which keeps its working buffers between calls so a run of triangulations
  allocates only the arrays it returns, or nothing at all when the output array is reused too.
  About 1.5x faster on polygons of 128 vertices or fewer. Not `Sendable`; use one per thread.
- A release-mode benchmark executable: `swift run -c release SwiftEarcutBench`.
- 13 upstream fixtures the port was missing, and a test harness driven by upstream's own
  `expected.json` that also runs every fixture at 0°, 90°, 180° and 270°.

### Changed

- `Node` is a 40-byte trivial struct in a flat arena addressed by `Int32`, replacing a class
  with `weak` back-pointers. Every backwards dereference in the innermost loops was a
  `swift_weakLoadStrong` call and every vertex was a separate heap allocation; neither remains.
- Hole bridging indexes the ring in blocks of 16 edges, so `findHoleBridge` skips a block at a
  time instead of walking the whole merged ring twice (upstream 3.1.0).
- The z-order sort is an insertion sort below 32 nodes and a four-pass LSD radix sort above,
  replacing a linked-list merge sort.
- The library imports nothing at all, Foundation included, so it no longer pulls Foundation in
  on Linux.
- Together these are roughly 100x faster in total across the test fixtures, 27x on a geometric
  mean, and 118x on `water-huge2` (267 ms to 2.3 ms).

## [1.0.0]

Initial release, tracking Mapbox earcut 2.2.4.

[2.0.0]: https://github.com/measuredweighed/SwiftEarcut/releases/tag/2.0.0
[1.0.0]: https://github.com/measuredweighed/SwiftEarcut/releases/tag/1.0.0