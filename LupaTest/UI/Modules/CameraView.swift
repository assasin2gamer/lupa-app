// File: CameraView.swift
import SwiftUI
import AVFoundation
import Vision

struct CameraView: UIViewRepresentable {
    class VideoPreviewView: UIView {
        override class var layerClass: AnyClass {
            AVCaptureVideoPreviewLayer.self
        }
        
        var videoPreviewLayer: AVCaptureVideoPreviewLayer {
            layer as! AVCaptureVideoPreviewLayer
        }
    }
    
    let session: AVCaptureSession
    let faceObservations: [VNFaceObservation]
    
    func makeUIView(context: Context) -> VideoPreviewView {
        let view = VideoPreviewView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        return view
    }
    
    func updateUIView(_ uiView: VideoPreviewView, context: Context) {
        uiView.videoPreviewLayer.session = session
        
        uiView.subviews.forEach { $0.removeFromSuperview() }
        
        for face in faceObservations {
            var faceRect = uiView.videoPreviewLayer.layerRectConverted(fromMetadataOutputRect: face.boundingBox)
            
            if let connection = uiView.videoPreviewLayer.connection, connection.isVideoMirrored {
                faceRect.origin.x = uiView.bounds.width - faceRect.origin.x - faceRect.size.width
            }
            faceRect.origin.y = uiView.bounds.height - faceRect.origin.y - faceRect.size.height
            
            let overlay = UIView(frame: faceRect)
            overlay.layer.borderColor = UIColor.red.cgColor
            overlay.layer.borderWidth = 2
            overlay.backgroundColor = UIColor.clear
            uiView.addSubview(overlay)
        }
    }
}
