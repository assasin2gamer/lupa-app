// File: PageController.swift
import SwiftUI

struct PageController: View {
    @State private var selectedTab: Int = 0
    
    var body: some View {
        ZStack {
            // Main content based on selected tab
            Group {
                switch selectedTab {
                case 0:
                    HomePage()
                case 1:
                    TablePage()
                default:
                    HomePage()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            // Overlay NavBar which includes the top-right console button
            NavBar(selectedTab: $selectedTab)
        }
        .edgesIgnoringSafeArea(.all)
    }
}

struct PageController_Previews: PreviewProvider {
    static var previews: some View {
        PageController()
    }
}
