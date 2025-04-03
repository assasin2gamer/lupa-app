// File: ConsoleView.swift
import SwiftUI

struct ConsoleView: View {
    @EnvironmentObject var console: ConsoleModel
    var onClose: () -> Void  // Closure to notify when the console should be closed
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with title, clear button, and close (X) button
            HStack {
                Text("Console")
                    .font(.headline)
                    .padding(.leading, 8)
                Spacer()
                Button(action: {
                    console.text = ""
                }) {
                    Image(systemName: "trash")
                        .padding(8)
                }
                Button(action: {
                    onClose()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .padding(8)
                }
            }
            .background(Color.black)
            .foregroundColor(.white)
            
            // Console output area
            ScrollView {
                Text(console.text)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.white)
                    .padding(8)
            }
            .frame(width: 300, height: 200)
            .background(Color.black)
        }
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white, lineWidth: 1))
        .padding()
        // Position at the top-right corner in its parent container.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
    }
}

struct ConsoleView_Previews: PreviewProvider {
    static var previews: some View {
        ConsoleView(onClose: { print("Console closed") })
            .environmentObject(ConsoleModel.shared)
    }
}
