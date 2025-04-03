// AWSS3Client.swift
import Foundation
import CryptoKit

class AWSS3Client {
    let accessKey: String
    let secretKey: String
    let region: String
    let bucket: String

    init(accessKey: String, secretKey: String, region: String, bucket: String) {
        self.accessKey = accessKey
        self.secretKey = secretKey
        self.region = region
        self.bucket = bucket
    }

    // MARK: - Helper Functions
    func hmacSHA256(key: Data, data: Data) -> Data {
        let symmetricKey = SymmetricKey(data: key)
        let signature = HMAC<SHA256>.authenticationCode(for: data, using: symmetricKey)
        return Data(signature)
    }

    func sha256Hex(_ data: Data) -> String {
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }

    // MARK: - S3 Signing (for S3 API calls)
    func generateAuthorizationHeader(httpMethod: String, objectKey: String, date: Date, payloadHash: String) -> (authorization: String, amzDate: String) {
        let service = "s3"
        let dateFormatter = DateFormatter()
        dateFormatter.timeZone = TimeZone(identifier: "UTC")
        dateFormatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        let amzDate = dateFormatter.string(from: date)
        dateFormatter.dateFormat = "yyyyMMdd"
        let dateStamp = dateFormatter.string(from: date)
        
        let canonicalURI = "/" + objectKey.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!
        let canonicalQueryString = ""
        let host = "\(bucket).s3.\(region).amazonaws.com"
        let canonicalHeaders = "host:\(host)\n" +
                               "x-amz-content-sha256:\(payloadHash)\n" +
                               "x-amz-date:\(amzDate)\n"
        let signedHeaders = "host;x-amz-content-sha256;x-amz-date"
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

    // MARK: - S3 API Calls
    func uploadObject(objectKey: String, data: Data, completion: @escaping (Bool) -> Void) {
        let httpMethod = "PUT"
        let payloadHash = sha256Hex(data)
        let now = Date()
        let (authorizationHeader, amzDate) = generateAuthorizationHeader(httpMethod: httpMethod, objectKey: objectKey, date: now, payloadHash: payloadHash)
        let host = "\(bucket).s3.\(region).amazonaws.com"
        let urlString = "https://\(host)/\(objectKey)"
        guard let url = URL(string: urlString) else {
            completion(false)
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = httpMethod
        request.httpBody = data
        request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        request.setValue(payloadHash, forHTTPHeaderField: "x-amz-content-sha256")
        request.setValue(amzDate, forHTTPHeaderField: "x-amz-date")
        request.setValue(authorizationHeader, forHTTPHeaderField: "Authorization")
        
        URLSession.shared.dataTask(with: request) { _, response, error in
            if let error = error {
                print("S3 upload error: \(error)")
                completion(false)
                return
            }
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                completion(true)
            } else {
                completion(false)
            }
        }.resume()
    }

    func fetchObject(objectKey: String, completion: @escaping (Data?) -> Void) {
        let httpMethod = "GET"
        let emptyPayloadHash = sha256Hex("".data(using: .utf8)!)
        let now = Date()
        let (authorizationHeader, amzDate) = generateAuthorizationHeader(httpMethod: httpMethod, objectKey: objectKey, date: now, payloadHash: emptyPayloadHash)
        let host = "\(bucket).s3.\(region).amazonaws.com"
        let urlString = "https://\(host)/\(objectKey)"
        guard let url = URL(string: urlString) else {
            completion(nil)
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = httpMethod
        request.setValue(emptyPayloadHash, forHTTPHeaderField: "x-amz-content-sha256")
        request.setValue(amzDate, forHTTPHeaderField: "x-amz-date")
        request.setValue(authorizationHeader, forHTTPHeaderField: "Authorization")
        
        URLSession.shared.dataTask(with: request) { data, _, error in
            if let error = error {
                print("S3 fetch error: \(error)")
                completion(nil)
                return
            }
            completion(data)
        }.resume()
    }
}
