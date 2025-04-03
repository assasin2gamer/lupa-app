// File: FaceCaptureRecord.swift
import Foundation
import CoreLocation

struct FaceCaptureRecord: Identifiable {
    let id = UUID()
    let timestamp: Date
    let location: CLLocationCoordinate2D
    let imageURL: URL
}
