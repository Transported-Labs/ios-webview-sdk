//
//  IoUtils.swift
//  CueLightShow
//
//  Created by Alexander Mokrushin on 21.03.2025.
//

import Foundation

public typealias LogHandler = (_ urlString: String) -> ()
public typealias PrefetchCompletionListener = () -> ()

public class IOUtils {
    
    private static var logHandler: LogHandler?
    private static let masterGroup = DispatchGroup()
    
    fileprivate static func fetchLinks(from jsonURL: String, completion: @escaping ([String]) -> Void) {
        guard let url = URL(string: jsonURL) else {
            print("Invalid JSON URL: \(jsonURL)")
            completion([])
            return
        }
        
        URLSession.shared.dataTask(with: url) { data, response, error in
            guard let data = data, error == nil else {
                print("Error fetching JSON: \(error?.localizedDescription ?? "Unknown error")")
                completion([])
                return
            }
            do {
                let urls = try JSONDecoder().decode([String].self, from: data)
                completion(urls)
            } catch {
                print("Error decoding JSON: \(error.localizedDescription)")
                completion([])
            }
        }.resume()
    }

    fileprivate static func hasNewLink(path: String, from links: [String]) -> Bool {
        let fileManager = FileManager.default
        // Get the Document Directory URL
        if let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
            // Get the Cache Directory URL
            let cacheDirectory = documentsDirectory.appendingPathComponent(AppConstant.cacheDirectoryName, isDirectory: true)
            if !fileManager.fileExists(atPath: cacheDirectory.path){
                // No Cache Directory, all data are new
                addToLog("No Cache Directory is found, need to create cache")
                return true
            }
            for link in links {
                if let url = URL(string: "\(path)/\(link)") {
                    let fileName = makeFileNameFromUrl(url: url)
                    let fileURL = cacheDirectory.appendingPathComponent(fileName)
                    // Found non-existing in cache file
                    if !fileManager.fileExists(atPath: fileURL.path){
                        addToLog("File is not found in cache, need to update cache. File: \(shorten(fileName))")
                        return true
                    }
                }
            }
        }
        addToLog("All files listed in JSON for url: \(path) are already in cache.")
        return false
    }
    
    fileprivate static func downloadFiles(path: String, from links: [String]) {
        for link in links {
            if let url = URL(string: "\(path)/\(link)") {
                masterGroup.enter() // Enter the master group
                let task = URLSession.shared.dataTask(with: url) { cueData, _, cueError in
                    defer { masterGroup.leave() } // Leave the group when the task is done
                    
                    if let error = cueError {
                        self.addToLog("ERROR downloading by JSON: \(error.localizedDescription), url:\(url)")
                    } else {
                        let resultMessage = self.saveDataToCache(url: url, data: cueData, isOverwrite: true)
                        addToLog("Saved from JSON: \(resultMessage)")
                    }
                }
                task.resume()
            }
        }
    }
    
    public static func prefetchJSONData(urlString: String, logHandler: LogHandler? = nil,
                                        completion: @escaping PrefetchCompletionListener) {
        if let url = URL(string: urlString) {
            self.logHandler = logHandler
            // Load files listed in JSONs for platform and for game
            if let urlObj = NSURLComponents(url: url, resolvingAgainstBaseURL: true) {
                let scheme = urlObj.scheme ?? "https"
                let host = urlObj.host ?? ""
                let platformUrl = "\(scheme)://\(host)"
                let gameUrl = "\(scheme)://\(host)/\(AppConstant.gameAssetsPath)"
                
                let remoteJSONUrls = [platformUrl, gameUrl]
                // Load URLs from each remote JSON file and start downloading
                for jsonUrl in remoteJSONUrls {
                    masterGroup.enter()
                    let indexUrl = "\(jsonUrl)/\(AppConstant.indexFileName)"
                    fetchLinks(from: indexUrl) { links in
                        if hasNewLink(path: jsonUrl, from: links) {
                            downloadFiles(path: jsonUrl, from: links)
                        }
                        masterGroup.leave()
                    }
                }

                // Notify when all downloads are complete
                masterGroup.notify(queue: .main) {
                    addToLog("All downloads from all JSON groups are complete")
                    DispatchQueue.main.async {
                        completion()
                    }
                }
            }
        }
    }
    
    fileprivate static func makeFileUrl(fileName: String) -> URL? {
        let fileManager = FileManager.default
        if let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
            let fileURL = documentsDirectory.appendingPathComponent("\(AppConstant.cacheDirectoryName)/\(fileName)")
            return fileURL
        } else {
            return nil
        }
    }
    
    public static func loadMediaFromCacheFile(fileName: String) -> (data: Data?, logMessage: String) {
        if let fileUrl = makeFileUrl(fileName: fileName),
           let data = try? Data(contentsOf: fileUrl) {
            return (data: data, logMessage: "Loaded from cache")
        } else {
            return (data: nil, logMessage: "Not loaded, file does not exist")
        }
    }
    
    public static func saveMediaToFile(fileName: String, data: Data, isOverwrite: Bool) -> String {
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
                    if isOverwrite {
                        try fileManager.removeItem(at: fileURL)
                        resultMessage = "Overwritten in cache"
                    } else {
                        resultMessage = "Already exists in cache"
                        return resultMessage
                    }
                } else {
                    resultMessage = "Added to cache"
                }
                resultMessage += ", size: \(data.count) "
                // Save the downloaded file to a desired location
                try data.write(to: fileURL, options: [.atomic])
            } catch {
                resultMessage = "Error, failed to save in cache: \(error.localizedDescription)"
            }
        }
        return resultMessage
    }
    
    public static func prepareUrlString(urlString: String) -> String {
        var preparedUrl: String = urlString
        // Remove part after ? sign
        if let range = preparedUrl.range(of: "?") {
            preparedUrl = String(preparedUrl[preparedUrl.startIndex..<range.lowerBound])
        }
        // Add index.html after last /
        let lastChar = preparedUrl[preparedUrl.index(before: preparedUrl.endIndex)]
        if (lastChar == "/") {
            preparedUrl += AppConstant.indexHtml
        }
        return preparedUrl
    }
    
    public static func makeFileNameFromUrl(url: URL) -> String {
        var fileName: String = prepareUrlString(urlString: url.absoluteString)
        fileName.removingRegexMatches(pattern: AppConstant.regexAllowedLetters, replaceWith: "_")
        return fileName
    }
    
    public static func saveDataToCache(url: URL, data: Data?, isOverwrite: Bool) -> String {
        if let media = data {
            let fileName = makeFileNameFromUrl(url: url)
            let resultMessage = saveMediaToFile(fileName: fileName, data: media, isOverwrite: isOverwrite)
            return "\(resultMessage): \(shorten(fileName))"
        }
        return "Data is NULL for url: \(url.absoluteString)"
    }
    
    fileprivate static func getLastNElements(from path: String, delimiter: Character, count n: Int) -> String {
        let components = path.split(separator: delimiter)
        
        guard n > 0, n <= components.count else {
            return path // Return the original string if the input is invalid
        }
        
        let lastNElements = components.suffix(n).joined(separator: "/")
        return lastNElements
    }
    
    public static func shorten(_ fileName: String) -> String {
        return getLastNElements(from: fileName, delimiter: "_", count: 2)
    }
    
    fileprivate static func addToLog(_ logLine: String) {
        print("Log: \(logLine)")
        if let logHandler = self.logHandler {
            logHandler(logLine)
        }
    }
}

extension URLSession {
    func decode<T: Decodable>(
        _ type: T.Type = T.self,
        from url: URL,
        keyDecodingStrategy: JSONDecoder.KeyDecodingStrategy = .useDefaultKeys,
        dataDecodingStrategy: JSONDecoder.DataDecodingStrategy = .deferredToData,
        dateDecodingStrategy: JSONDecoder.DateDecodingStrategy = .deferredToDate
    ) async throws  -> T {
        let (data, _) = try await data(from: url)

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = keyDecodingStrategy
        decoder.dataDecodingStrategy = dataDecodingStrategy
        decoder.dateDecodingStrategy = dateDecodingStrategy

        let decoded = try decoder.decode(T.self, from: data)
        return decoded
    }
}
