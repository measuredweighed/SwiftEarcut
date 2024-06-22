# ``Earcut``

Copyright © 2018 measuredweighed. All rights reserved.

A Swift port of Mapbox's [earcut.js](https://github.com/mapbox/earcut) polygon triangulation library (ISC License, Copyright (c) 2016, Mapbox).

#### The algorithm

The library implements a modified ear slicing algorithm,
optimized by [z-order curve](http://en.wikipedia.org/wiki/Z-order_curve) hashing
and extended to handle holes, twisted polygons, degeneracies and self-intersections
in a way that doesn't _guarantee_ correctness of triangulation,
but attempts to always produce acceptable results for practical data.

It's based on ideas from [FIST: Fast Industrial-Strength Triangulation of Polygons](http://www.cosy.sbg.ac.at/~held/projects/triang/triang.html) by Martin Held and [Triangulation by Ear Clipping](http://www.geometrictools.com/Documentation/TriangulationByEarClipping.pdf) by David Eberly.

If you want to get correct triangulation even on very bad data with lots of self-intersections and earcut is not precise enough, take a look at [libtess.js](https://github.com/brendankenny/libtess.js).

If you pass a single vertex as a hole, Earcut treats it as a Steiner point.

Note that Earcut is a **2D** triangulation algorithm, and handles 3D data as if it was projected onto the XY plane (with Z component ignored).

## Topics

### 1. Preparing the Polygon

- ``Earcut/Earcut/flatten(data:)``

### 2. Tessellating the Polygon

- ``Earcut/Earcut/tessellate(data:holeIndices:dim:)``

### 3. Verifying by checking the Size (optional)

- ``Earcut/Earcut/deviation(data:holeIndices:dim:indices:)``
