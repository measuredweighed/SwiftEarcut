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
        let earcut = Earcut()
        let result = earcut.tesselate(data: [], holeIndices: [])
        XCTAssertEqual(result, [], "Earcut of empty set failed")
    }
    
    func testSimple() {
        let earcut = Earcut()
        let result = earcut.tesselate(data: [10, 0, 0, 50, 60, 60, 70, 10], holeIndices: nil)
        let expectedResult:[Int] = [1, 0, 3, 3, 2, 1]
        XCTAssertEqual(result, expectedResult, "Earcut of simple 0 hole example failed")
    }
    
    func testSimple3d() {
        let earcut = Earcut()
        let result = earcut.tesselate(data: [10, 0, 0, 0, 50, 0, 60, 60, 0, 70, 10, 0], holeIndices: nil, dim: 3)
        let expectedResult:[Int] = [1, 0, 3, 3, 2, 1]
        XCTAssertEqual(result, expectedResult, "Earcut of simple 3d coordinates example failed")
    }
    
    func testSimpleHole() {
        let earcut = Earcut()
        let result = earcut.tesselate(data: [0,0, 100,0, 100,100, 0,100,  20,20, 80,20, 80,80, 20,80], holeIndices: [4])
        let expectedResult:[Int] = [3,0,4, 5,4,0, 3,4,7, 5,0,1, 2,3,7, 6,5,1, 2,7,6, 6,1,2]
        XCTAssertEqual(result, expectedResult, "Earcut of simple hole example failed")
    }
    
    func areaTest(fixture:String, expectedTriangles:Int, expectedDeviation:Double=1e-14) {
        let bundle = Bundle(for: type(of: self))
        guard let url = bundle.url(forResource: fixture, withExtension: "json") else {
            XCTFail("Missing file: \(fixture).json")
            return
        }
        
        let earcut = Earcut()
        do {
            let data = try Data(contentsOf: url)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [[[Double]]] else {
                XCTFail("\(fixture).json is in an invalid format")
                return
            }
            
            let flattened = earcut.flatten(data: json)
            let indices = earcut.tesselate(data: flattened.vertices, holeIndices: flattened.holes, dim: flattened.dim)
            let deviation = earcut.deviation(data: flattened.vertices, holeIndices: flattened.holes, dim: flattened.dim, indices: indices)
            XCTAssertLessThan(deviation, expectedDeviation, "Expected deviation for \(fixture).json was too high")
            
            if expectedTriangles > 0 {
                let numTriangles = indices.count/3
                XCTAssertEqual(expectedTriangles, numTriangles, "Unexpected number of triangles generated for \(fixture).json")
            }
        } catch {
            XCTFail("Failed to parse \(fixture).json")
            return
        }
    }
    
    func testFixtures() {
        areaTest(fixture: "building", expectedTriangles: 13);
        areaTest(fixture: "dude", expectedTriangles: 106);
        areaTest(fixture: "water", expectedTriangles: 2482, expectedDeviation: 0.0008);
        areaTest(fixture: "water2", expectedTriangles: 1212);
        areaTest(fixture: "water3", expectedTriangles: 197);
        areaTest(fixture: "water3b", expectedTriangles: 25);
        areaTest(fixture: "water4", expectedTriangles: 705);
        areaTest(fixture: "water-huge", expectedTriangles: 5174, expectedDeviation: 0.0011);
        areaTest(fixture: "water-huge2", expectedTriangles: 4461, expectedDeviation: 0.0028);
        areaTest(fixture: "degenerate", expectedTriangles: 0);
        areaTest(fixture: "bad-hole", expectedTriangles: 42, expectedDeviation: 0.019);
        areaTest(fixture: "empty-square", expectedTriangles: 0);
        areaTest(fixture: "issue16", expectedTriangles: 12);
        areaTest(fixture: "issue17", expectedTriangles: 11);
        areaTest(fixture: "steiner", expectedTriangles: 9);
        areaTest(fixture: "issue29", expectedTriangles: 40);
        areaTest(fixture: "issue34", expectedTriangles: 139);
        areaTest(fixture: "issue35", expectedTriangles: 844);
        areaTest(fixture: "self-touching", expectedTriangles: 124, expectedDeviation: 3.4e-14);
        areaTest(fixture: "outside-ring", expectedTriangles: 64);
        areaTest(fixture: "simplified-us-border", expectedTriangles: 120);
        areaTest(fixture: "touching-holes", expectedTriangles: 57);
        areaTest(fixture: "hole-touching-outer", expectedTriangles: 77);
        areaTest(fixture: "hilbert", expectedTriangles: 1024);
        areaTest(fixture: "issue45", expectedTriangles: 10);
        areaTest(fixture: "eberly-3", expectedTriangles: 73);
        areaTest(fixture: "eberly-6", expectedTriangles: 1429);
        areaTest(fixture: "issue52", expectedTriangles: 109);
        areaTest(fixture: "shared-points", expectedTriangles: 4);
        areaTest(fixture: "bad-diagonals", expectedTriangles: 7);
        areaTest(fixture: "issue83", expectedTriangles: 0, expectedDeviation: 1e-14);
    }
    
    func testOpsPerSec() {
        
        let fixture:String = "water"
        let bundle = Bundle(for: type(of: self))
        guard let url = bundle.url(forResource: fixture, withExtension: "json") else {
            XCTFail("Missing file: \(fixture).json")
            return
        }
        
        let earcut = Earcut()
        do {
            let data = try Data(contentsOf: url)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [[[Double]]] else {
                XCTFail("\(fixture).json is in an invalid format")
                return
            }
            
            let flattened = earcut.flatten(data: json)
            
            let start = CACurrentMediaTime()
            var ops:Int = 0
            while(CACurrentMediaTime() - start < 1) {
                let _ = earcut.tesselate(data: flattened.vertices, holeIndices: flattened.holes, dim: flattened.dim)
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
