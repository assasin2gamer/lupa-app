// File: CaptureButton.swift
import SwiftUI

struct CaptureButton: View {
    var action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Circle()
                .fill(Color.blue)
                .frame(width: 70, height: 70)
                .shadow(radius: 5)
        }
    }
}

struct CaptureButton_Previews: PreviewProvider {
    static var previews: some View {
        CaptureButton {
            print("Capture button pressed")
        }
    }
}
