/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Main view controller for the AR experience.
*/

import UIKit
import SceneKit
import ARKit
import Vision
import Photos


class ViewController: UIViewController, ARSCNViewDelegate, ARSessionDelegate, ARCoachingOverlayViewDelegate {
    // MARK: - IBOutlets

    @IBOutlet weak var sessionInfoView: UIView!
    @IBOutlet weak var sessionInfoLabel: UILabel!
    @IBOutlet weak var sceneView: ARSCNView!
    let coachingOverlay = ARCoachingOverlayView()

    private var frameRect: CGRect?
    let ciContext = CIContext()

    var distanceFromDeviceLabel = UILabel()
    var modeButton = UIButton()
    var recBotton = UIButton()
    
    var recording = false
    var recorder: SceneRecorder?
    
    // Node
    var baseNode = SCNNode()
    
    // top left
    var TLNode: SCNNode = {
        let node = SCNNode(geometry: SCNSphere(radius: 0.01))
        node.worldPosition = SCNVector3(x: 0, y: 10, z: 0)
        node.geometry?.materials.first?.diffuse.contents = UIColor.orange
        return node
    }()

    var hitObjectDistanceFromCamera:Float?
    
    var raycastMode:mode = .sceneDepth
    enum mode {
        case sceneDepth
        case estimatedPlane
        case existingPlaneGeometry
        case existingPlaneInfinite
        case hitTest
    }

    // MARK: - View Life Cycle
    override func viewDidLoad() {
        super.viewDidLoad()
    }
    /// - Tag: StartARSession
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        setupAR()
        let configuration = ARWorldTrackingConfiguration()
        configuration.frameSemantics = .smoothedSceneDepth

        if #available(iOS 16.0, *) {
            if let hiResFormat = ARWorldTrackingConfiguration.recommendedVideoFormatFor4KResolution {
//                configuration.videoFormat = hiResFormat
            }
        } else {
            // Fallback on earlier versions
        }
        configuration.planeDetection = [.vertical,.horizontal]
        sceneView.session.run(configuration)

        sceneView.session.delegate = self
        UIApplication.shared.isIdleTimerDisabled = true
        coachingOverlay.goal = .verticalPlane
        coachingOverlay.activatesAutomatically = true
        coachingOverlay.session = sceneView.session
        coachingOverlay.delegate = self
///Users/majimadaisuke/Downloads
//        // Viewとして扱う
        coachingOverlay.frame = sceneView.bounds
//        sceneView.addSubview(coachingOverlay)
        view.addSubview(distanceFromDeviceLabel)
        distanceFromDeviceLabel.frame = CGRect(x: 0, y: view.bounds.maxY - 300, width: view.bounds.width, height: 300)
        distanceFromDeviceLabel.numberOfLines = 2
        distanceFromDeviceLabel.textAlignment = .center
//        distanceFromDeviceLabel.text = "distance"
        
        
//        view.addSubview(recBotton)
        recBotton.frame = CGRect(x: view.bounds.maxX - 200, y: 20, width: 200, height: 100)
        recBotton.setTitle("録画", for: .normal)
        recBotton.addTarget(self, action: #selector(recordVideo), for: .touchUpInside)

//        view.addSubview(modeButton)
        modeButton.frame = CGRect(x: view.bounds.maxX - 400, y: distanceFromDeviceLabel.frame.minY-100, width: 400, height: 100)
        modeButton.setTitle("sceneDepth", for: .normal)
        modeButton.titleLabel?.font = .systemFont(ofSize: 20, weight: .bold)
        modeButton.addTarget(self, action: #selector(modeChange), for: .touchUpInside)

        self.recorder = SceneRecorder(setting: SceneRecorder.SceneRecorderSetting(fps: 60, videoSize: self.sceneView.snapshot().size, watermark: nil, scene: self.sceneView))

    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        // Pause the view's AR session.
        sceneView.session.pause()
    }
    
    @objc func modeChange() {
        switch raycastMode {
        case .sceneDepth:
            self.raycastMode = .estimatedPlane
            modeButton.setTitle("estimatedPlane", for: .normal)
        case .estimatedPlane:
            self.raycastMode = .existingPlaneGeometry
            modeButton.setTitle("existingPlaneGeometry", for: .normal)
        case .existingPlaneGeometry:
            self.raycastMode = .existingPlaneInfinite
            modeButton.setTitle("existingPlaneInfinite", for: .normal)
        case .existingPlaneInfinite:
            self.raycastMode = .hitTest
            modeButton.setTitle("hitTest", for: .normal)
        case .hitTest:
            self.raycastMode = .sceneDepth
            modeButton.setTitle("sceneDepth", for: .normal)
        }
    }
    
    @objc func recordVideo() {
        if !recording {
            recording = true
            recBotton.setTitle("停止", for: .normal)
            self.recorder!.start()
        
        } else {
            recording = false
            recBotton.setTitle("録画", for: .normal)
            recorder!.stop { url in
                self.saveVideoToPhotoLibrary(at: url) { success, error in
                    if success {
                        print("Video saved to photo library successfully!")
                        DispatchQueue.main.async {
                            let alert = UIAlertController(title: "保存しました", message: "", preferredStyle: .actionSheet)
                            let ok = UIAlertAction(title:"ok", style: .default) { action in
                                alert.dismiss(animated: true)
                            }
                            alert.addAction(ok)
                            self.present(alert, animated: true)
                        }
                    } else {
                        print("Error saving video to photo library: \(error?.localizedDescription ?? "Unknown error")")
                    }
                }
            }
        }
    }

    func saveVideoToPhotoLibrary(at videoURL: URL, completion: @escaping (Bool, Error?) -> Void) {
        PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: videoURL)
        } completionHandler: { success, error in
            if success {
                completion(true, nil)
            } else {
                if let error = error {
                    print("Error saving video to photo library: \(error)")
                    completion(false, error)
                }
            }
        }
    }
    
    // MARK: - ARSessionDelegate
    
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        let image = CIImage(cvPixelBuffer: frame.capturedImage).oriented(.right)
        let roll = round(frame.camera.eulerAngles.y * 180 / .pi * 100) / 100
        var distanceToSurface:Float = 0
        var distText = "No data."
        if raycastMode == .sceneDepth {
            
            guard let sceneDepth = frame.smoothedSceneDepth ?? frame.sceneDepth else {
                print("Failed to acquire scene depth.")
                return
            }
            var pixelBuffer: CVPixelBuffer!
            pixelBuffer = sceneDepth.depthMap
            let ciImage = CIImage(cvPixelBuffer: pixelBuffer).oriented(.right)
            
            let width = CVPixelBufferGetWidth(pixelBuffer)
            let height = CVPixelBufferGetHeight(pixelBuffer)
            
            // 中央の座標を計算する
            let centerX = width / 2
            let centerY = height / 2
            CVPixelBufferLockBaseAddress(pixelBuffer, CVPixelBufferLockFlags(rawValue: 0))
            let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer)?.assumingMemoryBound(to: Float32.self)
            
            // Calculate the index for the specified pixel
            let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
            let pixelIndex = Int(centerY) * bytesPerRow / MemoryLayout<Float32>.stride + Int(centerX)
            
            // Access the depth value at the specified pixel
            let depthValue = baseAddress?[pixelIndex]
            
            // Unlock the pixel buffer
            CVPixelBufferUnlockBaseAddress(pixelBuffer, CVPixelBufferLockFlags(rawValue: 0))
            
            if let depthValue = depthValue {
                // Convert the depth value to distance in meters using scaling factor
                let scalingFactor = 0.01
                let distanceInMeters = Double(depthValue)
                distanceToSurface = Float(distanceInMeters)
                // Now 'distanceInMeters' contains the distance in meters at the specified pixel.
            }
        } else {
            
            //        let pixelBuffer = frame.capturedImage
            guard let surfaceCenter = getPointOnSurface(cgPoint: view.center) else {
                hitObjectDistanceFromCamera = nil
                return
            }
            let transform = frame.camera.transform.columns.3
            let devicePosition = simd_float3(x: transform.x, y: transform.y, z: transform.z)
            distanceToSurface = distance(devicePosition,surfaceCenter)
            
        }
//        distText = "距離: \(round(distanceToSurface*10000)/100) cm\n角度 \(roll)°"
//        DispatchQueue.main.async {
//            self.distanceFromDeviceLabel.isHidden = false
//            self.distanceFromDeviceLabel.text = distText
//        }
//
//        let infrontOfCamera = SCNVector3(x: 0, y: 0, z: -distanceToSurface)
//        guard let cameraNode = sceneView.pointOfView else { return }
//        let pointInWorld = cameraNode.convertPosition(infrontOfCamera, to: nil)
//
//        var screenPos = sceneView.projectPoint(pointInWorld)
//
//        screenPos.x = Float(view.center.x)
//        screenPos.y = Float(view.center.y)
//        TLNode.isHidden = false
//        TLNode.worldPosition = sceneView.unprojectPoint(screenPos)
        
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
