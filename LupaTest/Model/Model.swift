// Models.swift
import UIKit

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
