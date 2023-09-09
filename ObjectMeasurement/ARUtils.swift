//
//  ARUtils.swift
//  ARKitBasics
//
//  Created by 間嶋大輔 on 2023/06/08.
//  Copyright © 2023 Apple. All rights reserved.
//

import Foundation
import ARKit
import SceneKit

extension ViewController {
    
    func setupAR() {
        sceneView.scene.rootNode.addChildNode(baseNode)
        baseNode.addChildNode(TLNode)
        baseNode.addChildNode(bgNode)

    }
    
    
    func getPointOnSurface(cgPoint: CGPoint) -> simd_float3? {

        let raycastQuery = sceneView.raycastQuery(from: cgPoint, allowing: .estimatedPlane, alignment: .any)
        if let unwrappedRaycastQuery = raycastQuery {
            let raycastResults = sceneView.session.raycast(unwrappedRaycastQuery)
            guard let result = raycastResults.first else { return nil }
            let worldCoordinates = simd_float3(
                x: result.worldTransform.columns.3.x,
                y: result.worldTransform.columns.3.y,
                z: result.worldTransform.columns.3.z
            )
            return worldCoordinates
        } else {
            return nil
        }
    }
    
    func getTapCoordinateOnPlaneNode(tapPoint:CGPoint) -> simd_float3? {
        guard let hitTestResult = self.sceneView.hitTest(tapPoint, types: .featurePoint).first else { return nil }
        
        let hitPosition = hitTestResult.worldTransform.columns.3
        let nodeHitTestResults = self.sceneView.hitTest(tapPoint, options: nil)
        
        guard let hitNode = nodeHitTestResults.first?.node else { return nil }
        
        // ノードのジオメトリとの交点を求める
        let localCoordinates = hitNode.convertPosition(SCNVector3(hitPosition.x, hitPosition.y, hitPosition.z), from: nil)
        let intersection = SCNVector3(localCoordinates.x, localCoordinates.y, localCoordinates.z)
        // ジオメトリとの交点の座標（ノード座標系）を取得
        
        let intersectionWorldCoordinates = hitNode.convertPosition(intersection, to: nil)
        return simd_float3(
            x: intersectionWorldCoordinates.x,
            y: intersectionWorldCoordinates.y,
            z: intersectionWorldCoordinates.z
        )
    }
    
    func lineBetweenNodes(positionA: SCNVector3, positionB: SCNVector3, inScene: SCNScene) -> SCNNode {
        let vector = SCNVector3(positionA.x - positionB.x, positionA.y - positionB.y, positionA.z - positionB.z)
        let distance = sqrt(vector.x * vector.x + vector.y * vector.y + vector.z * vector.z)
        let midPosition = SCNVector3 (x:(positionA.x + positionB.x) / 2, y:(positionA.y + positionB.y) / 2, z:(positionA.z + positionB.z) / 2)

        let lineGeometry = SCNCylinder()
        lineGeometry.radius = 0.005
        lineGeometry.height = CGFloat(distance)
        lineGeometry.radialSegmentCount = 5
        lineGeometry.firstMaterial!.diffuse.contents = UIColor.orange

        let lineNode = SCNNode(geometry: lineGeometry)
        lineNode.position = midPosition
        lineNode.look (at: positionB, up: inScene.rootNode.worldUp, localFront: lineNode.worldUp)
    
        return lineNode
    }
  
}
