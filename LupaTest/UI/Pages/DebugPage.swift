// File: PageOneView.swift
import SwiftUI

struct DebugPage: View {
    var body: some View {
        VStack {
            Text("Welcome to Table Page")
                .font(.largeTitle)
                .padding()
            NavigationLink("Go to Page Two", destination: HomePage())
                .padding()
        }
        .navigationTitle("Table Page")
    }
}

struct DebugPagePreview: PreviewProvider {
    static var previews: some View {
        NavigationView {
            DebugPage()
        }
    }
}
