//
//  IoUtils.swift
//  CueLightShow
//
//  Created by Alexander Mokrushin on 21.03.2025.
//

import Foundation

class IoUtils {
    static let shared = IoUtils()

    private init() { }
    
    fileprivate func makeFileUrl(fileName: String) -> URL? {
        let fileManager = FileManager.default
        if let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
            let fileURL = documentsDirectory.appendingPathComponent("\(AppConstant.cacheDirectoryName)/\(fileName)")
            return fileURL
        } else {
            return nil
        }
    }
    
    func loadMediaFromCacheFile(fileName: String) -> (data: Data?, logMessage: String) {
        if let fileUrl = makeFileUrl(fileName: fileName),
           let data = try? Data(contentsOf: fileUrl) {
            return (data: data, logMessage: "Loaded from cache")
        } else {
            return (data: nil, logMessage: "Not loaded, file does not exist")
        }
    }
    
    func saveMediaToFile(fileName: String, data: Data) -> String {
        var resultMessage: String = ""
        let fileManager = FileManager.default
        // Get the Document Directory URL
        if let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
            // Get the Cache Directory URL
            let cacheDirectory = documentsDirectory.appendingPathComponent(AppConstant.cacheDirectoryName, isDirectory: true)
            do {
                if !fileManager.fileExists(atPath: cacheDirectory.path){
                    try fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true, attributes: nil)
                }
                let fileURL = cacheDirectory.appendingPathComponent(fileName)
                // Remove previous possible file version
                if fileManager.fileExists(atPath: fileURL.path){
                    try fileManager.removeItem(at: fileURL)
                    resultMessage = "Overwritten in cache"
                } else {
                    resultMessage = "Added to cache"
                }
                // Save the downloaded file to a desired location
                try data.write(to: fileURL, options: [.atomic])
            } catch {
                resultMessage = "Error, failed to save in cache: \(error.localizedDescription)"
            }
        }
        return resultMessage
    }
}
