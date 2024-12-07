//
//  ContentView.swift
//  Image Resizer
//
//  Created by Daniel Kamel on 30/11/2024.
//

import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct ContentView: View {
    @State private var images: [URL] = []
    @State private var results: [ImageResult] = []
    @State private var history: [HistoryItem] = []
    
    // Dictionary to store pairs keyed by a base name:
    // baseName: (original: URL?, focused: URL?)
    @State private var imagePairs = [String: (original: URL?, focused: URL?)]()

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

                // Display the results in two columns
                // We'll merge `results` with `imagePairs` to show original statuses and focused versions side by side.
                let mergedPairs = mergeResultsWithPairs(results: results, pairs: imagePairs)

                List {
                    ForEach(mergedPairs.keys.sorted(), id: \.self) { baseName in
                        let item = mergedPairs[baseName]!
                        HStack {
                            // Left column: Original image name and status
                            if let originalURL = item.originalURL, let status = item.status {
                                switch status {
                                case .acceptable:
                                    Text("\(originalURL.lastPathComponent) - Acceptable")

                                case .tooLarge:
                                    HStack {
                                        Text("\(originalURL.lastPathComponent) - Too Large")
                                        // Only show "Download Resized Image" button if no focused version was originally provided
                                        if item.focusedURL == nil {
                                            Button("Download Resized Image") {
                                                promptToSaveResizedImage(from: originalURL)
                                            }
                                        }
                                    }

                                case .failed:
                                    Text("\(originalURL.lastPathComponent) - Failed")
                                }

                            } else if let originalURL = item.originalURL {
                                // If no status found (shouldn't happen, but just in case), just show the name
                                Text("\(originalURL.lastPathComponent)")
                            } else {
                                // No original found (also shouldn't happen)
                                Text("No original image")
                            }

                            Spacer()

                            // Right column: Focused version if it was originally dropped by the user
                            if let focusedURL = item.focusedURL {
                                Text("Focused \(focusedURL.lastPathComponent)")
                            } else {
                                Text("") // No focused version
                            }
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
                        self.addToPairs(url: url)
                    }
                }
            }
        }
    }
    
    // Adds the dropped image to the pairs dictionary
    // If the file name starts with "Focused ", it's a focused version.
    // Otherwise, it's considered original.
    private func addToPairs(url: URL) {
        let fileName = url.lastPathComponent
        let baseName: String
        let isFocused: Bool
        
        if fileName.lowercased().hasPrefix("focused ") {
            isFocused = true
            baseName = String(fileName.dropFirst("Focused ".count))
        } else {
            isFocused = false
            baseName = fileName
        }
        
        var entry = imagePairs[baseName] ?? (original: nil, focused: nil)
        if isFocused {
            entry.focused = url
        } else {
            entry.original = url
        }
        imagePairs[baseName] = entry
    }

    private func checkAndResize() {
        results.removeAll()

        let tempDirectory = FileManager.default.temporaryDirectory

        // Only process original images (not focused ones)
        for (_, pair) in imagePairs {
            if let originalURL = pair.original {
                guard let nsImage = NSImage(contentsOf: originalURL) else {
                    results.append(.failed(url: originalURL))
                    continue
                }

                if let resized = resizeImageIfNeeded(nsImage) {
                    if resized != nsImage {
                        let resizedPath = tempDirectory.appendingPathComponent(originalURL.lastPathComponent)
                        saveImage(resized, to: resizedPath)
                        results.append(.tooLarge(url: originalURL, resizedImage: resized, resizedPath: resizedPath))
                    } else {
                        results.append(.acceptable(url: originalURL))
                    }
                } else {
                    results.append(.failed(url: originalURL))
                }
            }
        }

        history.append(HistoryItem(date: Date(), results: results))
    }

    // Merges the imagePairs dictionary with the results array to determine statuses
    private func mergeResultsWithPairs(results: [ImageResult], pairs: [String: (original: URL?, focused: URL?)]) -> [String: (originalURL: URL?, focusedURL: URL?, status: ImageStatus?)] {
        // Create a lookup table for results keyed by URL
        var resultLookup = [URL: ImageStatus]()
        for res in results {
            switch res {
            case .acceptable(let url):
                resultLookup[url] = .acceptable
            case .tooLarge(let url, _, _):
                resultLookup[url] = .tooLarge
            case .failed(let url):
                resultLookup[url] = .failed
            }
        }

        // Map pairs to a structure that includes the status
        var merged = [String: (originalURL: URL?, focusedURL: URL?, status: ImageStatus?)]()
        for (baseName, entry) in pairs {
            let status = entry.original.flatMap { resultLookup[$0] }
            merged[baseName] = (originalURL: entry.original, focusedURL: entry.focused, status: status)
        }
        return merged
    }

    private func promptToSaveResizedImage(from originalURL: URL) {
        // At this point, we know it's too large and no focused version was provided.
        // We must find the resized image from results again to save it.
        // The resized image was saved to a temporary location. Let's find it.

        if let res = results.first(where: {
            if case .tooLarge(let url, _, let resizedPath) = $0 {
                return url == originalURL && resizedPath != nil
            }
            return false
        }), case .tooLarge(_, _, let resizedPath) = res, let path = resizedPath {
            let panel = NSSavePanel()
            panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
            panel.nameFieldStringValue = "Focused " + path.lastPathComponent
            panel.allowedContentTypes = [.png]
            if panel.runModal() == .OK, let destination = panel.url {
                do {
                    try FileManager.default.copyItem(at: path, to: destination)
                    print("Image saved to \(destination.path)")
                } catch {
                    print("Failed to save the image: \(error.localizedDescription)")
                }
            }
        }
    }

    private func resizeImageIfNeeded(_ image: NSImage) -> NSImage? {
        let maxPixelArea: CGFloat = 750_000
        let currentArea = image.size.width * image.size.height

        if currentArea <= maxPixelArea {
            return image // No resizing needed
        }

        // Calculate the new size while maintaining aspect ratio
        let scaleFactor = sqrt(maxPixelArea / currentArea)
        let newSize = CGSize(
            width: round(image.size.width * scaleFactor),
            height: round(image.size.height * scaleFactor)
        )

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

// Represents the status of the original image after processing
enum ImageStatus {
    case acceptable
    case tooLarge
    case failed
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
