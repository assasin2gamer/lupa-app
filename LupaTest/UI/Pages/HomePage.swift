// File: HomePage.swift
import SwiftUI
import AVFoundation
import SFaceCompare
struct HomePage: View {
    @StateObject private var camera = CameraModel()
    @State private var isFaceDetectionEnabled = false
   
    var body: some View {
        ZStack(alignment: .topTrailing) {
            CameraView(session: camera.session, faceObservations: camera.faceObservations)
                .ignoresSafeArea()
            
            VStack {
              
                
                Spacer()
                
                Button(action: {
                    camera.captureAndSaveFaces()
                }) {
                    Text("Capture Faces")
                        .padding(10)
                        .background(Color.blue.opacity(0.7))
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .padding(.bottom, 90)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .padding(.trailing, 20)
        }
        .onAppear {
            camera.configure()
            camera.session.startRunning()
        }
        .onDisappear {
            camera.session.stopRunning()
        }
    }
}

struct HomePage_Previews: PreviewProvider {
    static var previews: some View {
        HomePage()
        
    }
}

   
