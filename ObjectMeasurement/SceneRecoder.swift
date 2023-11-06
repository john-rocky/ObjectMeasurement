//
//  SceneRecoder.swift
//  ObjectMeasurement
//
//  Created by 間嶋大輔 on 2023/09/08.
//

import ARKit
import Foundation
import VideoToolbox

protocol SceneRecorderDelegate: NSObjectProtocol {
    func sceneRecorder(_ recorder: SceneRecorder, didFailFor error: Error)
}

class SceneRecorder {
    enum SceneRecorderError: Error {
        case assetWriterInitFailed
        case mediaMergingFailed
    }

    struct SceneRecorderSetting {
        let fps: Int
        let videoSize: CGSize
        let watermark: UIImage?
        let scene: ARSCNView
    }

    weak var delegate: SceneRecorderDelegate?
    private let frameQueue = DispatchQueue(label: "jp.co.Agencia.SceneRecorder")
    private var isRendering = false
    private var assetWriterInput: AVAssetWriterInput!
    private var assetWriter: AVAssetWriter?
    private var audioRecorder: AVAudioRecorder?
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor!
    private let setting: SceneRecorderSetting

    init(setting: SceneRecorderSetting) {
        self.setting = setting
    }

    func start() {
        isRendering = false
        assetWriter = nil
        setupAudioRecording()
        setupVideoRecording()

        guard let assetWriter = assetWriter else {
            delegate?.sceneRecorder(self, didFailFor: SceneRecorderError.assetWriterInitFailed)
            return
        }
        recordVideo(from: pixelBufferAdaptor, assetWriterInput: assetWriterInput, assetWriter: assetWriter, setting: setting)
        audioRecorder?.record()
    }

    func stop(_ completion: @escaping (_: URL) -> () ) {
        guard !isRendering else { return }

        isRendering = true
        guard let assetWriter = assetWriter else {
            delegate?.sceneRecorder(self, didFailFor: SceneRecorderError.assetWriterInitFailed)
            return
        }

        audioRecorder?.stop()
        assetWriterInput.markAsFinished()
        assetWriter.finishWriting { [weak self] in
//            guard let self = self else {
//                return
//            }

            if let audioUrl = self?.audioRecorder?.url {
                self?.mergeVideoAndAudio(videoUrl: assetWriter.outputURL, audioUrl: audioUrl, setting: self!.setting, completion: completion)
            } else {
                completion(assetWriter.outputURL)
            }
        }
    }

    // MARK: - Setup

    private func setupAudioRecording() {
        try? AVAudioSession.sharedInstance().setCategory(.playAndRecord, options: [.defaultToSpeaker])
        try? AVAudioSession.sharedInstance().setActive(true)
        guard let availableInputs = AVAudioSession.sharedInstance().availableInputs,
              let builtInMicInput = availableInputs.first(where: { $0.portType == .builtInMic }) else {
            print("The device must have a built-in microphone.")
            return
        }

        // Make the built-in microphone input the preferred input.
        try? AVAudioSession.sharedInstance().setPreferredInput(builtInMicInput)

        AVAudioSession.sharedInstance().requestRecordPermission { allowed in
            if allowed {
                let settings =
                    [
                        AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                        AVSampleRateKey: 44100,
                        AVNumberOfChannelsKey: 2,
                        AVEncoderAudioQualityKey:AVAudioQuality.high.rawValue
                    ]
                let cacheDir = try! FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                let url: URL = cacheDir.appendingPathComponent("\(UUID().uuidString).m4a")
                self.audioRecorder = try? AVAudioRecorder(url: url, settings: settings)
            }
        }
    }

    private func setupVideoRecording() {
        let videoSize = setting.videoSize
        guard let pixelBuffer = setting.scene.session.currentFrame?.capturedImage else {
            fatalError()
        }
            
           
        let width = CVPixelBufferGetWidth(pixelBuffer)
            
           
        let height = CVPixelBufferGetHeight(pixelBuffer)

        // AVAssetWriterInput
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: videoSize.width,
            AVVideoHeightKey: videoSize.height
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        self.assetWriterInput = input

        // AVAssetWriter
        let cacheDir = try! FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let url: URL = cacheDir.appendingPathComponent("\(UUID().uuidString).m4v")
        let assetWriter = try? AVAssetWriter(outputURL: url, fileType: .m4v)
        assetWriter?.add(input)
        self.assetWriter = assetWriter

        // AVAssetWriterInputPixelBufferAdaptor
        let attributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: NSNumber(value: kCVPixelFormatType_32ARGB),
            kCVPixelBufferWidthKey as String: videoSize.width,
            kCVPixelBufferHeightKey as String: videoSize.height
        ]
        let pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: attributes
        )
        self.pixelBufferAdaptor = pixelBufferAdaptor
    }

    // MARK: - Record

    private func recordVideo(from adaptor: AVAssetWriterInputPixelBufferAdaptor, assetWriterInput: AVAssetWriterInput, assetWriter: AVAssetWriter, setting: SceneRecorderSetting) {
        let intervalDuration = CFTimeInterval(1.0 / Double(setting.fps))
        let timescale: Float = 600
        let frameDuration = CMTimeMake(
            value: Int64( floor(timescale / Float(setting.fps)) ),
            timescale: Int32(timescale)
        )
        var frameNumber = 0
        assetWriter.startWriting()
        assetWriter.startSession(atSourceTime: .zero)
        var startTime:TimeInterval = 0
        assetWriterInput.requestMediaDataWhenReady(on: frameQueue) {
            if startTime == 0 {
                guard let start = setting.scene.session.currentFrame?.timestamp else { fatalError() }
                startTime = start
            }
            guard !self.isRendering else {return}
            let snapshotTime = CFTimeInterval(intervalDuration * CFTimeInterval(frameNumber))
            if assetWriterInput.isReadyForMoreMediaData, let pool = adaptor.pixelBufferPool, Date().timeIntervalSince1970 > snapshotTime {
                guard let frame = self.setting.scene.session.currentFrame else {return}
                let pixelBuffer = frame.capturedImage
                
                let time = CMTime(seconds: frame.timestamp-startTime, preferredTimescale: Int32(60))
//                guard let croppedCGImage = setting.scene.snapshot().cgImage?.cropping(to: CGRect(origin: .zero, size: setting.videoSize)) else {
//                    return
//                }
                // Watermark
//                let image: UIImage
//                if let watermark = setting.watermark {
//                    image = SceneRecorder.drawWatermark(watermark, on: UIImage(cgImage: croppedCGImage))
//                } else {
//                    image = UIImage(cgImage: croppedCGImage)
//                }
                print(time)
                let presentationTime = CMTimeMultiply(frameDuration, multiplier:  Int32(frameNumber))
                let image = self.convertCVPixelBufferToCGImage(pixelBuffer)
                let rotated = SceneRecorder.pixelBuffer(withSize: setting.videoSize, fromImage: image!, usingBufferPool: pool)
//                let pixelBuffer = SceneRecorder.pixelBuffer(withSize: setting.videoSize, fromImage: image, usingBufferPool: pool)
                adaptor.append(rotated, withPresentationTime: time)
                frameNumber += 1
            } else {
                print("WRONG")
            }
        }
    }
    
    func convertCVPixelBufferToCGImage(_ pixelBuffer: CVPixelBuffer) -> CGImage? {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let image = CIImage(cvPixelBuffer: pixelBuffer).oriented(.right)
        let cgImage = context.createCGImage(image, from: image.extent)
//        var cgImage: CGImage?
//        VTCreateCGImageFromCVPixelBuffer(pixelBuffer, options: nil, imageOut: &cgImage)
        
        return cgImage
    }


    let context = CIContext()
    // MARK: - Merge

    private func mergeVideoAndAudio(videoUrl: URL, audioUrl: URL, setting: SceneRecorderSetting, completion: @escaping (URL) -> Void) {

        let mixComposition : AVMutableComposition = AVMutableComposition()
        var mutableCompositionVideoTrack : [AVMutableCompositionTrack] = []
        var mutableCompositionAudioTrack : [AVMutableCompositionTrack] = []
        let totalVideoCompositionInstruction : AVMutableVideoCompositionInstruction = AVMutableVideoCompositionInstruction()

        let videoAsset = AVAsset(url: videoUrl)
        let audioAsset = AVAsset(url: audioUrl)
        mutableCompositionVideoTrack.append(mixComposition.addMutableTrack(withMediaType: AVMediaType.video, preferredTrackID: kCMPersistentTrackID_Invalid)!)
        mutableCompositionAudioTrack.append(mixComposition.addMutableTrack(withMediaType: AVMediaType.audio, preferredTrackID: kCMPersistentTrackID_Invalid)!)

        guard let videoAssetTrack = videoAsset.tracks(withMediaType: AVMediaType.video).first,
           let audioAssetTrack = audioAsset.tracks(withMediaType: AVMediaType.audio).first else {
            delegate?.sceneRecorder(self, didFailFor: SceneRecorderError.mediaMergingFailed)
            return
        }
        do {
            try mutableCompositionVideoTrack.first?.insertTimeRange(CMTimeRangeMake(start: CMTime.zero, duration: videoAssetTrack.timeRange.duration), of: videoAssetTrack, at: CMTime.zero)
            try mutableCompositionAudioTrack.first?.insertTimeRange(CMTimeRangeMake(start: CMTime.zero, duration: videoAssetTrack.timeRange.duration), of: audioAssetTrack, at: CMTime.zero)

        } catch {
            delegate?.sceneRecorder(self, didFailFor: SceneRecorderError.mediaMergingFailed)
        }

        totalVideoCompositionInstruction.timeRange = CMTimeRangeMake(start: CMTime.zero,duration: videoAssetTrack.timeRange.duration )

        let mutableVideoComposition : AVMutableVideoComposition = AVMutableVideoComposition()
        mutableVideoComposition.frameDuration = CMTimeMake(value: 1, timescale: Int32(setting.fps))

        mutableVideoComposition.renderSize = setting.videoSize

        let cacheDir = try! FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let url = cacheDir.appendingPathComponent("\(UUID().uuidString).m4v")
        let savePathUrl = url

        let assetExport: AVAssetExportSession = AVAssetExportSession(asset: mixComposition, presetName: AVAssetExportPresetHighestQuality)!
        assetExport.outputFileType = AVFileType.mp4
        assetExport.outputURL = savePathUrl
        assetExport.shouldOptimizeForNetworkUse = true

        assetExport.exportAsynchronously {
            switch assetExport.status {
            case .completed:
                completion(savePathUrl)
            default:
                self.delegate?.sceneRecorder(self, didFailFor: SceneRecorderError.mediaMergingFailed)
            }
        }
    }

    // MARK: - Class Function

    private class func pixelBuffer(withSize size: CGSize, fromImage image: CGImage, usingBufferPool pool: CVPixelBufferPool) -> CVPixelBuffer {

        var pixelBufferOut: CVPixelBuffer?

        CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pixelBufferOut)

        let pixelBuffer = pixelBufferOut!

        CVPixelBufferLockBaseAddress(pixelBuffer, CVPixelBufferLockFlags.readOnly)

        let data = CVPixelBufferGetBaseAddress(pixelBuffer)
        let context = CGContext(
            data: data,
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: Int(8),
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
        )
        context?.clear(CGRect(x: 0, y: 0, width: size.width, height: size.height))
        context?.draw(image, in: CGRect(x: 0, y: 0, width: size.width, height: size.height))

        CVPixelBufferUnlockBaseAddress(pixelBuffer, CVPixelBufferLockFlags.readOnly)

        return pixelBuffer
    }

    private class func drawWatermark(_ watermark: UIImage, on image: UIImage) -> UIImage {
        let imageSize = image.size
        let watermarkSize = CGSize(width: watermark.size.width * UIScreen.main.scale, height: watermark.size.height * UIScreen.main.scale)
        let imageRect = CGRect(x: 0, y: 0, width: imageSize.width, height: imageSize.height)
        let watermarkRect = CGRect(x: (imageSize.width - watermarkSize.width) / 2, y: 88, width: watermarkSize.width, height: watermarkSize.height)

        UIGraphicsBeginImageContextWithOptions(imageSize, false, image.scale);
        image.draw(in: imageRect)
        watermark.draw(in: watermarkRect)
        let maybeResult = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        guard let result = maybeResult else {
            assert(false, "Unable to draw a watermark on the image")
            return image
        }
        return result
    }
    
    

    func rotatePixelBuffer(_ pixelBuffer: CVPixelBuffer) -> CVPixelBuffer? {
        let image = CIImage(cvPixelBuffer: pixelBuffer)
        
        // 90度回転するアフィン変換を設定
        let rotationTransform = CGAffineTransform(rotationAngle: .pi / 2.0)
        let outputImage = image.transformed(by: rotationTransform)
        
        // 回転後の画像を新しいピクセルバッファに書き込む
        var newPixelBuffer: CVPixelBuffer?
        let attrs = [
            kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue,
            kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue
        ] as CFDictionary
        let status = CVPixelBufferCreate(nil, Int(outputImage.extent.width), Int(outputImage.extent.height), kCVPixelFormatType_32ARGB, attrs, &newPixelBuffer)
        
        if status == kCVReturnSuccess {
            let ciContext = CIContext()
            ciContext.render(outputImage, to: newPixelBuffer!)
            return newPixelBuffer
        }
        
        return nil
    }
}
