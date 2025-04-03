// File: ConsoleModel.swift
import SwiftUI
import Combine

class ConsoleModel: ObservableObject {
    static let shared = ConsoleModel()
    
    @Published var text: String = "Console Output\n"
    
    func append(_ message: String) {
        text.append("\(message)\n")
    }
}
