// AWSS3Client+Rekognition.swift
import Foundation
import CryptoKit

extension AWSS3Client {
    // Rekognition signing method (defined only once)
    func generateRekognitionAuthorizationHeader(httpMethod: String, target: String, payload: Data, date: Date) -> (authorization: String, amzDate: String) {
        let service = "rekognition"
        let dateFormatter = DateFormatter()
        dateFormatter.timeZone = TimeZone(identifier: "UTC")
        dateFormatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        let amzDate = dateFormatter.string(from: date)
        dateFormatter.dateFormat = "yyyyMMdd"
        let dateStamp = dateFormatter.string(from: date)

        let canonicalURI = "/" // For Rekognition API
        let canonicalQueryString = ""
        let host = "rekognition.\(region).amazonaws.com"
        let canonicalHeaders = "host:\(host)\n" +
                               "x-amz-date:\(amzDate)\n" +
                               "x-amz-target:\(target)\n"
        let signedHeaders = "host;x-amz-date;x-amz-target"
        let payloadHash = sha256Hex(payload)
        let canonicalRequest = "\(httpMethod)\n\(canonicalURI)\n\(canonicalQueryString)\n\(canonicalHeaders)\n\(signedHeaders)\n\(payloadHash)"
        let canonicalRequestHash = sha256Hex(canonicalRequest.data(using: .utf8)!)

        let algorithm = "AWS4-HMAC-SHA256"
        let credentialScope = "\(dateStamp)/\(region)/\(service)/aws4_request"
        let stringToSign = "\(algorithm)\n\(amzDate)\n\(credentialScope)\n\(canonicalRequestHash)"

        let kSecret = "AWS4" + secretKey
        let kDate = hmacSHA256(key: kSecret.data(using: .utf8)!, data: dateStamp.data(using: .utf8)!)
        let kRegion = hmacSHA256(key: kDate, data: region.data(using: .utf8)!)
        let kService = hmacSHA256(key: kRegion, data: service.data(using: .utf8)!)
        let kSigning = hmacSHA256(key: kService, data: "aws4_request".data(using: .utf8)!)
        let signatureData = hmacSHA256(key: kSigning, data: stringToSign.data(using: .utf8)!)
        let signature = signatureData.map { String(format: "%02x", $0) }.joined()

        let authorizationHeader = "\(algorithm) Credential=\(accessKey)/\(credentialScope), SignedHeaders=\(signedHeaders), Signature=\(signature)"
        return (authorizationHeader, amzDate)
    }
}
