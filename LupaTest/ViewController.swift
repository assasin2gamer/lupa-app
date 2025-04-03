// CameraViewController.swift
import UIKit
import AVFoundation
import CoreLocation
import AudioToolbox

class CameraViewController: UIViewController {
    
    // MARK: - UI Properties
    let boundingBoxView = UIView()
    let overlayView = UIView()
    let searchBar = UISearchBar()
    let tableView = UITableView()
    let consoleTextView: UITextView = {
        let tv = UITextView()
        tv.translatesAutoresizingMaskIntoConstraints = false
        tv.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        tv.textColor = .green
        tv.font = UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        tv.isEditable = false
        return tv
    }()
    let autoCaptureButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Start Auto Capture", for: .normal)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    // MARK: - Capture and Processing Properties
    var captureSession: AVCaptureSession?
    var previewLayer: AVCaptureVideoPreviewLayer?
    var photoOutput: AVCapturePhotoOutput?
    var audioRecorder: AVAudioRecorder?
    var lastAudioStartTime: Date?
    var lastCapturedImage: UIImage?
    var processedResults: [ProcessedResult] = []
    var captureTimer: Timer?
    var isAutoCaptureEnabled = false
    var lastUploadedObjectKey: String?
    
    // MARK: - Location
    let locationManager = CLLocationManager()
    var currentLocation: CLLocation?
    
    // MARK: - Rekognition & S3
    let collectionId = "lupa-test"
    var s3Client: AWSS3Client! // Assumed to be injected or initialized elsewhere
    var s3UploadClient: AWSS3Client! // Assumed to be injected or initialized elsewhere
    
    // MARK: - View Lifecycle
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
    
    // MARK: - Audio Setup
    func setupAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .default, options: [])
            try session.setActive(true)
            session.requestRecordPermission { granted in
                self.updateConsole(with: granted ? "Microphone permission granted." : "Microphone permission denied.")
            }
        } catch {
            updateConsole(with: "Audio session error: \(error.localizedDescription)")
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
                    self.s3UploadClient.uploadObject(objectKey: audioObjectKey, data: audioData) { success in
                        DispatchQueue.main.async {
                            self.updateConsole(with: success ? "Audio upload successful." : "Audio upload failed.")
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
    
    // MARK: - Camera Setup
    func setupCamera() {
        captureSession = AVCaptureSession()
        guard let captureSession = captureSession else { return }
        captureSession.sessionPreset = .photo
        guard let camera = AVCaptureDevice.default(for: .video) else { return }
        do {
            let input = try AVCaptureDeviceInput(device: camera)
            if captureSession.canAddInput(input) { captureSession.addInput(input) }
        } catch {
            updateConsole(with: "Camera error: \(error.localizedDescription)")
            return
        }
        photoOutput = AVCapturePhotoOutput()
        if let photoOutput = photoOutput, captureSession.canAddOutput(photoOutput) {
            captureSession.addOutput(photoOutput)
        }
        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        if let previewLayer = previewLayer {
            previewLayer.videoGravity = .resizeAspectFill
            previewLayer.frame = view.bounds
            view.layer.insertSublayer(previewLayer, at: 0)
        }
        DispatchQueue.global(qos: .background).async { captureSession.startRunning() }
    }
    
    func setupBoundingBoxView() {
        boundingBoxView.frame = view.bounds
        boundingBoxView.backgroundColor = .clear
        view.addSubview(boundingBoxView)
    }
    
    // MARK: - UI Setup
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
    
    // MARK: - Location Setup
    func setupLocationManager() {
        locationManager.delegate = self
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
    }
    
    // MARK: - Console Logging
    func updateConsole(with message: String) {
        DispatchQueue.main.async {
            self.consoleTextView.text.append("\n\(message)")
            let range = NSMakeRange(self.consoleTextView.text.count - 1, 0)
            self.consoleTextView.scrollRangeToVisible(range)
        }
    }
    
    // MARK: - Auto Capture
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
    
    @objc func capturePhoto() {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
        let dateString = dateFormatter.string(from: Date())
        let locationString = currentLocation.map { "\(Int($0.coordinate.latitude))_\(Int($0.coordinate.longitude))" } ?? "unknown"
        let objectKeyBase = "\(dateString)_\(locationString)"
        lastUploadedObjectKey = objectKeyBase + ".jpg"
        if let lastStart = lastAudioStartTime, Date().timeIntervalSince(lastStart) < 10 {
            updateConsole(with: "Audio recording already in progress; skipping new start.")
        } else {
            startAudioRecording(with: objectKeyBase)
        }
        updateConsole(with: "Capturing photo and processing image as \(lastUploadedObjectKey!)...")
        photoOutput?.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
    }
    
    // MARK: - Rekognition Processing
    func callIndexFacesAndDrawBoxes() {
        guard let capturedImage = lastCapturedImage,
              let imageData = capturedImage.jpegData(compressionQuality: 0.8) else {
            updateConsole(with: "No captured image available for Rekognition.")
            return
        }
        
        let base64String = imageData.base64EncodedString()
        let requestBody: [String: Any] = [
            "CollectionId": collectionId,
            "Image": ["Bytes": base64String],
            "ExternalImageId": lastUploadedObjectKey ?? "unknown",
            "MaxFaces": 100,
            "QualityFilter": "AUTO",
            "DetectionAttributes": ["ALL"]
        ]
        guard let jsonData = try? JSONSerialization.data(withJSONObject: requestBody, options: []) else {
            updateConsole(with: "Error creating Rekognition request JSON.")
            return
        }
        
        let target = "RekognitionService.IndexFaces"
        let endpoint = "https://rekognition.\(s3Client.region).amazonaws.com/"
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
        
        URLSession.shared.dataTask(with: request) { data, _, error in
            if let error = error {
                DispatchQueue.main.async {
                    self.updateConsole(with: "Rekognition call failed: \(error.localizedDescription)")
                }
                return
            }
            guard let data = data else { return }
            do {
                if let rawResponse = String(data: data, encoding: .utf8) {
                    DispatchQueue.main.async { self.updateConsole(with: "Raw Rekognition response:\n\(rawResponse)") }
                }
                guard let responseDict = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
                    DispatchQueue.main.async { self.updateConsole(with: "Unable to decode Rekognition response as dictionary.") }
                    return
                }
                DispatchQueue.main.async {
                    var faceRecords: [[String: Any]] = []
                    if let records = responseDict["FaceRecords"] as? [[String: Any]] {
                        faceRecords = records
                    } else if let singleRecord = responseDict["FaceRecords"] as? [String: Any] {
                        faceRecords = [singleRecord]
                    } else {
                        self.updateConsole(with: "No FaceRecords found in response.")
                        return
                    }
                    let imageSize = capturedImage.size
                    let previewSize = self.previewLayer?.bounds.size ?? CGSize.zero
                    let imageAspect = imageSize.width / imageSize.height
                    let previewAspect = previewSize.width / previewSize.height
                    var scale: CGFloat = 1.0, xOffset: CGFloat = 0, yOffset: CGFloat = 0
                    if previewAspect > imageAspect {
                        scale = previewSize.width / imageSize.width
                        yOffset = (previewSize.height - imageSize.height * scale) / 2.0
                    } else {
                        scale = previewSize.height / imageSize.height
                        xOffset = (previewSize.width - imageSize.width * scale) / 2.0
                    }
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
        }.resume()
    }
}

// MARK: - AVCapturePhotoCaptureDelegate
extension CameraViewController: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error = error {
            updateConsole(with: "Photo error: \(error.localizedDescription)")
            return
        }
        guard let imageData = photo.fileDataRepresentation() else { return }
        if let image = UIImage(data: imageData) { lastCapturedImage = image }
        boundingBoxView.layer.sublayers?.forEach { $0.removeFromSuperlayer() }
        callIndexFacesAndDrawBoxes()
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
}

// MARK: - UITableViewDataSource & UITableViewDelegate
extension CameraViewController: UITableViewDataSource, UITableViewDelegate {
    func numberOfSections(in tableView: UITableView) -> Int { return 1 }
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { return processedResults.count }
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: FaceCell.identifier, for: indexPath) as! FaceCell
        let result = processedResults[indexPath.row]
        cell.configure(with: "Image: \(result.original_image_key) | People: \(result.people.count)")
        return cell
    }
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
    }
}

// MARK: - UISearchBarDelegate
extension CameraViewController: UISearchBarDelegate {
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        tableView.reloadData()
    }
}

// MARK: - CLLocationManagerDelegate
extension CameraViewController: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        currentLocation = locations.last
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        updateConsole(with: "Location error: \(error.localizedDescription)")
    }
}
