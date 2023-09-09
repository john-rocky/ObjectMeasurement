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

        setupAR()
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.vertical]
        sceneView.session.run(configuration)

        sceneView.session.delegate = self
        UIApplication.shared.isIdleTimerDisabled = true
//        coachingOverlay.goal = .verticalPlane
//        coachingOverlay.activatesAutomatically = true
//        coachingOverlay.session = sceneView.session
//        coachingOverlay.delegate = self
//
//        // Viewとして扱う
//        coachingOverlay.frame = sceneView.bounds
//        sceneView.addSubview(coachingOverlay)
        view.addSubview(distanceFromDeviceLabel)
        distanceFromDeviceLabel.frame = CGRect(x: 0, y: view.bounds.maxY - 300, width: view.bounds.width, height: 300)
        distanceFromDeviceLabel.numberOfLines = 2
        distanceFromDeviceLabel.textAlignment = .center
        distanceFromDeviceLabel.text = "distance"
        
        view.addSubview(recBotton)
        recBotton.frame = CGRect(x: view.bounds.maxX - 200, y: 20, width: 200, height: 100)
        recBotton.setTitle("録画", for: .normal)
        recBotton.addTarget(self, action: #selector(recordVideo), for: .touchUpInside)

    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        // Pause the view's AR session.
        sceneView.session.pause()
    }
    
    @objc func recordVideo() {
        if !recording {
            recording = true
            recBotton.setTitle("停止", for: .normal)
            recorder = SceneRecorder(setting: SceneRecorder.SceneRecorderSetting(fps: 10, videoSize: sceneView.bounds.size, watermark: nil, scene: sceneView))
            recorder!.start()
        } else {
            recBotton.setTitle("録画", for: .normal)
            recorder!.stop { url in
                self.saveVideoToPhotoLibrary(at: url) { success, error in
                    if success {
                        print("Video saved to photo library successfully!")
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
        }

    }
    
    // MARK: - ARSessionDelegate

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        let roll = round(frame.camera.eulerAngles.y * 180 / .pi * 100) / 100
        
//        let pixelBuffer = frame.capturedImage
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
            self.distanceFromDeviceLabel.text = "距離: \(round(distanceToSurface*10000)/100) cm\n角度 \(roll)°"
        }

        let infrontOfCamera = SCNVector3(x: 0, y: 0, z: -distanceToSurface)
        guard let cameraNode = sceneView.pointOfView else { return }
        let pointInWorld = cameraNode.convertPosition(infrontOfCamera, to: nil)

        var screenPos = sceneView.projectPoint(pointInWorld)

        screenPos.x = Float(view.center.x)
        screenPos.y = Float(view.center.y)
        TLNode.isHidden = false
        TLNode.worldPosition = sceneView.unprojectPoint(screenPos)
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
struct Detection {
    let box:CGRect
    let confidence:Float
    let label:String?
    let color:UIColor
}
