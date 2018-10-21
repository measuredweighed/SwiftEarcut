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

/**
 Scalar is the type used through Earcut. If you'd rather
 deal with `Float` values, you can change that here
 */
public typealias Scalar = Double

final class Node : Equatable {
    // vertex index in coord array
    var i:Int
    
    // vertex coordinates
    var x:Scalar
    var y:Scalar
    
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
    
    init(i:Int, x:Scalar, y:Scalar) {
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
 the tesselation process. As such, I've adopted the solution used in
 Mapbox's own C++ port of earcut, which is to have an allocator keep
 track of all Node instances and then wipe them out at the end of the process
 */
final class NodeAllocator {
    var nodes:[Node] = [Node]()
    
    public func create(i:Int, x:Scalar, y:Scalar) -> Node {
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


fileprivate func signedArea(data:[Scalar], start:Int, end:Int, dim:Int=2) -> Scalar {
    var sum:Scalar = 0
    var j:Int = end - dim
    for i in stride(from: start, to:end, by: dim) {
        sum += (data[j] - data[i]) * (data[i+1] + data[j+1])
        j = i
    }
    return sum
}

final public class Earcut {
    var allocator = NodeAllocator()
    
    public func tesselate(data:[Scalar], holeIndices:[Int]?, dim:Int=2) -> [Int] {
        let hasHoles:Bool = holeIndices != nil && holeIndices!.count > 0
        let outerLen:Int = hasHoles ? holeIndices![0] * dim : data.count
        
        var triangles:[Int] = [Int]()
        guard var outerNode = linkedList(
            allocator: allocator,
            data: data,
            start: 0,
            end: outerLen,
            dim: dim,
            clockwise: true
        ) else { return triangles }
        
        var minX:Scalar = 0
        var maxX:Scalar = 0
        var minY:Scalar = 0
        var maxY:Scalar = 0
        var invSize:Scalar = 0
        
        if hasHoles {
            outerNode = eliminateHoles(data, holeIndices!, outerNode, dim)
        }
        
        // if the shape is not too simple, we'll use z-order curve hash later; calculate polygon bbox
        if data.count > 80 * dim {
            minX = data[0]
            maxX = minX
            minY = data[1]
            maxY = minY
            
            for i in stride(from: dim, to:outerLen, by: dim) {
                let x:Scalar = data[i]
                let y:Scalar = data[i+1]
                if x < minX { minX = x }
                if y < minY { minY = y }
                if x > maxX { maxX = x }
                if y > maxY { maxY = y }
            }
            
            // minX, minY and size are later used to transform coords into integers for z-order calculation
            invSize = max(maxX - minX, maxY - minY)
            invSize = invSize != 0 ? 1 / invSize : 0
        }
        
        earcutLinked(outerNode, &triangles, dim, minX, minY, invSize);
        
        // clean-up memory
        allocator.clear()
        
        return triangles
    }
    
    // create a circular doubly linked list from polygon points in the specified winding order
    private func linkedList(allocator:NodeAllocator, data:[Scalar], start:Int, end:Int, dim:Int=2, clockwise:Bool=true) -> Node? {
        var last:Node?
        
        if clockwise == (signedArea(data: data, start: start, end: end, dim: dim) > 0) {
            for i in stride(from: start, to: end, by: dim) {
                last = insertNode(p: allocator.create(i: i, x: data[i], y: data[i+1]), last: last)
            }
        } else {
            for i in stride(from: end-dim, through: start, by: -dim) {
                last = insertNode(p: allocator.create(i: i, x: data[i], y: data[i+1]), last: last)
            }
        }
        
        if last != nil && last! == last!.next! {
            removeNode(last!)
            last = last!.next
        }
        return last
    }
    
    private func insertNode(p:Node, last:Node?) -> Node {
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
    private func removeNode(_ p:Node) {
        p.next?.prev = p.prev
        p.prev?.next = p.next
        
        p.prevZ?.nextZ = p.nextZ
        p.nextZ?.prevZ = p.prevZ
    }
    
    // finds the leftmode node of a polygon ring
    private func getLeftmost(_ start:Node) -> Node? {
        var p:Node? = start
        var leftMost:Node? = start
        repeat {
            if p!.x < leftMost!.x {
                leftMost = p
            }
            p = p!.next
        } while p !== start
        
        return leftMost
    }
    
    public func flatten(data:[[[Scalar]]]) -> (vertices:[Scalar], holes:[Int], dim:Int) {
        let dim = data[0][0].count
        
        var holeIndex:Int = 0
        var result:(vertices:[Scalar], holes:[Int], dim:Int) = (vertices:[Scalar](), holes:[Int](), dim:dim)
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
    public func deviation(data:[Scalar], holeIndices:[Int]?, dim:Int=2, indices:[Int]) -> Scalar {
        let hasHoles:Bool = holeIndices != nil && holeIndices!.count > 0
        let outerLen:Int = hasHoles ? holeIndices![0] * dim : data.count
        
        var polygonArea:Scalar = abs(signedArea(data: data, start: 0, end: outerLen, dim: dim))
        if hasHoles {
            let len = holeIndices!.count
            for i in 0 ..< len {
                let start = holeIndices![i] * dim
                let end = i < len - 1 ? holeIndices![i + 1] * dim : data.count
                polygonArea -= abs(signedArea(data: data, start: start, end: end, dim: dim))
            }
        }
        
        var trianglesArea:Scalar = 0
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
    
    // eliminate colinear or duplicate points
    private func filterPoints(_ start:Node, _ _end:Node?=nil) -> Node {
        var end:Node = _end != nil ? _end! : start
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
    private func earcutLinked(_ _ear:Node?, _ triangles:inout[Int], _ dim:Int, _ minX:Scalar, _ minY:Scalar, _ invSize:Scalar, _ pass:Int=0) {
        guard var ear:Node = _ear else { return }
        
        if pass == 0 && invSize > 0 {
            indexCurve(ear, minX, minY, invSize)
        }
        
        var stop:Node? = ear
        var prev:Node! = nil
        var next:Node! = nil
        
        while ear.prev !== ear.next {
            prev = ear.prev
            next = ear.next
            
            let _isEar = invSize > 0 ? isEarHashed(ear, minX, minY, invSize) : isEar(ear)
            if _isEar {
                // cut off the triangle
                triangles.append(prev.i / dim)
                triangles.append(ear.i / dim)
                triangles.append(next.i / dim)
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
                    earcutLinked(filterPoints(ear), &triangles, dim, minX, minY, invSize, 1)
                    
                // if this didn't work, try curing all small self-intersections locally
                } else if pass == 1 {
                    ear = cureLocalIntersections(ear, &triangles, dim)
                    earcutLinked(ear, &triangles, dim, minX, minY, invSize, 2)
                
                // as a last resort, try splitting the remaining polygon into two
                } else if (pass == 2) {
                    splitEarcut(ear, &triangles, dim, minX, minY, invSize)
                }
                
                break
            }
        }
    }
    
    // check whether a polygon node forms a valid ear with adjacent nodes
    private func isEar(_ ear:Node) -> Bool {
        let a = ear.prev!
        let b = ear
        let c = ear.next!
        
        if area(a, b, c) >= 0 { return false }  // reflex, can't be an ear
        
        // now make sure we don't have other points inside the potential ear
        var p:Node = ear.next!.next!
        
        while p !== ear.prev {
            if pointInTriangle(a.x, a.y, b.x, b.y, c.x, c.y, p.x, p.y) &&
                area(p.prev!, p, p.next!) >= 0 { return false }
            p = p.next!
        }
        
        return true
    }
private func isEarHashed(_ ear:Node, _ minX:Scalar, _ minY:Scalar, _ invSize:Scalar) -> Bool {
    let a = ear.prev!
    let b = ear
    let c = ear.next!
    
    if area(a, b, c) >= 0 { return false }  // reflex, can't be an ear
    
    let minTX:Scalar = a.x < b.x ? (a.x < c.x ? a.x : c.x) : (b.x < c.x ? b.x : c.x)
    let minTY:Scalar = a.y < b.y ? (a.y < c.y ? a.y : c.y) : (b.y < c.y ? b.y : c.y)
    let maxTX:Scalar = a.x > b.x ? (a.x > c.x ? a.x : c.x) : (b.x > c.x ? b.x : c.x)
    let maxTY:Scalar = a.y > b.y ? (a.y > c.y ? a.y : c.y) : (b.y > c.y ? b.y : c.y)
    
    // z-order range for the current triangle bbox;
    let minZ:Int = zOrder(minTX, minTY, minX, minY, invSize)
    let maxZ:Int = zOrder(maxTX, maxTY, minX, minY, invSize)
    
    var p:Node? = ear.prevZ
    var n:Node? = ear.nextZ
    
    // look for points inside the triangle in both directions
    while p != nil && p!.z >= minZ && n != nil && n!.z <= maxZ {
        if (p! !== ear.prev && p! !== ear.next &&
            pointInTriangle(a.x, a.y, b.x, b.y, c.x, c.y, p!.x, p!.y) &&
            area(p!.prev!, p!, p!.next!) >= 0) { return false; }
        p = p!.prevZ;
        
        if (n! !== ear.prev && n! !== ear.next &&
            pointInTriangle(a.x, a.y, b.x, b.y, c.x, c.y, n!.x, n!.y) &&
            area(n!.prev!, n!, n!.next!) >= 0) { return false; }
        n = n!.nextZ;
    }
    
    // look for remaining points in decreasing z-order
    while p != nil && p!.z >= minZ {
        if p !== ear.prev && p !== ear.next &&
            pointInTriangle(a.x, a.y, b.x, b.y, c.x, c.y, p!.x, p!.y) &&
            area(p!.prev!, p!, p!.next!) >= 0 { return false }
        p = p!.prevZ
    }
    
    // look for remaining points in increasing z-order
    while n != nil && n!.z <= maxZ {
        if n !== ear.prev && n !== ear.next &&
            pointInTriangle(a.x, a.y, b.x, b.y, c.x, c.y, n!.x, n!.y) &&
            area(n!.prev!, n!, n!.next!) >= 0 { return false }
        n = n!.nextZ;
    }
    
    return true
}
    
    private func cureLocalIntersections(_ _start:Node, _ triangles:inout[Int], _ dim:Int=2) -> Node {
        var start:Node = _start
        var p:Node = start
        repeat {
            let a:Node = p.prev!
            let b:Node = p.next!.next!
            
            if a != b && intersects(a, p, p.next!, b) && locallyInside(a, b) && locallyInside(b, a) {
                triangles.append(a.i / dim)
                triangles.append(p.i / dim)
                triangles.append(b.i / dim)
                
                // remove two nodes involved
                removeNode(p)
                removeNode(p.next!)
                p = b
                start = b
            }
            p = p.next!
        } while p !== start
        
        return p
    }
    
    // try splitting polygon into two and triangulate them independently
    private func splitEarcut(_ start:Node, _ triangles:inout[Int], _ dim:Int = 2, _ minX:Scalar, _ minY:Scalar, _ invSize:Scalar) {
        // look for a valid diagonal that divides the polygon into two
        var a:Node = start
        repeat {
            var b = a.next!.next!
            while b !== a.prev {
                if a.i != b.i && isValidDiagonal(a, b) {
                    // split the polygon in two by the diagonal
                    var c:Node = splitPolygon(a, b)
                    
                    // filter colinear points around the cuts
                    a = filterPoints(a, a.next)
                    c = filterPoints(c, c.next)
                    
                    // run earcut on each half
                    earcutLinked(a, &triangles, dim, minX, minY, invSize)
                    earcutLinked(c, &triangles, dim, minX, minY, invSize)
                    return
                }
                b = b.next!
            }
            a = a.next!
        } while a !== start
    }
    
    // link every hole into the outer loop, producing a single-ring polygon without holes
    private func eliminateHoles(_ data:[Scalar], _ holeIndices:[Int], _ _outerNode:Node, _ dim:Int=2) -> Node {
        var outerNode = _outerNode
        var queue:[Node] = [Node]()
        var start:Int = 0
        var end:Int = 0
        let len:Int = holeIndices.count
        
        for i in 0 ..< len {
            start = holeIndices[i] * dim
            end = i < len-1 ? holeIndices[i+1] * dim : data.count
            if let list = linkedList(allocator: allocator, data: data, start: start, end: end, dim: dim, clockwise: false) {
                if list === list.next {
                    list.steiner = true
                }
                
                if let node = getLeftmost(list) {
                    queue.append(node)
                }
            }
        }
        queue.sort { (a, b) -> Bool in
            return (a.x - b.x) <= 0
        }
        
        // process holes left -> right
        for i in 0 ..< queue.count {
            eliminateHole(queue[i], outerNode)
            outerNode = filterPoints(outerNode, outerNode.next)
        }
        
        return outerNode
    }
    
    // find a bridge between vertices that connects hole with an outer ring and and link it
    private func eliminateHole(_ hole:Node, _ _outerNode:Node?) {
        
        let outerNode = findHoleBridge(hole: hole, outerNode: _outerNode!)
        if outerNode != nil {
            let b = splitPolygon(outerNode!, hole)
            let _ = filterPoints(b, b.next)
        }
    }
    
    // David Eberly's algorithm for finding a bridge between hole and outer polygon
    private func findHoleBridge(hole:Node, outerNode:Node) -> Node? {
        var p:Node = outerNode
        let hx:Scalar = hole.x
        let hy:Scalar = hole.y
        var qx:Scalar = -Scalar.infinity
        var m:Node?
        
        // find a segment intersected by a ray from the hole's leftmost point to the left;
        // segment's endpoint with lesser x will be potential connection point
        repeat {
            if hy <= p.y && hy >= p.next!.y && p.next!.y != p.y {
                let x:Scalar = p.x + (hy - p.y) * (p.next!.x - p.x) / (p.next!.y - p.y)
                if x <= hx && x > qx {
                    qx = x
                    if x == hx {
                        if hy == p.y { return p }
                        if hy == p.next!.y { return p.next! }
                    }
                    
                    m = p.x < p.next!.x ? p : p.next!
                }
            }
            p = p.next!
        } while p !== outerNode
        
        guard m != nil else { return nil }
        
        // hole touches outer segment; pick lower endpoint
        if hx == qx {
            return m!.prev
        }
        
        // look for points inside the triangle of hole point, segment intersection and endpoint;
        // if there are no points found, we have a valid connection;
        // otherwise choose the point of the minimum angle with the ray as connection point
        let stop:Node = m!
        let mx:Scalar = m!.x
        let my:Scalar = m!.y
        var tanMin:Scalar = Scalar.infinity
        var tan:Scalar = 0
        
        p = m!.next!
        while p !== stop {
            if hx >= p.x && p.x >= mx && hx != p.x &&
                pointInTriangle(hy < my ? hx : qx, hy, mx, my, hy < my ? qx : hx, hy, p.x, p.y) {
                tan = abs(hy - p.y) / (hx - p.x) // tangential
                
                if ((tan < tanMin || (tan == tanMin && p.x > m!.x)) && locallyInside(p, hole)) {
                    m = p
                    tanMin = tan
                }
            }
            
            p = p.next!
        }
        
        return m
    }
    
    // interlink polygon nodes in z-order
    private func indexCurve(_ start:Node, _ minX:Scalar, _ minY:Scalar, _ invSize:Scalar) {
        var p = start
        repeat {
            p.z = p.z != 0 ? p.z : zOrder(p.x, p.y, minX, minY, invSize)
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
    private func sortLinked(_ _list:Node) -> Node {
        
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
    private func zOrder(_ _x:Scalar, _ _y:Scalar, _ minX:Scalar, _ minY:Scalar, _ invSize:Scalar) -> Int {
        // coords are transformed into non-negative 15-bit integer range
        var x:Int = Int(32767 * (_x - minX) * invSize)
        var y:Int = Int(32767 * (_y - minY) * invSize)
        
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
    
    private func pointInTriangle(_ ax:Scalar, _ ay:Scalar, _ bx:Scalar, _ by:Scalar, _ cx:Scalar, _ cy:Scalar, _ px:Scalar, _ py:Scalar) -> Bool {
        return (cx - px) * (ay - py) - (ax - px) * (cy - py) >= 0 &&
            (ax - px) * (by - py) - (bx - px) * (ay - py) >= 0 &&
            (bx - px) * (cy - py) - (cx - px) * (by - py) >= 0
    }
    
    private func isValidDiagonal(_ a:Node, _ b:Node) -> Bool {
        return a.next!.i != b.i && a.prev!.i != b.i && !intersectsPolygon(a, b) &&
                locallyInside(a, b) && locallyInside(b, a) && middleInside(a, b)
    }
    private func area(_ p:Node, _ q:Node, _ r:Node) -> Scalar {
        return (q.y - p.y) * (r.x - q.x) - (q.x - p.x) * (r.y - q.y)
    }
    private func intersects(_ p1:Node, _ q1:Node, _ p2:Node, _ q2:Node) -> Bool {
        if ((p1 == q1 && p2 == q2) || (p1 == q2 && p2 == q1)) {
            return true
        }
        
        return (area(p1, q1, p2) > 0) != (area(p1, q1, q2) > 0) &&
            (area(p2, q2, p1) > 0) != (area(p2, q2, q1) > 0)
    }
    private func intersectsPolygon(_ a:Node, _ b: Node) -> Bool {
        var p:Node = a
        repeat {
            if p.i != a.i && p.next!.i != a.i && p.i != b.i && p.next!.i != b.i && intersects(p, p.next!, a, b) {
                return true
            }
            p = p.next!
        } while p !== a
        
        return false
    }
    
    // check if a polygon diagonal is locally inside the polygon
    private func locallyInside(_ a:Node, _ b:Node) -> Bool {
        return area(a.prev!, a, a.next!) < 0 ?
            area(a, b, a.next!) >= 0 && area(a, a.prev!, b) >= 0 :
            area(a, b, a.prev!) < 0 || area(a, a.next!, b) < 0
    }
    
    // check if the middle point of a polygon diagonal is inside the polygon
    private func middleInside(_ a:Node, _ b:Node) -> Bool {
        var p:Node = a
        var inside:Bool = false
        let px:Scalar = (a.x + b.x) / 2
        let py:Scalar = (a.y + b.y) / 2
        repeat {
            if (((p.y > py) != (p.next!.y > py)) && p.next!.y != p.y &&
                (px < (p.next!.x - p.x) * (py - p.y) / (p.next!.y - p.y) + p.x)) {
                inside = !inside
            }
            
            p = p.next!
        } while p !== a
        return inside
    }
    
    // link two polygon vertices with a bridge; if the vertices belong to the same ring, it splits polygon into two;
    // if one belongs to the outer ring and another to a hole, it merges it into a single ring
    private func splitPolygon(_ a:Node, _ b:Node) -> Node {
        let a2 = allocator.create(i: a.i, x: a.x, y: a.y)
        let b2 = allocator.create(i: b.i, x: b.x, y: b.y)
        let an = a.next
        let bp = b.prev
        
        a.next = b
        b.prev = a
        
        a2.next = an
        an?.prev = a2
        
        b2.next = a2
        a2.prev = b2
        
        bp?.next = b2
        b2.prev = bp
        
        return b2
    }
}
