//
//  ContentView.swift
//  Image Resizer
//
//  Created by Daniel Kamel on 30/11/2024.
//

import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var images: [URL] = []
    @State private var results: [ImageResult] = []
    @State private var history: [HistoryItem] = []

    // Specify the target dimensions for resizing
    let targetSize = CGSize(width: 576, height: 781)

    var body: some View {
        HStack {
            SidebarView(history: $history)
                .frame(width: 250)

            VStack {
                Spacer()

                Text("Drag image here")
                    .font(.title)
                    .foregroundColor(.blue)
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.blue.opacity(0.1))
                    )
                    .onDrop(of: [UTType.fileURL.identifier], isTargeted: nil) { providers in
                        handleDrop(providers: providers)
                        return true
                    }

                Spacer()

                if !images.isEmpty {
                    Button("Check and Resize") {
                        checkAndResize()
                    }
                    .padding()
                }

                List {
                    ForEach(results, id: \.self) { result in
                        switch result {
                        case .acceptable(let url):
                            Text("\(url.lastPathComponent) - Acceptable")
                        case .tooLarge(let url, _, let resizedPath):
                            VStack(alignment: .leading) {
                                Text("\(url.lastPathComponent) - Too Large")
                                if let resizedPath = resizedPath {
                                    Button("Download Resized Image") {
                                        let panel = NSSavePanel()
                                        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
                                        panel.nameFieldStringValue = resizedPath.lastPathComponent
                                        panel.allowedContentTypes = [.png]
                                        if panel.runModal() == .OK, let destination = panel.url {
                                            try? FileManager.default.copyItem(at: resizedPath, to: destination)
                                        }
                                    }
                                }
                            }
                        case .failed(let url):
                            Text("\(url.lastPathComponent) - Failed")
                        }
                    }
                }
                .frame(maxHeight: 300)
            }
        }
    }

    private func handleDrop(providers: [NSItemProvider]) {
        providers.forEach { provider in
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { (item, error) in
                if let urlData = item as? Data,
                   let url = URL(dataRepresentation: urlData, relativeTo: nil) {
                    DispatchQueue.main.async {
                        images.append(url)
                    }
                }
            }
        }
    }

    private func checkAndResize() {
        results.removeAll()

        let tempDirectory = FileManager.default.temporaryDirectory

        images.forEach { url in
            guard let nsImage = NSImage(contentsOf: url) else {
                results.append(.failed(url: url))
                return
            }

            if let resized = resizeImageIfNeeded(nsImage) {
                let resizedPath = tempDirectory.appendingPathComponent(url.lastPathComponent)
                saveImage(resized, to: resizedPath)
                results.append(.tooLarge(url: url, resizedImage: resized, resizedPath: resizedPath))
            } else {
                results.append(.acceptable(url: url))
            }
        }

        history.append(HistoryItem(date: Date(), results: results))
    }

    private func resizeImageIfNeeded(_ image: NSImage) -> NSImage? {
        // Resize the image to the target size regardless of the original size
        let newSize = targetSize

        guard let bitmapRep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(newSize.width),
            pixelsHigh: Int(newSize.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }

        bitmapRep.size = newSize
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmapRep)

        image.draw(
            in: NSRect(origin: .zero, size: newSize),
            from: NSRect(origin: .zero, size: image.size),
            operation: .copy,
            fraction: 1.0
        )

        NSGraphicsContext.restoreGraphicsState()

        let resizedImage = NSImage(size: newSize)
        resizedImage.addRepresentation(bitmapRep)
        return resizedImage
    }

    private func saveImage(_ image: NSImage, to url: URL) {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else { return }
        try? pngData.write(to: url)
    }
}

enum ImageResult: Hashable {
    case acceptable(url: URL)
    case tooLarge(url: URL, resizedImage: NSImage, resizedPath: URL?)
    case failed(url: URL)
}

struct HistoryItem: Hashable {
    let date: Date
    let results: [ImageResult]
}

struct SidebarView: View {
    @Binding var history: [HistoryItem]

    var body: some View {
        List {
            ForEach(history, id: \.date) { item in
                VStack(alignment: .leading) {
                    Text("Processed on \(item.date, formatter: DateFormatter.shortFormatter)")
                        .font(.headline)
                    ForEach(item.results, id: \.self) { result in
                        switch result {
                        case .acceptable(let url):
                            Text("\(url.lastPathComponent) - Acceptable")
                        case .tooLarge(let url, _, _):
                            Text("\(url.lastPathComponent) - Too Large")
                        case .failed(let url):
                            Text("\(url.lastPathComponent) - Failed")
                        }
                    }
                }
            }
        }
    }
}

extension DateFormatter {
    static var shortFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }
}

#Preview {
    ContentView()
}
