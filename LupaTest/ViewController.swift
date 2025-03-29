import UIKit
import AVFoundation
import CoreLocation
import AudioToolbox

// MARK: - Models

struct BoundingBox: Codable {
    var Left: CGFloat
    var Top: CGFloat
    var Width: CGFloat
    var Height: CGFloat
}

struct ProcessedResult: Codable {
    var original_image_key: String
    var people: [PersonFace]
}

struct PersonFace: Codable {
    var face_id: String?
    var bounding_box: BoundingBox
    var status: String
    var saved_face_image_key: String?
}

// New structs for SearchFacesByImage response (optional, if you want to decode)
struct SearchFacesByImageResponse: Codable {
    var SearchedFaceId: String
    var FaceMatches: [FaceMatch]
    var FaceModelVersion: String?
}

struct FaceMatch: Codable {
    var Face: FaceDetail
    var Similarity: Float
}

struct FaceDetail: Codable {
    var BoundingBox: BoundingBox
    var FaceId: String
    var ExternalImageId: String?
    var Confidence: Float
    var ImageId: String?
}

// MARK: - Console Cell for Log Display

class FaceCell: UITableViewCell {
    static let identifier = "FaceCell"
    
    let infoLabel = UILabel()
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        infoLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(infoLabel)
        NSLayoutConstraint.activate([
            infoLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 10),
            infoLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            infoLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -10),
            infoLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10)
        ])
        infoLabel.numberOfLines = 0
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }
    
    func configure(with text: String) {
        infoLabel.text = text
    }
}
/////////////////////////////////////////////
// CameraViewController.swift
/////////////////////////////////////////////

class CameraViewController: UIViewController, UITableViewDataSource, UITableViewDelegate, UISearchBarDelegate, AVCapturePhotoCaptureDelegate, CLLocationManagerDelegate {
    
    var captureSession: AVCaptureSession?
    var previewLayer: AVCaptureVideoPreviewLayer?
    var photoOutput: AVCapturePhotoOutput?
    
    // Audio recorder property
    var audioRecorder: AVAudioRecorder?
    var lastAudioStartTime: Date?
    
    // Store the last captured image for scaling bounding boxes.
    var lastCapturedImage: UIImage?
    
    // View to display bounding boxes on preview
    let boundingBoxView = UIView()
    
    let overlayView = UIView()
    let searchBar = UISearchBar()
    let tableView = UITableView()
    
    // UI Console for log messages
    let consoleTextView: UITextView = {
        let tv = UITextView()
        tv.translatesAutoresizingMaskIntoConstraints = false
        tv.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        tv.textColor = .green
        tv.font = UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        tv.isEditable = false
        return tv
    }()
    
    // Button to toggle auto capture every 5 seconds
    let autoCaptureButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Start Auto Capture", for: .normal)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    // Processed results array (not used in this example)
    var processedResults: [ProcessedResult] = []
    
    var captureTimer: Timer?
    var isAutoCaptureEnabled = false
    var lastUploadedObjectKey: String?
    
    // Location Manager
    let locationManager = CLLocationManager()
    var currentLocation: CLLocation?
    
    
    
    // Rekognition collection ID (replace with your actual collection)
    let collectionId = "lupa-test"
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        
        setupAudioSession()
        setupCamera()
        setupBoundingBoxView()
        setupOverlay()
        setupAutoCaptureButton()
        setupConsole()
        setupLocationManager()
    }
    
    // MARK: - Audio Session and Recording
    func setupAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .default, options: [])
            try session.setActive(true)
            session.requestRecordPermission { granted in
                if granted {
                    self.updateConsole(with: "Microphone permission granted.")
                } else {
                    self.updateConsole(with: "Microphone permission denied.")
                }
            }
        } catch {
            self.updateConsole(with: "Audio session error: \(error.localizedDescription)")
        }
    }
    
    func startAudioRecording(with fileName: String) {
        let now = Date()
        if let lastStart = lastAudioStartTime, now.timeIntervalSince(lastStart) < 10 {
            updateConsole(with: "Audio recording already in progress; skipping new start.")
            return
        }
        lastAudioStartTime = now
        
        let audioFileName = "\(fileName).m4a"
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(audioFileName)
        
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 2,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        
        do {
            audioRecorder = try AVAudioRecorder(url: fileURL, settings: settings)
            audioRecorder?.record(forDuration: 10)
            updateConsole(with: "Started 10-second audio recording (AAC, renamed to .mp3 on upload): \(audioFileName)")
            scheduleAudioUpload(for: fileName)
        } catch {
            updateConsole(with: "Audio recording error: \(error.localizedDescription)")
        }
    }
    
    func scheduleAudioUpload(for fileName: String) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
            if let audioData = self.stopAudioRecording() {
                let audioObjectKey = (self.lastUploadedObjectKey ?? "unknown").replacingOccurrences(of: ".jpg", with: ".mp3")
                DispatchQueue.global(qos: .background).async {
                    self.s3UploadClient.uploadObject(objectKey: audioObjectKey, data: audioData) { audioSuccess in
                        DispatchQueue.main.async {
                            if audioSuccess {
                                self.updateConsole(with: "Audio upload successful.")
                            } else {
                                self.updateConsole(with: "Audio upload failed.")
                            }
                        }
                    }
                }
            } else {
                self.updateConsole(with: "No audio recorded.")
            }
        }
    }
    
    func stopAudioRecording() -> Data? {
        audioRecorder?.stop()
        if let url = audioRecorder?.url {
            do {
                let audioData = try Data(contentsOf: url)
                updateConsole(with: "Stopped audio recording, file size: \(audioData.count) bytes")
                return audioData
            } catch {
                updateConsole(with: "Error reading audio file: \(error.localizedDescription)")
            }
        }
        return nil
    }
    
    // MARK: - Console UI
    func setupConsole() {
        view.addSubview(consoleTextView)
        NSLayoutConstraint.activate([
            consoleTextView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10),
            consoleTextView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -10),
            consoleTextView.bottomAnchor.constraint(equalTo: overlayView.topAnchor, constant: -10),
            consoleTextView.heightAnchor.constraint(equalToConstant: 80)
        ])
        updateConsole(with: "Console initialized.")
    }
    
    func updateConsole(with message: String) {
        DispatchQueue.main.async {
            self.consoleTextView.text.append("\n\(message)")
            let range = NSMakeRange(self.consoleTextView.text.count - 1, 0)
            self.consoleTextView.scrollRangeToVisible(range)
        }
    }
    
    // MARK: - Location Manager Setup
    func setupLocationManager() {
        locationManager.delegate = self
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
    }
    
    // MARK: - Setup Camera and Preview
    func setupCamera() {
        captureSession = AVCaptureSession()
        guard let captureSession = captureSession else { return }
        captureSession.sessionPreset = .photo
        
        guard let camera = AVCaptureDevice.default(for: .video) else { return }
        do {
            let input = try AVCaptureDeviceInput(device: camera)
            if captureSession.canAddInput(input) {
                captureSession.addInput(input)
            }
        } catch {
            updateConsole(with: "Camera error: \(error.localizedDescription)")
            return
        }
        
        photoOutput = AVCapturePhotoOutput()
        if let photoOutput = photoOutput, captureSession.canAddOutput(photoOutput) {
            captureSession.addOutput(photoOutput)
        }
        
        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        guard let previewLayer = previewLayer else { return }
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = view.bounds
        view.layer.insertSublayer(previewLayer, at: 0)
        
        DispatchQueue.global(qos: .background).async {
            captureSession.startRunning()
        }
    }
    
    func setupBoundingBoxView() {
        boundingBoxView.frame = view.bounds
        boundingBoxView.backgroundColor = .clear
        view.addSubview(boundingBoxView)
    }
    
    // MARK: - Setup Overlay and Auto Capture Button
    func setupOverlay() {
        overlayView.translatesAutoresizingMaskIntoConstraints = false
        overlayView.backgroundColor = UIColor(white: 0, alpha: 0.5)
        view.addSubview(overlayView)
        NSLayoutConstraint.activate([
            overlayView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            overlayView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            overlayView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            overlayView.heightAnchor.constraint(equalTo: view.heightAnchor, multiplier: 0.5)
        ])
        
        searchBar.translatesAutoresizingMaskIntoConstraints = false
        searchBar.delegate = self
        overlayView.addSubview(searchBar)
        
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = .clear
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(FaceCell.self, forCellReuseIdentifier: FaceCell.identifier)
        overlayView.addSubview(tableView)
        
        NSLayoutConstraint.activate([
            searchBar.topAnchor.constraint(equalTo: overlayView.topAnchor),
            searchBar.leadingAnchor.constraint(equalTo: overlayView.leadingAnchor),
            searchBar.trailingAnchor.constraint(equalTo: overlayView.trailingAnchor),
            tableView.topAnchor.constraint(equalTo: searchBar.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: overlayView.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: overlayView.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: overlayView.bottomAnchor)
        ])
    }
    
    func setupAutoCaptureButton() {
        autoCaptureButton.addTarget(self, action: #selector(toggleAutoCapture), for: .touchUpInside)
        view.addSubview(autoCaptureButton)
        NSLayoutConstraint.activate([
            autoCaptureButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10),
            autoCaptureButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -10),
            autoCaptureButton.widthAnchor.constraint(equalToConstant: 150),
            autoCaptureButton.heightAnchor.constraint(equalToConstant: 40)
        ])
    }
    
    // MARK: - Auto Capture Control
    @objc func toggleAutoCapture() {
        isAutoCaptureEnabled.toggle()
        if isAutoCaptureEnabled {
            autoCaptureButton.setTitle("Stop Auto Capture", for: .normal)
            updateConsole(with: "Auto capture started.")
            captureTimer = Timer.scheduledTimer(timeInterval: 5.0, target: self, selector: #selector(capturePhoto), userInfo: nil, repeats: true)
        } else {
            autoCaptureButton.setTitle("Start Auto Capture", for: .normal)
            updateConsole(with: "Auto capture stopped.")
            captureTimer?.invalidate()
            captureTimer = nil
        }
    }
    
    // MARK: - Photo Capture with Audio and Rekognition
    @objc func capturePhoto() {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
        let dateString = dateFormatter.string(from: Date())
        var locationString = "unknown"
        if let location = currentLocation {
            locationString = "\(Int(location.coordinate.latitude))_\(Int(location.coordinate.longitude))"
        }
        let objectKeyBase = "\(dateString)_\(locationString)"
        // For IndexFaces we use the captured image bytes directly, so our local image key is used for logging.
        self.lastUploadedObjectKey = objectKeyBase + ".jpg"
        
        if let lastStart = lastAudioStartTime, Date().timeIntervalSince(lastStart) < 10 {
            updateConsole(with: "Audio recording already in progress; skipping new start.")
        } else {
            startAudioRecording(with: objectKeyBase)
        }
        
        updateConsole(with: "Capturing photo and processing image as \(self.lastUploadedObjectKey!)...")
        photoOutput?.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
    }
    
    // MARK: - AVCapturePhotoCaptureDelegate
    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        if let error = error {
            updateConsole(with: "Photo error: \(error.localizedDescription)")
            return
        }
        guard let imageData = photo.fileDataRepresentation() else { return }
        
        // Store the captured image for scaling bounding boxes.
        if let image = UIImage(data: imageData) {
            self.lastCapturedImage = image
        }
        
        // Clear previous bounding boxes.
        self.boundingBoxView.layer.sublayers?.forEach { $0.removeFromSuperlayer() }
        
        // Call IndexFaces using the captured image bytes.
        self.callIndexFacesAndDrawBoxes()
        
        // (Optional) Check for S3 JSON result if using S3-based processing.
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            let jsonKey = "results/\((self.lastUploadedObjectKey ?? "unknown").replacingOccurrences(of: ".jpg", with: ".json"))"
            self.updateConsole(with: "Checking for JSON at key: \(jsonKey)")
            self.s3Client.fetchObject(objectKey: jsonKey) { data in
                if let data = data, let jsonString = String(data: data, encoding: .utf8) {
                    self.updateConsole(with: "Raw JSON:\n\(jsonString)")
                } else {
                    self.updateConsole(with: "JSON does not exist in S3.")
                }
            }
        }
    }
    
    // MARK: - Call Rekognition IndexFaces and Draw Bounding Boxes
    func callIndexFacesAndDrawBoxes() {
        // Use the locally captured image.
        guard let capturedImage = self.lastCapturedImage,
              let imageData = capturedImage.jpegData(compressionQuality: 0.8) else {
            updateConsole(with: "No captured image available for Rekognition.")
            return
        }
        
        // Build the request for IndexFaces.
        // We'll send the image bytes (base64 encoded) in the "Bytes" field.
        let base64String = imageData.base64EncodedString()
        let requestBody: [String: Any] = [
            "CollectionId": collectionId,
            "Image": [
                "Bytes": base64String
            ],
            "ExternalImageId": self.lastUploadedObjectKey ?? "unknown",
            "MaxFaces": 100,
            "QualityFilter": "AUTO",
            "DetectionAttributes": ["ALL"]
        ]
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: requestBody, options: []) else {
            updateConsole(with: "Error creating Rekognition request JSON.")
            return
        }
        
        let target = "RekognitionService.IndexFaces"
        let endpoint = "https://rekognition.\(self.s3Client.region).amazonaws.com/"
        guard let url = URL(string: endpoint) else {
            updateConsole(with: "Invalid Rekognition endpoint URL.")
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = jsonData
        request.setValue("application/x-amz-json-1.1", forHTTPHeaderField: "Content-Type")
        request.setValue(target, forHTTPHeaderField: "X-Amz-Target")
        let (authorizationHeader, amzDate) = s3Client.generateRekognitionAuthorizationHeader(httpMethod: "POST", target: target, payload: jsonData, date: Date())
        request.setValue(amzDate, forHTTPHeaderField: "X-Amz-Date")
        request.setValue(authorizationHeader, forHTTPHeaderField: "Authorization")
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("Rekognition API error: \(error)")
                DispatchQueue.main.async {
                    self.updateConsole(with: "Rekognition call failed: \(error.localizedDescription)")
                }
                return
            }
            if let data = data {
                do {
                    // Print the raw response as text.
                    if let rawResponse = String(data: data, encoding: .utf8) {
                        DispatchQueue.main.async {
                            self.updateConsole(with: "Raw Rekognition response:\n\(rawResponse)")
                        }
                    }
                    
                    // Convert response to dictionary.
                    guard var responseDict = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
                        DispatchQueue.main.async {
                            self.updateConsole(with: "Unable to decode Rekognition response as dictionary.")
                        }
                        return
                    }
                    DispatchQueue.main.async {
                        // Get the "FaceRecords" array from the response.
                        var faceRecords: [[String: Any]] = []
                        if let records = responseDict["FaceRecords"] as? [[String: Any]] {
                            faceRecords = records
                        } else if let singleRecord = responseDict["FaceRecords"] as? [String: Any] {
                            faceRecords = [singleRecord]
                        } else {
                            self.updateConsole(with: "No FaceRecords found in response.")
                            return
                        }
                        
                        // Use the captured image size for scaling.
                        let imageSize = capturedImage.size
                        let previewSize = self.previewLayer?.bounds.size ?? CGSize.zero
                        
                        // Calculate scale and offsets based on .resizeAspectFill.
                        let imageAspect = imageSize.width / imageSize.height
                        let previewAspect = previewSize.width / previewSize.height
                        var scale: CGFloat = 1.0
                        var xOffset: CGFloat = 0
                        var yOffset: CGFloat = 0
                        
                        if previewAspect > imageAspect {
                            scale = previewSize.width / imageSize.width
                            yOffset = (previewSize.height - imageSize.height * scale) / 2.0
                        } else {
                            scale = previewSize.height / imageSize.height
                            xOffset = (previewSize.width - imageSize.width * scale) / 2.0
                        }
                        
                        // Draw a bounding box and label for each face record.
                        for record in faceRecords {
                            if let face = record["Face"] as? [String: Any],
                               let boundingBox = face["BoundingBox"] as? [String: Any],
                               let leftNorm = boundingBox["Left"] as? CGFloat,
                               let topNorm = boundingBox["Top"] as? CGFloat,
                               let widthNorm = boundingBox["Width"] as? CGFloat,
                               let heightNorm = boundingBox["Height"] as? CGFloat,
                               let faceId = face["FaceId"] as? String {
                                
                                let x = leftNorm * imageSize.width
                                let y = topNorm * imageSize.height
                                let boxWidth = widthNorm * imageSize.width
                                let boxHeight = heightNorm * imageSize.height
                                
                                let convertedRect = CGRect(x: x * scale + xOffset,
                                                           y: y * scale + yOffset,
                                                           width: boxWidth * scale,
                                                           height: boxHeight * scale)
                                
                                let boxLayer = CAShapeLayer()
                                boxLayer.frame = convertedRect
                                boxLayer.borderColor = UIColor.blue.cgColor
                                boxLayer.borderWidth = 2.0
                                
                                let textLayer = CATextLayer()
                                textLayer.string = faceId
                                textLayer.fontSize = 12
                                textLayer.foregroundColor = UIColor.blue.cgColor
                                textLayer.frame = CGRect(x: convertedRect.origin.x,
                                                         y: convertedRect.origin.y - 16,
                                                         width: 150,
                                                         height: 16)
                                textLayer.contentsScale = UIScreen.main.scale
                                
                                self.boundingBoxView.layer.addSublayer(boxLayer)
                                self.boundingBoxView.layer.addSublayer(textLayer)
                            }
                        }
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.updateConsole(with: "Error decoding Rekognition response: \(error.localizedDescription)")
                    }
                }
            }
        }.resume()
    }
    
    // MARK: - UITableViewDataSource Methods
    func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return processedResults.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: FaceCell.identifier, for: indexPath) as! FaceCell
        let result = processedResults[indexPath.row]
        let info = "Image: \(result.original_image_key) | People: \(result.people.count)"
        cell.configure(with: info)
        return cell
    }
    
    // MARK: - UITableViewDelegate Methods
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
    }
    
    // MARK: - UISearchBarDelegate Methods
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        tableView.reloadData()
    }
    
    // MARK: - CLLocationManagerDelegate Methods
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        currentLocation = locations.last
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        updateConsole(with: "Location error: \(error.localizedDescription)")
    }
}
