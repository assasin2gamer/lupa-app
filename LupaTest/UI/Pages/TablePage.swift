// File: TablePage.swift
import SwiftUI

struct TablePage: View {
    @State private var records: [FaceCaptureRecord] = []
    
    // Group records by timestamp rounded to seconds.
    var groupedRecords: [(key: Date, value: [FaceCaptureRecord])] {
        let groups = Dictionary(grouping: records) { record in
            Date(timeIntervalSince1970: floor(record.timestamp.timeIntervalSince1970))
        }
        return groups.sorted { $0.key > $1.key }
    }
    
    var body: some View {
            List {
                ForEach(groupedRecords, id: \.key) { group in
                    Section(header:
                        HStack {
                            VStack(alignment: .leading) {
                                Text("Timestamp:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(group.key, formatter: dateFormatter)
                                    .font(.body)
                            }
                            Spacer()
                            Button(action: {
                                deleteGroup(timestamp: group.key)
                            }) {
                                Image(systemName: "trash")
                                    .foregroundColor(.red)
                            }
                        }
                    ) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 15) {
                                ForEach(group.value) { record in
                                    VStack {
                                        AsyncImage(url: record.imageURL) { image in
                                            image
                                                .resizable()
                                                .aspectRatio(contentMode: .fill)
                                                .frame(width: 60, height: 60)
                                                .clipped()
                                        } placeholder: {
                                            Rectangle()
                                                .fill(Color.gray.opacity(0.5))
                                                .frame(width: 60, height: 60)
                                        }
                                        Text("\(record.location.latitude, specifier: "%.4f"), \(record.location.longitude, specifier: "%.4f")")
                                            .font(.caption2)
                                    }
                                }
                            }
                            .padding(.vertical, 5)
                            
                        }
                    }
                }
            }
            .navigationTitle("Captured Faces")
            .onAppear {
                records = FaceCaptureStore.getRecords()
            }
            .padding(.top, 90)
        }
    
    
    private func deleteGroup(timestamp: Date) {
        // Delete records from the file system.
        FaceCaptureStore.deleteRecords(withTimestamp: timestamp)
        // Refresh records.
        records = FaceCaptureStore.getRecords()
    }
}

private let dateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .medium
    return formatter
}()

struct TablePage_Previews: PreviewProvider {
    static var previews: some View {
        TablePage()
    }
}
