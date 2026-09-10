# SwiftEarcut
A Swift port of Mapbox's [earcut.js](https://github.com/mapbox/earcut) polygon triangulation library.

[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fmeasuredweighed%2FSwiftEarcut%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/measuredweighed/SwiftEarcut)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fmeasuredweighed%2FSwiftEarcut%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/measuredweighed/SwiftEarcut)

## Table of Contents
1. [License](#license)
2. [Installation](#installation)
3. [Documentation](#documentation)
4. [Quick Start](#quick-start)
5. [Holes](#holes)
6. [Delaunay refinement](#delaunay-refinement)
7. [Triangulating many polygons](#triangulating-many-polygons)
8. [Upgrading from 1.x](#upgrading-from-1x)

Release notes are in [CHANGELOG.md](CHANGELOG.md).

## License
Mapbox's [earcut.js](https://github.com/mapbox/earcut) is governed by an [ISC license](https://github.com/mapbox/earcut/blob/main/LICENSE) while this Swift port is governed by an [MIT license](https://github.com/measuredweighed/SwiftEarcut/blob/master/LICENSE).

## Installation

### Swift Package Manager
Add the following dependency
```swift
.package(url: "https://github.com/measuredweighed/SwiftEarcut.git", from: "2.0.0"),
```

## Documentation
Comprehensive documentation for SwiftEarcut can be found on the [Swift Package Index](https://swiftpackageindex.com/measuredweighed/SwiftEarcut/) (click on `Documentation`).

## Quick Start
Pass Earcut a flat array of vertex coordinates, and `tessellate` returns a flat array of triangle indices (three per triangle).

```swift
let result = Earcut.tessellate([10, 0, 0, 50, 60, 60, 70, 10])

// result: [1, 0, 3, 1, 3, 2]
```

Indices are `UInt32`, so the result uploads directly as a GPU index buffer.

## Holes
Hole rings follow the outer ring in the same array, with `holeIndices` giving the vertex index each one starts at. `flatten` builds both from GeoJSON-style nested rings.

```swift
let (vertices, holes, dimensions) = Earcut.flatten(geoJSONPolygon.coordinates)
let indices = Earcut.tessellate(vertices, holeIndices: holes, dim: dimensions)
```

`dim` is the number of coordinates per vertex. Earcut is a 2D algorithm: with `dim: 3` it triangulates the XY projection and ignores Z.

A single-vertex hole is treated as a Steiner point.

## Delaunay refinement

```swift
var indices = Earcut.tessellate(vertices, holeIndices: holes, dim: dimensions)
Earcut.refine(&indices, coords: vertices, dim: dimensions)
```

## Triangulating many polygons
`Tessellator` keeps its working buffers between calls, so it's often more efficient to use the same `Tesselator` when triangulating a lot of geometry.

```swift
let tessellator = Tessellator()
var indices = [UInt32]()

for polygon in polygons {
    tessellator.tessellate(polygon.vertices, holeIndices: polygon.holes, into: &indices)
    render(indices)
}
```

(Note: `Tessellator` is not `Sendable`. Use one per thread, or one per task.)

## Upgrading from 1.x
Some signatures have changed between 1.x and 2.x, but the 1.x variants remain in the project (with deprecation warnings). Perhaps the largest breaking change is that indices are now returned as `UInt`s.

To resolve deprecation warnings move off of the follow signatures:

| 1.x | 2.0 |
| --- | --- |
| `tessellate(data:holeIndices:dim:) -> [Int]` | `tessellate(_:holeIndices:dim:) -> [UInt32]` |
| `flatten(data:) -> (vertices:holes:dim:)` | `flatten(_:) -> (vertices:holes:dimensions:)` |
| `deviation(data:holeIndices:dim:indices:)` | `deviation(_:holeIndices:dim:triangles:)` |

Worth also noting that triangle output also changes in 2.x. Don't expect the returned indices to match 1.x, even with identical inputs.

See [CHANGELOG.md](CHANGELOG.md) for the full list of changes.