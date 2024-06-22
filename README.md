# SwiftEarcut
A Swift port of Mapbox's [earcut.js](https://github.com/mapbox/earcut) polygon triangulation library.

[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fmeasuredweighed%2FSwiftEarcut%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/measuredweighed/SwiftEarcut)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fmeasuredweighed%2FSwiftEarcut%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/measuredweighed/SwiftEarcut)

## Table of Contents
1. [License](#license)
2. [Installation](#installation)
3. [Documentation](#documentation)
4. [Quick Start](#quick-start)

## License
Mapbox's [earcut.js](https://github.com/mapbox/earcut) is governed by an [ISC license](https://github.com/mapbox/earcut/blob/main/LICENSE) while this Swift port is governed by an [MIT license](https://github.com/measuredweighed/SwiftEarcut/blob/master/LICENSE).

## Installation

### Swift Package Manager
Add the following dependency
```swift
.package(url: "https://github.com/measuredweighed/SwiftEarcut.git", from: "2.2.4"),
```

## Documentation
Comprehensive documentation for SwiftEarcut can be found on the [Swift Package Index](https://swiftpackageindex.com/measuredweighed/SwiftEarcut/) (click on `Documentation`).

## Quick Start
Pass Earcut a flat array of vertex coordinates and optionally include an array of hole indices, and the tesselate function will return a flat array of triangle indices.

```swift
let result = Earcut.tesselate(data: [10, 0, 0, 50, 60, 60, 70, 10])

// result: [1, 0, 3, 3, 2, 1]
```
