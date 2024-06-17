# SwiftEarcut
A Swift port of Mapbox's [earcut.js](https://github.com/mapbox/earcut) polygon triangulation library.

## Usage
Pass Earcut a flat array of vertex coordinates and optionally include an array of hole indices, and the tesselate function will return a flat array of triangle indices.

```
let result = Earcut.tesselate(data: [10, 0, 0, 50, 60, 60, 70, 10])

// result: [1, 0, 3, 3, 2, 1]
```


