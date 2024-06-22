//
//  EarcutTests.swift
//  EarcutTests
//
//  Copyright © 2018 measuredweighed. All rights reserved.
//

import XCTest
@testable import Earcut

class EarcutTests: XCTestCase {

    func testEmpty() {
        let result = Earcut.tesselate(data: [], holeIndices: [])
        XCTAssertEqual(result, [], "Earcut of empty set failed")
    }
    
    func testIndices2D() {
        let result = Earcut.tesselate(data: [10, 0, 0, 50, 60, 60, 70, 10])
        let expectedResult:[Int] = [1, 0, 3, 3, 2, 1]
        XCTAssertEqual(result, expectedResult, "Earcut of simple 2D coordinates example failed")
    }
    
    func testIndices3D() {
        let result = Earcut.tesselate(data: [10, 0, 0, 0, 50, 0, 60, 60, 0, 70, 10, 0], dim: 3)
        let expectedResult:[Int] = [1, 0, 3, 3, 2, 1]
        XCTAssertEqual(result, expectedResult, "Earcut of simple 3D coordinates example failed")
    }
    
    func testInfiniteLoop() {
        let _ = Earcut.tesselate(data: [1, 2, 2, 2, 1, 2, 1, 1, 1, 2, 4, 1, 5, 1, 3, 2, 4, 2, 4, 1], holeIndices: [5], dim: 3)
    }
    
    func areaTest(fixture:String, expectedTriangles:Int, expectedDeviation:Double=1e-14) {
        guard let url = Bundle.module.url(forResource: fixture, withExtension: "json", subdirectory: "fixtures") else {
            XCTFail("Missing file: \(fixture).json")
            return
        }
        
        do {
            let data = try Data(contentsOf: url)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [[[Double]]] else {
                XCTFail("\(fixture).json is in an invalid format")
                return
            }
            
            let flattened = Earcut.flatten(data: json)
            
            let indices = Earcut.tesselate(data: flattened.vertices, holeIndices: flattened.holes, dim: flattened.dim)
            let deviation = Earcut.deviation(data: flattened.vertices, holeIndices: flattened.holes, dim: flattened.dim, indices: indices)
            if expectedTriangles > 0 {
                XCTAssertLessThan(deviation, expectedDeviation, "Expected deviation for \(fixture).json was too high")
                
                let numTriangles = indices.count/3
                XCTAssertEqual(expectedTriangles, numTriangles, "Unexpected number of triangles generated for \(fixture).json")
            }
        } catch {
            XCTFail("Failed to parse \(fixture).json")
            return
        }
    }
    
    func testFixtures() {
        areaTest(fixture: "building", expectedTriangles: 13)
        areaTest(fixture: "dude", expectedTriangles: 106, expectedDeviation: 2e-15)
        areaTest(fixture: "water", expectedTriangles: 2482, expectedDeviation: 0.0008)
        areaTest(fixture: "water2", expectedTriangles: 1212)
        areaTest(fixture: "water3", expectedTriangles: 197)
        areaTest(fixture: "water3b", expectedTriangles: 25)
        areaTest(fixture: "water4", expectedTriangles: 705)
        areaTest(fixture: "water-huge", expectedTriangles: 5177, expectedDeviation: 0.0011)
        areaTest(fixture: "water-huge2", expectedTriangles: 4462, expectedDeviation: 0.0028)
        areaTest(fixture: "degenerate", expectedTriangles: 0)
        areaTest(fixture: "bad-hole", expectedTriangles: 42, expectedDeviation: 0.019)
        areaTest(fixture: "empty-square", expectedTriangles: 0)
        areaTest(fixture: "issue16", expectedTriangles: 12)
        areaTest(fixture: "issue17", expectedTriangles: 11, expectedDeviation: 2e-16)
        areaTest(fixture: "steiner", expectedTriangles: 9)
        areaTest(fixture: "issue29", expectedTriangles: 40, expectedDeviation: 2e-15)
        areaTest(fixture: "issue34", expectedTriangles: 139)
        areaTest(fixture: "issue35", expectedTriangles: 844)
        areaTest(fixture: "self-touching", expectedTriangles: 124, expectedDeviation: 2e-13)
        areaTest(fixture: "outside-ring", expectedTriangles: 64)
        areaTest(fixture: "simplified-us-border", expectedTriangles: 120)
        areaTest(fixture: "touching-holes", expectedTriangles: 57)
        areaTest(fixture: "hole-touching-outer", expectedTriangles: 77)
        areaTest(fixture: "hilbert", expectedTriangles: 1024)
        areaTest(fixture: "issue45", expectedTriangles: 10)
        areaTest(fixture: "eberly-3", expectedTriangles: 73)
        areaTest(fixture: "eberly-6", expectedTriangles: 1429, expectedDeviation: 2e-14)
        areaTest(fixture: "issue52", expectedTriangles: 109)
        areaTest(fixture: "shared-points", expectedTriangles: 4)
        areaTest(fixture: "bad-diagonals", expectedTriangles: 7)
        areaTest(fixture: "issue83", expectedTriangles: 0)
        areaTest(fixture: "issue107", expectedTriangles: 0)
        areaTest(fixture: "issue111", expectedTriangles: 19)
        areaTest(fixture: "boxy", expectedTriangles: 57)
        areaTest(fixture: "collinear-diagonal", expectedTriangles: 14)
        areaTest(fixture: "issue119", expectedTriangles: 18)
        areaTest(fixture: "hourglass", expectedTriangles: 2)
        areaTest(fixture: "touching2", expectedTriangles: 8)
        areaTest(fixture: "touching3", expectedTriangles: 15)
        areaTest(fixture: "touching4", expectedTriangles: 20)
        areaTest(fixture: "rain", expectedTriangles: 2681)
        areaTest(fixture: "issue131", expectedTriangles: 12)
        areaTest(fixture: "infinite-loop-jhl", expectedTriangles: 0)
        areaTest(fixture: "filtered-bridge-jhl", expectedTriangles: 25)
        areaTest(fixture: "issue149", expectedTriangles: 2)
        areaTest(fixture: "issue142", expectedTriangles: 4, expectedDeviation: 0.13)
    }
    
    func testOpsPerSec() {
        
        let fixture:String = "water"
        guard let url = Bundle.module.url(forResource: fixture, withExtension: "json", subdirectory: "fixtures") else {
            XCTFail("Missing file: \(fixture).json")
            return
        }
        
        do {
            let data = try Data(contentsOf: url)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [[[Double]]] else {
                XCTFail("\(fixture).json is in an invalid format")
                return
            }
            
            let flattened = Earcut.flatten(data: json)
            
            let start = CACurrentMediaTime()
            var ops:Int = 0
            while(CACurrentMediaTime() - start < 1) {
                let _ = Earcut.tesselate(data: flattened.vertices, holeIndices: flattened.holes, dim: flattened.dim)
                ops += 1
            }
            
            let diff = CACurrentMediaTime()-start
            print("\(round(Double(ops)/diff)) ops per sec (\(diff) elapsed)")
            
        } catch {
            XCTFail("Failed to parse \(fixture).json")
            return
        }
    }

}
