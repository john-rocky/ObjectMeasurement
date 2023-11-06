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
    
    func setupViews() {
        view.addSubview(distanceFromDeviceLabel)
        distanceFromDeviceLabel.frame = CGRect(x: 0, y: view.bounds.maxY - 300, width: view.bounds.width, height: 150)
        distanceFromDeviceLabel.numberOfLines = 2
        distanceFromDeviceLabel.textAlignment = .center
        distanceFromDeviceLabel.text = "distance"
        distanceFromDeviceLabel.font = .systemFont(ofSize: 20, weight: .heavy)
        
        view.addSubview(recBotton)
        recBotton.frame = CGRect(x: view.center.x - 100, y: distanceFromDeviceLabel.frame.maxY, width: 200, height: 100)
        recBotton.setTitle("撮影", for: .normal)
        recBotton.titleLabel?.font = .systemFont(ofSize: 20, weight: .bold)
        recBotton.addTarget(self, action: #selector(shootPhoto), for: .touchUpInside)
    }
    
    func updateViews(distanceToObject: Float, roll: Float) {
        let distText = "距離: \(round(distanceToObject*10000)/100) cm\n角度 \(roll)°"
        DispatchQueue.main.async {
            self.distanceFromDeviceLabel.isHidden = false
            self.distanceFromDeviceLabel.text = distText
        }
    }
    
    
    @objc func shootPhoto() {
        let uiImage = takePhoto()
        UIImageWriteToSavedPhotosAlbum(uiImage, self, nil, nil)
    }
    
    func setupAR() {
        sceneView.scene.rootNode.addChildNode(baseNode)
        baseNode.addChildNode(TLNode)
    }
    
    func updateAR(distanceToObject: Float) {
        let infrontOfCamera = SCNVector3(x: 0, y: 0, z: -distanceToObject)
        guard let cameraNode = sceneView.pointOfView else { return }
        let pointInWorld = cameraNode.convertPosition(infrontOfCamera, to: nil)

        var screenPos = sceneView.projectPoint(pointInWorld)

        screenPos.x = Float(view.center.x)
        screenPos.y = Float(view.center.y)
        TLNode.isHidden = false
        TLNode.worldPosition = sceneView.unprojectPoint(screenPos)
    }
}
