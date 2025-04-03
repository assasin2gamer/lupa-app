// File: FaceCaptureStore.swift
import Foundation
import CoreLocation

struct FaceCaptureStore {
    // Retrieves FaceCaptureRecords by scanning the temporary directory for face images.
    static func getRecords() -> [FaceCaptureRecord] {
        let tempDir = NSTemporaryDirectory()
        let fileManager = FileManager.default
        guard let files = try? fileManager.contentsOfDirectory(atPath: tempDir) else {
            return []
        }
        var records: [FaceCaptureRecord] = []
        for file in files {
            if file.hasPrefix("face_") && file.hasSuffix(".jpg") {
                let filePath = tempDir + file
                let url = URL(fileURLWithPath: filePath)
                // Expected format: face_{index}_{timestamp}_{lat}_{lon}.jpg
                let fileName = file.replacingOccurrences(of: "face_", with: "").replacingOccurrences(of: ".jpg", with: "")
                let components = fileName.split(separator: "_")
                if components.count == 4,
                   let timestampDouble = Double(components[1]),
                   let lat = Double(components[2]),
                   let lon = Double(components[3]) {
                    let timestamp = Date(timeIntervalSince1970: timestampDouble)
                    let location = CLLocationCoordinate2D(latitude: lat, longitude: lon)
                    let record = FaceCaptureRecord(timestamp: timestamp, location: location, imageURL: url)
                    records.append(record)
                }
            }
        }
        // Sort records by timestamp descending.
        return records.sorted(by: { $0.timestamp > $1.timestamp })
    }
    
    // Deletes all face image files that have the same timestamp (rounded to seconds).
    static func deleteRecords(withTimestamp timestamp: Date) {
        let tempDir = NSTemporaryDirectory()
        let fileManager = FileManager.default
        guard let files = try? fileManager.contentsOfDirectory(atPath: tempDir) else {
            return
        }
        for file in files {
            if file.hasPrefix("face_") && file.hasSuffix(".jpg") {
                let fileName = file.replacingOccurrences(of: "face_", with: "").replacingOccurrences(of: ".jpg", with: "")
                let components = fileName.split(separator: "_")
                if components.count == 4,
                   let timestampDouble = Double(components[1]) {
                    let fileTimestamp = Date(timeIntervalSince1970: timestampDouble)
                    if floor(fileTimestamp.timeIntervalSince1970) == floor(timestamp.timeIntervalSince1970) {
                        let filePath = tempDir + file
                        try? fileManager.removeItem(atPath: filePath)
                    }
                }
            }
        }
    }
}
