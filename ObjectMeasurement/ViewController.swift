/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Main view controller for the AR experience.
*/

import UIKit
import SceneKit
import ARKit
import Vision


class ViewController: UIViewController, ARSCNViewDelegate, ARSessionDelegate, ARCoachingOverlayViewDelegate {
    // MARK: - IBOutlets

    @IBOutlet weak var sessionInfoView: UIView!
    @IBOutlet weak var sessionInfoLabel: UILabel!
    @IBOutlet weak var sceneView: ARSCNView!
    var widthLabel = UILabel()
    var heightLabel = UILabel()
    var classLabel = UILabel()
    let coachingOverlay = ARCoachingOverlayView()

    var yoloRequest: VNCoreMLRequest!
    private var frameRect: CGRect?
    let ciContext = CIContext()

    var distanceFromDeviceLabel = UILabel()
    
    // Node
    var baseNode = SCNNode()
    
    // top left
    var TLNode: SCNNode = {
        let node = SCNNode(geometry: SCNSphere(radius: 0.01))
        node.worldPosition = SCNVector3(x: 0, y: 10, z: 0)
        node.geometry?.materials.first?.diffuse.contents = UIColor.orange
        return node
    }()

    // top right
    var TRNode: SCNNode = {
        let node = SCNNode(geometry: SCNSphere(radius: 0.01))
        node.worldPosition = SCNVector3(x: 0, y: 10, z: 0)
        node.geometry?.materials.first?.diffuse.contents = UIColor.orange
        return node
    }()

    // bottom left
    var BLNode: SCNNode = {
        let node = SCNNode(geometry: SCNSphere(radius: 0.01))
        node.worldPosition = SCNVector3(x: 0, y: 10, z: 0)
        node.geometry?.materials.first?.diffuse.contents = UIColor.orange
        return node
    }()

    // bottom right
    var BRNode: SCNNode = {
        let node = SCNNode(geometry: SCNSphere(radius: 0.01))
        node.worldPosition = SCNVector3(x: 0, y: 10, z: 0)
        node.geometry?.materials.first?.diffuse.contents = UIColor.orange
        return node
    }()
    
    var LCNode: SCNNode = {
        let node = SCNNode(geometry: SCNSphere(radius: 0.01))
        node.worldPosition = SCNVector3(x: 0, y: 10, z: 0)
        node.geometry?.materials.first?.diffuse.contents = UIColor.orange
        return node
    }()
    
    var RCNode: SCNNode = {
        let node = SCNNode(geometry: SCNSphere(radius: 0.01))
        node.worldPosition = SCNVector3(x: 0, y: 10, z: 0)
        node.geometry?.materials.first?.diffuse.contents = UIColor.orange
        return node
    }()
    
    var TCNode: SCNNode = {
        let node = SCNNode(geometry: SCNSphere(radius: 0.01))
        node.worldPosition = SCNVector3(x: 0, y: 10, z: 0)
        node.geometry?.materials.first?.diffuse.contents = UIColor.orange
        return node
    }()
    
    var BCNode: SCNNode = {
        let node = SCNNode(geometry: SCNSphere(radius: 0.01))
        node.worldPosition = SCNVector3(x: 0, y: 10, z: 0)
        node.geometry?.materials.first?.diffuse.contents = UIColor.orange
        return node
    }()
    
    var LRLineNode:SCNNode?
    var TBLineNode:SCNNode?
    
    var bgNode: SCNNode = {
        let node = SCNNode(geometry: SCNPlane(width: 100, height: 100))
        node.worldPosition = SCNVector3(x: 0, y: 10, z: 0)
        node.geometry?.materials.first?.diffuse.contents = UIColor.orange.withAlphaComponent(0.3)
        return node
    }()
    
    var hitObjectDistanceFromCamera:Float?
    
    var plane:SCNNode?


    // MARK: - View Life Cycle

    /// - Tag: StartARSession
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

//        setupModel()
        setupAR()
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.vertical]
        sceneView.session.run(configuration)

        sceneView.session.delegate = self
        UIApplication.shared.isIdleTimerDisabled = true
        coachingOverlay.goal = .verticalPlane
        coachingOverlay.activatesAutomatically = true
        coachingOverlay.session = sceneView.session
        coachingOverlay.delegate = self

        // Viewとして扱う
        coachingOverlay.frame = sceneView.bounds
        sceneView.addSubview(coachingOverlay)
        view.addSubview(distanceFromDeviceLabel)
        distanceFromDeviceLabel.frame = CGRect(x: 0, y: view.bounds.maxY - 200, width: view.bounds.width, height: 200)
        distanceFromDeviceLabel.textAlignment = .center
        distanceFromDeviceLabel.text = "distance"
        
        view.addSubview(widthLabel)
        view.addSubview(heightLabel)
        sceneView.addSubview(classLabel)
        widthLabel.textAlignment = .center
        heightLabel.textAlignment = .center
        classLabel.textAlignment = .center
        classLabel.numberOfLines = 3
        
        widthLabel.font = .systemFont(ofSize: 24, weight: .heavy)
        heightLabel.font = .systemFont(ofSize: 24, weight: .heavy)
        classLabel.font = .systemFont(ofSize: 24, weight: .heavy)
        widthLabel.textColor = .red
        heightLabel.textColor = .red
        classLabel.textColor = .red

        widthLabel.backgroundColor = .orange.withAlphaComponent(0.5)
        heightLabel.backgroundColor = .orange.withAlphaComponent(0.5)
        classLabel.backgroundColor = .orange.withAlphaComponent(0.5)
        
        classLabel.frame = CGRect(x: 0, y: 0, width: view.bounds.width, height: view.bounds.height / 3)
        classLabel.isHidden = true
    }
    
    func setupModel() {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let model = try yolov8s().model
                let vnModel = try VNCoreMLModel(for: model)
                self.yoloRequest = VNCoreMLRequest(model: vnModel)
                self.yoloRequest.imageCropAndScaleOption = .scaleFit
            } catch let error {
                fatalError("mlmodel error.")
            }
        }
    }
    
    func detectObject(pixelBuffer:CVPixelBuffer, frame:ARFrame) {
        guard let yoloRequest = yoloRequest else {return}
        frameRect = sceneView.bounds
        var ciImage = CIImage(cvPixelBuffer: pixelBuffer, options: [:])
        if UIDevice.current.orientation.isPortrait {
            ciImage = ciImage.oriented(.right)
        }

        var cropped:CIImage
        if self.view.window!.windowScene!.interfaceOrientation.rawValue == 1 {

            let aspect =  frameRect!.width / frameRect!.height
            let estimateWidth = ciImage.extent.height * aspect
            
            cropped = ciImage.cropped(to: CGRect(
                x: ciImage.extent.width / 2 - estimateWidth / 2,
                y: 0,
                width: estimateWidth,
                height: ciImage.extent.height)
            )
        } else {
            ciImage = ciImage.oriented(.left)

            let aspect =  frameRect!.height / frameRect!.width
            let estimateHeight = ciImage.extent.width * aspect
            cropped = ciImage.cropped(to: CGRect(
                x: 0,
                y: ciImage.extent.height / 2 - estimateHeight / 2,
                width: ciImage.extent.width,
                height: estimateHeight)
            )
        }

        let handler = VNImageRequestHandler(ciImage: cropped, options: [:])
        do {
            try handler.perform([yoloRequest])
//            guard let results = yoloRequest.results else { return }
            guard let result = yoloRequest.results?.first as? VNRecognizedObjectObservation else {
                hideResult()
                return
            }
            let topLeft = CGPoint(x: result.boundingBox.minX, y: 1 - result.boundingBox.maxY)
            let topRight = CGPoint(x: result.boundingBox.maxX, y: 1 - result.boundingBox.maxY)
            let bottomLeft = CGPoint(x: result.boundingBox.minX, y: 1 - result.boundingBox.minY)
            let bottomRight = CGPoint(x: result.boundingBox.maxX, y: 1 - result.boundingBox.minY)
            
            let deNormalizedTopLeft = VNImagePointForNormalizedPoint(topLeft, Int(frameRect!.width), Int(frameRect!.height))
            let deNormalizedTopRight = VNImagePointForNormalizedPoint(topRight, Int(frameRect!.width), Int(frameRect!.height))
            let deNormalizedBottomLeft = VNImagePointForNormalizedPoint(bottomLeft, Int(frameRect!.width), Int(frameRect!.height))
            let deNormalizedBottomRight = VNImagePointForNormalizedPoint(bottomRight, Int(frameRect!.width), Int(frameRect!.height))
            guard let surfaceCenter = getPointOnSurface(cgPoint: view.center) else {
                hitObjectDistanceFromCamera = nil
                return
            }
            let transform = frame.camera.transform.columns.3
            let devicePosition = simd_float3(x: transform.x, y: transform.y, z: transform.z)
            let distanceToSurface = distance(devicePosition,surfaceCenter)
            hitObjectDistanceFromCamera = -distanceToSurface
            
            let infrontOfCamera = SCNVector3(x: 0, y: 0, z: -distanceToSurface)

            guard let cameraNode = sceneView.pointOfView else { return }
            let pointInWorld = cameraNode.convertPosition(infrontOfCamera, to: nil)

            var screenPos = sceneView.projectPoint(pointInWorld)

            screenPos.x = Float(deNormalizedTopLeft.x)
            screenPos.y = Float(deNormalizedTopLeft.y)

            TLNode.worldPosition = sceneView.unprojectPoint(screenPos)
            screenPos.x = Float(deNormalizedTopRight.x)
            screenPos.y = Float(deNormalizedTopRight.y)

            TRNode.worldPosition = sceneView.unprojectPoint(screenPos)

            screenPos.x = Float(deNormalizedBottomLeft.x)
            screenPos.y = Float(deNormalizedBottomLeft.y)

            BLNode.worldPosition = sceneView.unprojectPoint(screenPos)

            screenPos.x = Float(deNormalizedBottomRight.x)
            screenPos.y = Float(deNormalizedBottomRight.y)

            BRNode.worldPosition = sceneView.unprojectPoint(screenPos)

            let leftCenterCoordinate = SIMD3(x: (BLNode.simdWorldPosition.x+TLNode.simdWorldPosition.x)/2, y: (BLNode.simdWorldPosition.y+TLNode.simdWorldPosition.y)/2, z: (BLNode.simdWorldPosition.z+TLNode.simdWorldPosition.z)/2)

            let rightCenterCoordinate = SIMD3(x: (BRNode.simdWorldPosition.x+TRNode.simdWorldPosition.x)/2, y: (BRNode.simdWorldPosition.y+TRNode.simdWorldPosition.y)/2, z: (BRNode.simdWorldPosition.z+TRNode.simdWorldPosition.z)/2)

            let topCenterCoordinate = SIMD3(x: (TLNode.simdWorldPosition.x+TRNode.simdWorldPosition.x)/2, y: (TLNode.simdWorldPosition.y+TRNode.simdWorldPosition.y)/2, z: (TLNode.simdWorldPosition.z+TRNode.simdWorldPosition.z)/2)

            let bottomCenterCoordinate = SIMD3(x: (BLNode.simdWorldPosition.x+BRNode.simdWorldPosition.x)/2, y: (BLNode.simdWorldPosition.y+BRNode.simdWorldPosition.y)/2, z: (BLNode.simdWorldPosition.z+BRNode.simdWorldPosition.z)/2)
            LCNode.simdWorldPosition = leftCenterCoordinate
            RCNode.simdWorldPosition = rightCenterCoordinate
            TCNode.simdWorldPosition = topCenterCoordinate
            BCNode.simdWorldPosition = bottomCenterCoordinate

            let LRDistance = distance(LCNode.simdWorldPosition, RCNode.simdWorldPosition)
            let LRcmDistance = floor(LRDistance * 1000) / 10
            let TBDistance = distance(TCNode.simdWorldPosition, BCNode.simdWorldPosition)
            let TBcmDistance = floor(TBDistance * 1000) / 10

            if self.LRLineNode != nil {
                self.LRLineNode?.removeFromParentNode()
            }
            let LRLineNode = lineBetweenNodes(
                positionA: LCNode.worldPosition,
                positionB: RCNode.worldPosition,
                inScene: sceneView.scene
            )
            if self.TBLineNode != nil {
                self.TBLineNode?.removeFromParentNode()
            }

            let TBLineNode = lineBetweenNodes(
                positionA: TCNode.worldPosition,
                positionB: BCNode.worldPosition,
                inScene: sceneView.scene
            )
            LRLineNode.geometry?.materials.first?.readsFromDepthBuffer = false
            TBLineNode.geometry?.materials.first?.readsFromDepthBuffer = false

            sceneView.scene.rootNode.addChildNode(LRLineNode)
            sceneView.scene.rootNode.addChildNode(TBLineNode)

            self.LRLineNode = LRLineNode
            self.TBLineNode = TBLineNode
            showResult()
            DispatchQueue.main.async {
//                self.classLabel.isHidden = false
                self.classLabel.frame = CGRect(x: deNormalizedTopLeft.x, y: deNormalizedTopLeft.y, width: deNormalizedTopRight.x-deNormalizedTopLeft.x, height: deNormalizedBottomLeft.y-deNormalizedTopLeft.y)
                self.classLabel.text = "\(result.labels.first!.identifier)\nw: \(LRcmDistance) cm\nh: \(TBcmDistance) cm"
            }

            print("")
        } catch let error {
            hideResult()
//            DispatchQueue.main.async {
//                self.classLabel.isHidden = true
//            }
            print(error)
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        // Pause the view's AR session.
        sceneView.session.pause()
    }

    // MARK: - ARSCNViewDelegate
    
    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        guard let hitObjectDistanceFromCamera = hitObjectDistanceFromCamera else {
            bgNode.isHidden = true
            return
        }
        bgNode.isHidden = true
        let position = SCNVector3(x: 0, y: 0, z: hitObjectDistanceFromCamera) // ノードの位置は、左右：0m 上下：0m　奥に50cm
        if let camera = sceneView.pointOfView {
            bgNode.position = camera.convertPosition(position, to: nil) // カメラ位置からの偏差で求めた位置
            bgNode.eulerAngles = camera.eulerAngles  // カメラのオイラー角と同じにする
//            print(bgNode.simdTransform)
        }

    }
    
    /// - Tag: PlaceARContent
    func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
        // Place content only for anchors found by plane detection.
        guard let planeAnchor = anchor as? ARPlaneAnchor else { return }
        
        // Create a custom object to visualize the plane geometry and extent.
//        let plane = Plane(anchor: planeAnchor, in: sceneView)
        
        // Add the visualization to the ARKit-managed node so that it tracks
        // changes in the plane anchor as plane estimation continues.
//        node.addChildNode(plane)
    }

    /// - Tag: UpdateARContent
    func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
    }

    
    
    // MARK: - ARSessionDelegate

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        
        let pixelBuffer = frame.capturedImage
        guard let surfaceCenter = getPointOnSurface(cgPoint: view.center) else {
            hitObjectDistanceFromCamera = nil
            return
        }
        let transform = frame.camera.transform.columns.3
        let devicePosition = simd_float3(x: transform.x, y: transform.y, z: transform.z)
        let distanceToSurface = distance(devicePosition,surfaceCenter)
        hitObjectDistanceFromCamera = -distanceToSurface
        DispatchQueue.main.async {
            self.distanceFromDeviceLabel.isHidden = false
            self.distanceFromDeviceLabel.text = String(distanceToSurface)
        }
    }
    
    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        guard let frame = session.currentFrame else { return }
        updateSessionInfoLabel(for: frame, trackingState: frame.camera.trackingState)
    }

    func session(_ session: ARSession, didRemove anchors: [ARAnchor]) {
        guard let frame = session.currentFrame else { return }
        updateSessionInfoLabel(for: frame, trackingState: frame.camera.trackingState)
    }

    func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        updateSessionInfoLabel(for: session.currentFrame!, trackingState: camera.trackingState)
    }

    // MARK: - ARSessionObserver

    func sessionWasInterrupted(_ session: ARSession) {
        // Inform the user that the session has been interrupted, for example, by presenting an overlay.
        sessionInfoLabel.text = "Session was interrupted"
    }

    func sessionInterruptionEnded(_ session: ARSession) {
        // Reset tracking and/or remove existing anchors if consistent tracking is required.
        sessionInfoLabel.text = "Session interruption ended"
        resetTracking()
    }
    
    func session(_ session: ARSession, didFailWithError error: Error) {
        sessionInfoLabel.text = "Session failed: \(error.localizedDescription)"
        guard error is ARError else { return }
        
        let errorWithInfo = error as NSError
        let messages = [
            errorWithInfo.localizedDescription,
            errorWithInfo.localizedFailureReason,
            errorWithInfo.localizedRecoverySuggestion
        ]
        
        // Remove optional error messages.
        let errorMessage = messages.compactMap({ $0 }).joined(separator: "\n")
        
        DispatchQueue.main.async {
            // Present an alert informing about the error that has occurred.
            let alertController = UIAlertController(title: "The AR session failed.", message: errorMessage, preferredStyle: .alert)
            let restartAction = UIAlertAction(title: "Restart Session", style: .default) { _ in
                alertController.dismiss(animated: true, completion: nil)
                self.resetTracking()
            }
            alertController.addAction(restartAction)
            self.present(alertController, animated: true, completion: nil)
        }
    }

    // MARK: - Private methods

    private func updateSessionInfoLabel(for frame: ARFrame, trackingState: ARCamera.TrackingState) {
        // Update the UI to provide feedback on the state of the AR experience.
        let message: String

        switch trackingState {
        case .normal where frame.anchors.isEmpty:
            // No planes detected; provide instructions for this app's AR interactions.
            message = "Move the device around to detect horizontal and vertical surfaces."
            
        case .notAvailable:
            message = "Tracking unavailable."
            
        case .limited(.excessiveMotion):
            message = "Tracking limited - Move the device more slowly."
            
        case .limited(.insufficientFeatures):
            message = "Tracking limited - Point the device at an area with visible surface detail, or improve lighting conditions."
            
        case .limited(.initializing):
            message = "Initializing AR session."
            
        default:
            // No feedback needed when tracking is normal and planes are visible.
            // (Nor when in unreachable limited-tracking states.)
            message = ""

        }

        sessionInfoLabel.text = message
        sessionInfoView.isHidden = message.isEmpty
    }

    private func resetTracking() {
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal, .vertical]
        sceneView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
    }
    
    func drawRectsOnImage(_ detections: [Detection], _ ciImage: CIImage) -> UIImage? {
        let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent)!
        let size = ciImage.extent.size
        guard let cgContext = CGContext(data: nil,
                                        width: Int(size.width),
                                        height: Int(size.height),
                                        bitsPerComponent: 8,
                                        bytesPerRow: 4 * Int(size.width),
                                        space: CGColorSpaceCreateDeviceRGB(),
                                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        cgContext.draw(cgImage, in: CGRect(origin: .zero, size: size))
        for detection in detections {
            let invertedBox = CGRect(x: detection.box.minX * size.width, y: size.height - detection.box.maxY * size.height, width: detection.box.width * size.width, height: detection.box.height * size.height)
            if let labelText = detection.label {
                cgContext.textMatrix = .identity
                
                let text = "\(labelText) : \(round(detection.confidence*100))"
                
                let textRect  = CGRect(x: invertedBox.minX + size.width * 0.01, y: invertedBox.minY - size.width * 0.01, width: invertedBox.width, height: invertedBox.height)
                let textStyle = NSMutableParagraphStyle.default.mutableCopy() as! NSMutableParagraphStyle
                
                let textFontAttributes = [
                    NSAttributedString.Key.font: UIFont.systemFont(ofSize: textRect.width * 0.1, weight: .bold),
                    NSAttributedString.Key.foregroundColor: detection.color,
                    NSAttributedString.Key.paragraphStyle: textStyle
                ]
                
                cgContext.saveGState()
                defer { cgContext.restoreGState() }
                let astr = NSAttributedString(string: text, attributes: textFontAttributes)
                let setter = CTFramesetterCreateWithAttributedString(astr)
                let path = CGPath(rect: textRect, transform: nil)
                
                let frame = CTFramesetterCreateFrame(setter, CFRange(), path, nil)
                cgContext.textMatrix = CGAffineTransform.identity
                CTFrameDraw(frame, cgContext)
                
                cgContext.setStrokeColor(detection.color.cgColor)
                cgContext.setLineWidth(9)
                cgContext.stroke(invertedBox)
            }
        }
        guard let newImage = cgContext.makeImage() else { return nil }
        return UIImage(ciImage: CIImage(cgImage: newImage))
    }

    func showResult() {
        TRNode.isHidden = false
        TLNode.isHidden = false
        BRNode.isHidden = false
        BLNode.isHidden = false
        LCNode.isHidden = false
        RCNode.isHidden = false
        TCNode.isHidden = false
        BCNode.isHidden = false
        LRLineNode?.isHidden = false
        TBLineNode?.isHidden = false
        DispatchQueue.main.async {
            self.classLabel.isHidden = false
        }
    }
    func hideResult() {
        TRNode.isHidden = true
        TLNode.isHidden = true
        BRNode.isHidden = true
        BLNode.isHidden = true
        LCNode.isHidden = true
        RCNode.isHidden = true
        TCNode.isHidden = true
        BCNode.isHidden = true
        LRLineNode?.isHidden = true
        TBLineNode?.isHidden = true
        DispatchQueue.main.async {
            self.classLabel.isHidden = true
        }
    }
}

extension CGPoint {
    func toVector(image: CIImage) -> CIVector {
        return CIVector(x: x, y: image.extent.height-y)
    }
}
extension CIImage {
    func resize(as size: CGSize) -> CIImage {
        let selfSize = extent.size
        let transform = CGAffineTransform(scaleX: size.width / selfSize.width, y: size.height / selfSize.height)
        return transformed(by: transform)
    }
}
struct Detection {
    let box:CGRect
    let confidence:Float
    let label:String?
    let color:UIColor
}
