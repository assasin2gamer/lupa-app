// File: NavBar.swift
import SwiftUI

struct NavBar: View {
    @Binding var selectedTab: Int
    @State private var showConsole = false
    
    var body: some View {
        ZStack {
            // Bottom Navigation Bar
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Button(action: {
                        selectedTab = 0
                    }) {
                        VStack {
                            Image(systemName: "house.fill")
                            Text("Home")
                        }
                    }
                    Spacer()
                    Button(action: {
                        selectedTab = 1
                    }) {
                        VStack {
                            Image(systemName: "list.bullet")
                            Text("Table")
                        }
                    }
                    Spacer()
                }
                .padding()
                .background(Color(UIColor.systemGray6).opacity(0.9))
            }
            
            // Top-right Console Button
            VStack {
                HStack {
                    Spacer()
                    Button(action: {
                        withAnimation {
                            showConsole.toggle()
                        }
                    }) {
                        Image(systemName: "terminal.fill")
                            .font(.title)
                            .padding(.top, 50)
                            .padding(.trailing, 30)
                    }
                }
                Spacer()
            }
            
            // Console overlay appears in the top right when toggled on
            if showConsole {
                ConsoleView(onClose: {
                    withAnimation {
                        showConsole = false
                    }
                })
                .environmentObject(ConsoleModel.shared)
                .frame(width: 300, height: 200)
                .transition(.move(edge: .top))
                .padding(.top, 70)
                .padding(.trailing, 20)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }
        }
        .edgesIgnoringSafeArea(.all)
    }
}

struct NavBar_Previews: PreviewProvider {
    static var previews: some View {
        NavBar(selectedTab: .constant(0))
    }
}
