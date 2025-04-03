// File: CameraModel.swift
import SwiftUI
import AVFoundation
import Vision
import CoreImage
import CoreLocation
import SFaceCompare

extension UIImage {
    func fixedOrientation() -> UIImage? {
        if imageOrientation == .up { return self }
        UIGraphicsBeginImageContextWithOptions(size, false, scale)
        draw(in: CGRect(origin: .zero, size: size))
        let normalizedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return normalizedImage
    }
}

class CameraModel: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate, CLLocationManagerDelegate {
    let session = AVCaptureSession()
    @Published var faceObservations: [VNFaceObservation] = []
    @Published var lastCapturedImage: UIImage?
    
    private let videoOutput = AVCaptureVideoDataOutput()
    private var frameCounter = 0
    private let frameProcessingInterval = 2  // Process every 6th frame (~10 FPS if running at 60 FPS)
    private var currentDevice: AVCaptureDevice?
    
    // Location Manager
    private let locationManager = CLLocationManager()
    @Published var currentLocation: CLLocationCoordinate2D?
    
    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
    }

    func configure() {
        session.beginConfiguration()
        session.sessionPreset = .photo
        
        guard let device = AVCaptureDevice.default(for: .video) else {
            print("No camera available")
            session.commitConfiguration()
            return
        }
        currentDevice = device
        
        do {
            let input = try AVCaptureDeviceInput(device: device)
            if session.canAddInput(input) {
                session.addInput(input)
            }
        } catch {
            print("Error configuring camera: \(error)")
        }
        
        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
            let queue = DispatchQueue(label: "VideoOutputQueue")
            videoOutput.setSampleBufferDelegate(self, queue: queue)
            videoOutput.alwaysDiscardsLateVideoFrames = true
            if let connection = videoOutput.connection(with: .video) {
                connection.videoOrientation = .portrait
                connection.isVideoMirrored = (currentDevice?.position == .front)
            }
        }
        
        session.commitConfiguration()
    }
    
    func capturePhoto() {
        print("Capture photo command triggered")
    }
    
    func startFaceDetection() {
        DispatchQueue.main.async {
            self.faceObservations = []
        }
    }
    
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        frameCounter += 1
        if frameCounter % frameProcessingInterval != 0 { return }
        
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
              let device = currentDevice else { return }
        
        // Update last captured image
        if let image = imageFromSampleBuffer(sampleBuffer: sampleBuffer) {
            DispatchQueue.main.async {
                self.lastCapturedImage = image
            }
        }
        
        let orientation: CGImagePropertyOrientation = (device.position == .front) ? .leftMirrored : .right
        
        let request = VNDetectFaceRectanglesRequest { [weak self] request, error in
            if let observations = request.results as? [VNFaceObservation] {
                DispatchQueue.main.async {
                    self?.faceObservations = observations
                }
            }
        }
        
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: orientation, options: [:])
        do {
            try handler.perform([request])
        } catch {
            print("Face detection failed: \(error)")
        }
    }
    
    // Capture and save face images using rotated bounding box coordinates.
    func captureAndSaveFaces() {
        guard let image = lastCapturedImage,
              let fixedImage = image.fixedOrientation(),
              let cgImage = fixedImage.cgImage else { return }
        
        // Determine image dimensions in pixels.
        let imageWidth = fixedImage.size.width * fixedImage.scale
        let imageHeight = fixedImage.size.height * fixedImage.scale
        
        let tempDir = NSTemporaryDirectory()
        let captureTime = Date()
        let location = currentLocation ?? CLLocationCoordinate2D(latitude: 0, longitude: 0)
        
        for (index, face) in faceObservations.enumerated() {
            // Convert normalized bounding box (origin at bottom-left) to pixel coordinates.
            var x = face.boundingBox.origin.y * imageWidth
            var y = (1 - face.boundingBox.origin.x - face.boundingBox.height) * imageHeight
            let width = face.boundingBox.width * imageWidth
            let height = face.boundingBox.height * imageHeight
            
            // Adjust for mirrored video if needed.
            if let connection = videoOutput.connection(with: .video), connection.isVideoMirrored {
                x = imageWidth - x - width
                
            }
            x = imageWidth - x - width
            let cropRect = CGRect(x: x - (width * 0.5), y: y - (height * 0.5), width: width * 2, height: height * 2)
                .intersection(CGRect(x: 0, y: 0, width: imageWidth, height: imageHeight))
            
            if let faceCgImage = cgImage.cropping(to: cropRect) {
                let faceImage = UIImage(cgImage: faceCgImage, scale: fixedImage.scale, orientation: fixedImage.imageOrientation)
                if let data = faceImage.jpegData(compressionQuality: 0.8) {
                    let filePath = tempDir + "face_\(index)_\(captureTime.timeIntervalSince1970)_\(location.latitude)_\(location.longitude).jpg"
                    let url = URL(fileURLWithPath: filePath)
                    try? data.write(to: url)
                    print("Saved face image to: \(url)")
                }
            }
        }
    }
    
    private func imageFromSampleBuffer(sampleBuffer: CMSampleBuffer) -> UIImage? {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return nil }
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext(options: nil)
        if let cgImage = context.createCGImage(ciImage, from: ciImage.extent) {
            return UIImage(cgImage: cgImage)
        }
        return nil
    }
    
    // MARK: - CLLocationManagerDelegate
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let location = locations.last {
            DispatchQueue.main.async {
                self.currentLocation = location.coordinate
            }
        }
    }
}
