//
//  Earcut.swift
//  Earcut
//
//  A Swift Earcut port of Mapbox's earcut.js
//  https://github.com/mapbox/earcut
//
//  Copyright © 2018 measuredweighed. All rights reserved.
//

import Foundation

final class Node : Equatable {
    // vertex index in coord array
    let i:Int
    
    // vertex coordinates
    let x:Double
    let y:Double
    
    // z-order curve value
    var z:Int = 0
    
    // previous and next nodes in z-order
    weak var prevZ:Node? = nil
    var nextZ:Node? = nil
    
    // previous and next vertex nodes in a polygon ring
    weak var prev:Node? = nil
    var next:Node? = nil
    
    // indicates whether this is a steiner point
    var steiner:Bool = false
    
    init(i:Int, x:Double, y:Double) {
        self.i = i
        self.x = x
        self.y = y
    }
    
    static func == (lhs: Node, rhs: Node) -> Bool {
        return lhs.x == rhs.x && lhs.y == rhs.y
    }
}

/**
 The earcut process doesn't seem to clean-up the `Node`'s generated during
 the tessellation process. As such, I've adopted the solution used in
 Mapbox's own C++ port of earcut, which is to have an allocator keep
 track of all Node instances and then wipe them out at the end of the process
 */
final class NodeAllocator {
    private var nodes:[Node] = [Node]()
    
    public func create(i:Int, x:Double, y:Double) -> Node {
        let node = Node(i: i, x: x, y: y)
        nodes.append(node)
        return node
    }
    
    public func clear() {
        for node in nodes {
            node.next = nil
            node.prev = nil
            node.nextZ = nil
            node.prevZ = nil
        }
        nodes.removeAll()
    }
}

final public class Earcut {
    public static func tessellate(data:[Double], holeIndices:[Int] = [], dim:Int = 2) -> [Int] {
        var triangles:[Int] = [Int]()
        guard data.count > 0 else { return triangles }
        
        let allocator = NodeAllocator()
        
        let hasHoles:Bool = holeIndices.count > 0
        let outerLen:Int = hasHoles ? holeIndices[0] * dim : data.count
        var outerNode = linkedList(
            allocator: allocator,
            data: data,
            start: 0,
            end: outerLen,
            dim: dim,
            clockwise: true
        )
        
        // single point
        guard outerNode.next !== outerNode.prev else { return triangles }
        
        var minX:Double = 0
        var maxX:Double = 0
        var minY:Double = 0
        var maxY:Double = 0
        var invSize:Double = 0
        
        if hasHoles {
            outerNode = eliminateHoles(allocator, data, holeIndices, outerNode, dim)
        }
        
        // if the shape is not too simple, we'll use z-order curve hash later; calculate polygon bbox
        if data.count > 80 * dim {
            minX = data[0]
            maxX = minX
            minY = data[1]
            maxY = minY
            
            for i in stride(from: dim, to:outerLen, by: dim) {
                let x:Double = data[i]
                let y:Double = data[i+1]
                if x < minX { minX = x }
                if y < minY { minY = y }
                if x > maxX { maxX = x }
                if y > maxY { maxY = y }
            }
            
            // minX, minY and size are later used to transform coords into integers for z-order calculation
            invSize = max(maxX - minX, maxY - minY)
            invSize = invSize != 0 ? 32767 / invSize : 0
        }
        
        earcutLinked(allocator, outerNode, &triangles, dim, minX, minY, invSize, 0);
        
        // clean-up memory
        allocator.clear()
        
        return triangles
    }
    
    public static func flatten(data:[[[Double]]]) -> (vertices:[Double], holes:[Int], dim:Int) {
        let dim = data[0][0].count
        
        var holeIndex:Int = 0
        var result:(vertices:[Double], holes:[Int], dim:Int) = (vertices:[Double](), holes:[Int](), dim:dim)
        for i in 0 ..< data.count {
            for j in 0 ..< data[i].count {
                for d in 0 ..< dim {
                    result.vertices.append(data[i][j][d])
                }
            }
            if i > 0 {
                holeIndex += data[i-1].count
                result.holes.append(holeIndex)
            }
        }
        
        return result
    }
    
    // return a percentage difference between the polygon area and its triangulation area;
    // used to verify correctness of triangulation
    public static func deviation(data:[Double], holeIndices:[Int] = [], dim:Int=2, indices:[Int]) -> Double {
        let hasHoles:Bool = holeIndices.count > 0
        let outerLen:Int = hasHoles ? holeIndices[0] * dim : data.count
        
        var polygonArea:Double = abs(signedArea(data: data, start: 0, end: outerLen, dim: dim))
        if hasHoles {
            let len = holeIndices.count
            for i in 0 ..< len {
                let start = holeIndices[i] * dim
                let end = i < len - 1 ? holeIndices[i + 1] * dim : data.count
                polygonArea -= abs(signedArea(data: data, start: start, end: end, dim: dim))
            }
        }
        
        var trianglesArea:Double = 0
        for i in stride(from: 0, to: indices.count, by: 3) {
            let a = indices[i] * dim
            let b = indices[i+1] * dim
            let c = indices[i+2] * dim
            trianglesArea += abs(
                (data[a] - data[c]) * (data[b+1] - data[a+1]) -
                (data[a] - data[b]) * (data[c+1] - data[a+1])
            )
        }
        
        return polygonArea == 0 && trianglesArea == 0 ? 0 : abs((trianglesArea - polygonArea) / polygonArea)
    }
}

// create a circular doubly linked list from polygon points in the specified winding order
fileprivate func linkedList(allocator: NodeAllocator, data:[Double], start:Int, end:Int, dim:Int=2, clockwise:Bool=true) -> Node {
    var last:Node?
    
    if clockwise == (signedArea(data: data, start: start, end: end, dim: dim) > 0) {
        for i in stride(from: start, to: end, by: dim) {
            last = insertNode(allocator: allocator, i: i, x: data[i], y: data[i+1], last: last)
        }
    } else {
        for i in stride(from: end-dim, through: start, by: -dim) {
            last = insertNode(allocator: allocator, i: i, x: data[i], y: data[i+1], last: last)
        }
    }
    
    if let last, last == last.next {
        removeNode(last)
        return last.next!
    }
    return last!
}

fileprivate func insertNode(allocator: NodeAllocator, i:Int, x:Double, y:Double, last:Node?) -> Node {
    let p = allocator.create(i: i, x: x, y: y)
    
    if last == nil {
        p.prev = p
        p.next = p
    } else {
        p.next = last!.next
        p.prev = last
        last!.next?.prev = p
        last!.next = p
    }
    return p
}
fileprivate func removeNode(_ p:Node) {
    p.next?.prev = p.prev
    p.prev?.next = p.next
    
    p.prevZ?.nextZ = p.nextZ
    p.nextZ?.prevZ = p.prevZ
}

// finds the leftmode node of a polygon ring
fileprivate func getLeftmost(_ start:Node) -> Node {
    var p:Node = start
    var leftMost:Node = start
    repeat {
        if p.x < leftMost.x || (p.x == leftMost.x && p.y < leftMost.y) {
            leftMost = p
        }
        p = p.next!
    } while p !== start
    
    return leftMost
}

// eliminate colinear or duplicate points
fileprivate func filterPoints(_ start:Node, _ end:Node?=nil) -> Node {
    var end:Node = end ?? start
    var p = start
    var again:Bool = false
    repeat {
        again = false
        
        if !p.steiner && (p == p.next! || area(p.prev!, p, p.next!) == 0) {
            removeNode(p)
            end = p.prev!
            p = p.prev!
            
            if p === p.next { break }
            again = true
        } else {
            p = p.next!
        }
        
    } while again || p !== end
    
    return end
}


// MARK:- Logic
fileprivate func earcutLinked(_ allocator: NodeAllocator, _ ear:Node, _ triangles:inout[Int], _ dim:Int, _ minX:Double, _ minY:Double, _ invSize:Double, _ pass:Int) {
    var ear:Node = ear
    
    if pass == 0 && invSize > 0 {
        indexCurve(ear, minX, minY, invSize)
    }
    
    var stop:Node? = ear
    
    while ear.prev !== ear.next {
        let prev = ear.prev!
        let next = ear.next!
        
        if (invSize > 0 ? isEarHashed(ear, minX, minY, invSize) : isEar(ear)) {
            // cut off the triangle
            triangles.append(prev.i / dim | 0)
            triangles.append(ear.i / dim | 0)
            triangles.append(next.i / dim | 0)
            
            removeNode(ear)
            
            // skipping the next vertice leads to less sliver triangles
            ear = next.next!
            stop = next.next
            
            continue
        }
        
        ear = next
        
        // if we looped through the whole remaining polygon and can't find any more ears
        if ear === stop {
            
            // try filtering points and slicing again
            if pass == 0 {
                earcutLinked(allocator, filterPoints(ear), &triangles, dim, minX, minY, invSize, 1)
                
            // if this didn't work, try curing all small self-intersections locally
            } else if pass == 1 {
                ear = cureLocalIntersections(filterPoints(ear), &triangles, dim)
                earcutLinked(allocator, ear, &triangles, dim, minX, minY, invSize, 2)
            
            // as a last resort, try splitting the remaining polygon into two
            } else if (pass == 2) {
                splitEarcut(allocator, ear, &triangles, dim, minX, minY, invSize)
            }
            
            break
        }
    }
}

// check whether a polygon node forms a valid ear with adjacent nodes
fileprivate func isEar(_ ear:Node) -> Bool {
    let a = ear.prev!
    let b = ear
    let c = ear.next!
    
    if area(a, b, c) >= 0 { return false }  // reflex, can't be an ear
    
    // now make sure we don't have other points inside the potential ear
    let ax = a.x, bx = b.x, cx = c.x, ay = a.y, by = b.y, cy = c.y;

    // triangle bbox; min & max are calculated like this for speed
    let x0 = ax < bx ? (ax < cx ? ax : cx) : (bx < cx ? bx : cx),
        y0 = ay < by ? (ay < cy ? ay : cy) : (by < cy ? by : cy),
        x1 = ax > bx ? (ax > cx ? ax : cx) : (bx > cx ? bx : cx),
        y1 = ay > by ? (ay > cy ? ay : cy) : (by > cy ? by : cy);
    
    // now make sure we don't have other points inside the potential ear
    var p:Node = c.next!
    while p !== a {
        if (p.x >= x0 && p.x <= x1 && p.y >= y0 && p.y <= y1 &&
            pointInTriangle(ax, ay, bx, by, cx, cy, p.x, p.y) &&
            area(p.prev!, p, p.next!) >= 0) { return false }
        p = p.next!
    }
    
    return true
}
    
fileprivate func isEarHashed(_ ear:Node, _ minX:Double, _ minY:Double, _ invSize:Double) -> Bool {
    let a = ear.prev!
    let b = ear
    let c = ear.next!
    
    if area(a, b, c) >= 0 { return false }  // reflex, can't be an ear
    
    let ax = a.x, bx = b.x, cx = c.x, ay = a.y, by = b.y, cy = c.y;

    // triangle bbox; min & max are calculated like this for speed
    let x0 = ax < bx ? (ax < cx ? ax : cx) : (bx < cx ? bx : cx),
        y0 = ay < by ? (ay < cy ? ay : cy) : (by < cy ? by : cy),
        x1 = ax > bx ? (ax > cx ? ax : cx) : (bx > cx ? bx : cx),
        y1 = ay > by ? (ay > cy ? ay : cy) : (by > cy ? by : cy);

    // z-order range for the current triangle bbox;
    let minZ = zOrder(x0, y0, minX, minY, invSize),
        maxZ = zOrder(x1, y1, minX, minY, invSize);
    
    var p:Node? = ear.prevZ
    var n:Node? = ear.nextZ
    
    // look for points inside the triangle in both directions
    while p != nil && p!.z >= minZ && n != nil && n!.z <= maxZ {
        if (p!.x >= x0 && p!.x <= x1 && p!.y >= y0 && p!.y <= y1 && p! !== a && p! !== c &&
            pointInTriangle(ax, ay, bx, by, cx, cy, p!.x, p!.y) && area(p!.prev!, p!, p!.next!) >= 0) { return false }
        p = p!.prevZ;
        
        if (n!.x >= x0 && n!.x <= x1 && n!.y >= y0 && n!.y <= y1 && n! !== a && n! !== c &&
            pointInTriangle(ax, ay, bx, by, cx, cy, n!.x, n!.y) && area(n!.prev!, n!, n!.next!) >= 0) { return false }
        n = n!.nextZ;
    }
    
    // look for remaining points in decreasing z-order
    while p != nil && p!.z >= minZ {
        if (p!.x >= x0 && p!.x <= x1 && p!.y >= y0 && p!.y <= y1 && p! !== a && p! !== c &&
            pointInTriangle(ax, ay, bx, by, cx, cy, p!.x, p!.y) && area(p!.prev!, p!, p!.next!) >= 0) { return false }
        p = p!.prevZ
    }
    
    // look for remaining points in increasing z-order
    while n != nil && n!.z <= maxZ {
        if (n!.x >= x0 && n!.x <= x1 && n!.y >= y0 && n!.y <= y1 && n! !== a && n! !== c &&
            pointInTriangle(ax, ay, bx, by, cx, cy, n!.x, n!.y) && area(n!.prev!, n!, n!.next!) >= 0) { return false }
        n = n!.nextZ;
    }
    
    return true
}
    
fileprivate func cureLocalIntersections(_ start:Node, _ triangles:inout[Int], _ dim:Int=2) -> Node {
    var start:Node = start
    var p:Node = start
    repeat {
        let a:Node = p.prev!
        let b:Node = p.next!.next!
        
        if a != b && intersects(a, p, p.next!, b) && locallyInside(a, b) && locallyInside(b, a) {
            triangles.append(a.i / dim | 0)
            triangles.append(p.i / dim | 0)
            triangles.append(b.i / dim | 0)
            
            // remove two nodes involved
            removeNode(p)
            removeNode(p.next!)
            
            p = b
            start = b
        }
        p = p.next!
    } while p !== start
    
    return filterPoints(p)
}

// try splitting polygon into two and triangulate them independently
fileprivate func splitEarcut(_ allocator: NodeAllocator, _ start:Node, _ triangles:inout[Int], _ dim:Int = 2, _ minX:Double, _ minY:Double, _ invSize:Double) {
    // look for a valid diagonal that divides the polygon into two
    var a:Node = start
    repeat {
        var b = a.next!.next!
        while b !== a.prev {
            if a.i != b.i && isValidDiagonal(a, b) {
                // split the polygon in two by the diagonal
                var c = splitPolygon(allocator, a, b)
                
                // filter colinear points around the cuts
                a = filterPoints(a, a.next)
                c = filterPoints(c, c.next)
                
                // run earcut on each half
                earcutLinked(allocator, a, &triangles, dim, minX, minY, invSize, 0)
                earcutLinked(allocator, c, &triangles, dim, minX, minY, invSize, 0)
                return
            }
            b = b.next!
        }
        a = a.next!
    } while a !== start
}

// link every hole into the outer loop, producing a single-ring polygon without holes
fileprivate func eliminateHoles(_ allocator: NodeAllocator, _ data:[Double], _ holeIndices:[Int], _ outerNode:Node, _ dim:Int=2) -> Node {
    var outerNode = outerNode
    var queue:[Node] = [Node]()
    let len:Int = holeIndices.count
    
    for i in 0 ..< len {
        let start:Int = holeIndices[i] * dim
        let end:Int = i < len-1 ? holeIndices[i+1] * dim : data.count
        let list = linkedList(allocator: allocator, data: data, start: start, end: end, dim: dim, clockwise: false)
        if list === list.next {
            list.steiner = true
        }
        
        queue.append(getLeftmost(list))
    }
    queue.sort { $0.x < $1.x }
    
    // process holes left to right
    queue.forEach { outerNode = eliminateHole(allocator, $0, outerNode) }
    
    return outerNode
}

// find a bridge between vertices that connects hole with an outer ring and and link it
fileprivate func eliminateHole(_ allocator:NodeAllocator, _ hole:Node, _ outerNode:Node) -> Node {
    guard let bridge = findHoleBridge(hole, outerNode) else { return outerNode }

    let bridgeReverse = splitPolygon(allocator, bridge, hole)
    
    // filter collinear points around the cuts
    let _ = filterPoints(bridgeReverse, bridgeReverse.next)
    return filterPoints(bridge, bridge.next)

}

// David Eberly's algorithm for finding a bridge between hole and outer polygon
fileprivate func findHoleBridge(_ hole:Node, _ outerNode:Node) -> Node? {
    var p:Node = outerNode
    let hx:Double = hole.x
    let hy:Double = hole.y
    var qx:Double = -Double.infinity
    var m:Node?
    
    // find a segment intersected by a ray from the hole's leftmost point to the left;
    // segment's endpoint with lesser x will be potential connection point
    repeat {
        if hy <= p.y && hy >= p.next!.y && p.next!.y != p.y {
            let x:Double = p.x + (hy - p.y) * (p.next!.x - p.x) / (p.next!.y - p.y)
            if x <= hx && x > qx {
                qx = x
                m = p.x < p.next!.x ? p : p.next!
                
                // hole touches outer segment; pick leftmost endpoint
                if x == hx { return m }
            }
        }
        p = p.next!
    } while p !== outerNode
    
    guard var m else { return nil }

    // look for points inside the triangle of hole point, segment intersection and endpoint;
    // if there are no points found, we have a valid connection;
    // otherwise choose the point of the minimum angle with the ray as connection point
    let stop:Node = m
    let mx:Double = m.x
    let my:Double = m.y
    var tanMin:Double = Double.infinity
    
    p = m
    repeat {
        if hx >= p.x && p.x >= mx && hx != p.x &&
            pointInTriangle(hy < my ? hx : qx, hy, mx, my, hy < my ? qx : hx, hy, p.x, p.y) {
            
            let tan = abs(hy - p.y) / (hx - p.x) // tangential
            
            if (
                locallyInside(p, hole) &&
                (tan < tanMin || (tan == tanMin && (p.x > m.x || (p.x == m.x && sectorContainsSector(m, p)))))
            ) {
                m = p
                tanMin = tan
            }
        }
        
        p = p.next!
    } while p !== stop
    
    return m
}

// whether sector in vertex m contains sector in vertex p in the same coordinates
fileprivate func sectorContainsSector(_ m:Node, _ p:Node) -> Bool {
    return area(m.prev!, m, p.prev!) < 0 && area(p.next!, m, m.next!) < 0;
}

// interlink polygon nodes in z-order
fileprivate func indexCurve(_ start:Node, _ minX:Double, _ minY:Double, _ invSize:Double) {
    var p = start
    repeat {
        if p.z == 0 { p.z = zOrder(p.x, p.y, minX, minY, invSize) }
        p.prevZ = p.prev
        p.nextZ = p.next
        p = p.next!
    } while p !== start
    
    p.prevZ?.nextZ = nil
    p.prevZ = nil
    
    let _ = sortLinked(p)
}

// Simon Tatham's linked list merge sort algorithm
// http://www.chiark.greenend.org.uk/~sgtatham/algorithms/listsort.html
fileprivate func sortLinked(_ _list:Node) -> Node {
    
    var list:Node? = _list
    var tail:Node?
    var e:Node?
    var p:Node?
    var q:Node?
    var qSize:Int = 0
    var pSize:Int = 0
    var inSize:Int = 1
    var numMerges:Int = 0
    
    repeat {
        p = list
        list = nil
        tail = nil
        numMerges = 0
        
        while p != nil {
            numMerges += 1
            q = p
            pSize = 0
            for _ in 0 ..< inSize {
                pSize += 1
                q = q!.nextZ
                if q == nil { break }
            }
            qSize = inSize
            
            while pSize > 0 || (qSize > 0 && q != nil) {
                
                if (pSize != 0 && (qSize == 0 || q == nil || p!.z <= q!.z)) {
                    e = p;
                    p = p!.nextZ;
                    pSize-=1;
                } else {
                    e = q;
                    q = q!.nextZ;
                    qSize-=1;
                }
                
                if tail != nil {
                    tail!.nextZ = e
                } else {
                    list = e
                }
                
                e!.prevZ = tail
                tail = e!
            }
            
            p = q
        }
        
        tail?.nextZ = nil
        inSize *= 2
    } while numMerges > 1
    
    return list!
}

// z-order of a point given coords and size of the data bounding box
fileprivate func zOrder(_ x: Double, _ y: Double, _ minX: Double, _ minY: Double, _ invSize: Double) -> Int {
    var x = UInt32((x - minX) * invSize)
    var y = UInt32((y - minY) * invSize)

    x = (x | (x << 8)) & 0x00FF00FF
    x = (x | (x << 4)) & 0x0F0F0F0F
    x = (x | (x << 2)) & 0x33333333
    x = (x | (x << 1)) & 0x55555555

    y = (y | (y << 8)) & 0x00FF00FF
    y = (y | (y << 4)) & 0x0F0F0F0F
    y = (y | (y << 2)) & 0x33333333
    y = (y | (y << 1)) & 0x55555555

    return Int(x | (y << 1))
}

fileprivate func pointInTriangle(_ ax:Double, _ ay:Double, _ bx:Double, _ by:Double, _ cx:Double, _ cy:Double, _ px:Double, _ py:Double) -> Bool {
    return (cx - px) * (ay - py) >= (ax - px) * (cy - py) &&
    (ax - px) * (by - py) >= (bx - px) * (ay - py) &&
    (bx - px) * (cy - py) >= (cx - px) * (by - py)
}

fileprivate func isValidDiagonal(_ a:Node, _ b:Node) -> Bool {
    return a.next!.i != b.i && a.prev!.i != b.i && !intersectsPolygon(a, b) && // doesn't intersect other edges
           (locallyInside(a, b) && locallyInside(b, a) && middleInside(a, b) && // locally visible
            (area(a.prev!, a, b.prev!) > 0 || area(a, b.prev!, b) > 0) || // does not create opposite-facing sectors TODO: audit
            a == b && area(a.prev!, a, a.next!) > 0 && area(b.prev!, b, b.next!) > 0); // special zero-length case
}
fileprivate func area(_ p:Node, _ q:Node, _ r:Node) -> Double {
    return (q.y - p.y) * (r.x - q.x) - (q.x - p.x) * (r.y - q.y)
}
fileprivate func intersects(_ p1:Node, _ q1:Node, _ p2:Node, _ q2:Node) -> Bool {
    let o1 = sign(area(p1, q1, p2))
    let o2 = sign(area(p1, q1, q2))
    let o3 = sign(area(p2, q2, p1))
    let o4 = sign(area(p2, q2, q1))
    
    // general case
    if (o1 != o2 && o3 != o4) { return true }
    
    // p1, q1 and p2 are collinear and p2 lies on p1q1
    if (o1 == 0 && onSegment(p1, p2, q1)) { return true }
    // p1, q1 and q2 are collinear and q2 lies on p1q1
    if (o2 == 0 && onSegment(p1, q2, q1)) { return true }
    // p2, q2 and p1 are collinear and p1 lies on p2q2
    if (o3 == 0 && onSegment(p2, p1, q2)) { return true }
    // p2, q2 and q1 are collinear and q1 lies on p2q2
    if (o4 == 0 && onSegment(p2, q1, q2)) { return true }

    return false
}

// for collinear points p, q, r, check if point q lies on segment pr
fileprivate func onSegment(_ p: Node, _ q: Node, _ r: Node) -> Bool {
    return q.x <= max(p.x, r.x) && q.x >= min(p.x, r.x) && q.y <= max(p.y, r.y) && q.y >= min(p.y, r.y)
}

fileprivate func intersectsPolygon(_ a:Node, _ b: Node) -> Bool {
    var p:Node = a
    repeat {
        if (p.i != a.i && p.next!.i != a.i && p.i != b.i && p.next!.i != b.i &&
            intersects(p, p.next!, a, b)) {
            return true
        }
        p = p.next!
    } while p !== a
    
    return false
}

// check if a polygon diagonal is locally inside the polygon
fileprivate func locallyInside(_ a:Node, _ b:Node) -> Bool {
    return area(a.prev!, a, a.next!) < 0 ?
        area(a, b, a.next!) >= 0 && area(a, a.prev!, b) >= 0 :
        area(a, b, a.prev!) < 0 || area(a, a.next!, b) < 0
}

// check if the middle point of a polygon diagonal is inside the polygon
fileprivate func middleInside(_ a:Node, _ b:Node) -> Bool {
    var p:Node = a
    var inside:Bool = false
    let px:Double = (a.x + b.x) / 2
    let py:Double = (a.y + b.y) / 2
    repeat {
        let next = p.next!
        if (((p.y > py) != (next.y > py)) && next.y != p.y && (px < (next.x - p.x) * (py - p.y) / (next.y - p.y) + p.x)) {
            inside = !inside
        }
        
        p = next
    } while p !== a
    return inside
}

// link two polygon vertices with a bridge; if the vertices belong to the same ring, it splits polygon into two;
// if one belongs to the outer ring and another to a hole, it merges it into a single ring
fileprivate func splitPolygon(_ allocator: NodeAllocator, _ a:Node, _ b:Node) -> Node {
    let a2 = allocator.create(i: a.i, x: a.x, y: a.y)
    let b2 = allocator.create(i: b.i, x: b.x, y: b.y)
    let an = a.next
    let bp = b.prev
    
    a.next = b;
    b.prev = a;

    a2.next = an;
    an?.prev = a2;

    b2.next = a2;
    a2.prev = b2;

    bp?.next = b2;
    b2.prev = bp;
    
    return b2
}
fileprivate func signedArea(data:[Double], start:Int, end:Int, dim:Int=2) -> Double {
    var sum:Double = 0
    var j:Int = end - dim
    for i in stride(from: start, to: end, by: dim) {
        sum += (data[j] - data[i]) * (data[i+1] + data[j+1])
        j = i
    }
    return sum
}

fileprivate func sign(_ num:Double) -> Int {
    return num > 0 ? 1 : num < 0 ? -1 : 0
}
