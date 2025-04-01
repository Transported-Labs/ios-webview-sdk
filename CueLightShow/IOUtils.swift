//
//  IoUtils.swift
//  CueLightShow
//
//  Created by Alexander Mokrushin on 21.03.2025.
//

import Foundation

public class IOUtils {
    
    private static var logHandler: LogHandler?
    
    public static func prefetchJSONData(urlString: String, logHandler: LogHandler? = nil) {
        if let url = URL(string: urlString) {
            self.logHandler = logHandler
            // Load files listed in JSONs for platform and for game
            if let urlObj = NSURLComponents(url: url, resolvingAgainstBaseURL: true) {
                let scheme = urlObj.scheme ?? "https"
                let host = urlObj.host ?? ""
                let platformIndexUrl = "\(scheme)://\(host)/\(AppConstant.indexFileName)"
                let gameIndexUrl = "\(scheme)://\(host)/\(AppConstant.gameAssetsPath)/\(AppConstant.indexFileName)"
                Task {
                    await makeCacheForIndex(urlString: platformIndexUrl)
                    await makeCacheForIndex(urlString: gameIndexUrl)
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
    
    public static func saveMediaToFile(fileName: String, data: Data) -> String {
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
    
    public static func saveDataToCache(url: URL, data: Data?) -> String {
        if let media = data {
            let fileName = makeFileNameFromUrl(url: url)
            let resultMessage = saveMediaToFile(fileName: fileName, data: media)
            return "\(resultMessage): \(shorten(fileName))"
        }
        return "Data is NULL for url: \(url.absoluteString)"
    }
    
    fileprivate static func saveToCacheFromUrl(url: URL) {
        URLSession.shared.dataTask(with: url) { (cueData, _, _) in
            let resultMessage = self.saveDataToCache(url: url, data: cueData)
            addToLog(resultMessage)
        }.resume()
    }
    
    fileprivate static func makeCacheForIndex(urlString: String) async {
        if let url = URL(string: urlString) {
            do {
                var pathToIndex = ""
                if let range = urlString.range(of: "/", options: .backwards) {
                    pathToIndex = String(urlString[urlString.startIndex..<range.lowerBound])
                }
                let links: [String] = try await URLSession.shared.decode([String].self, from: url)
                for link in links {
                    if let absoluteUrl = URL(string: "\(pathToIndex)/\(link)") {
                        saveToCacheFromUrl(url: absoluteUrl)
                    }
                }
            }  catch {
                addToLog("Error loading index: \(error)")
            }
        }
    }
    
    public static func shorten(_ fileName: String) -> String {
        if let range = fileName.range(of: "_", options: .backwards) {
            let shortName = String(fileName.suffix(from: range.upperBound))
            let prefixName = String(fileName[fileName.startIndex..<range.lowerBound])
            if let oneLevelUpRange = prefixName.range(of: "_", options: .backwards) {
                let oneLevelUp = String(fileName.suffix(from: oneLevelUpRange.upperBound))
                return oneLevelUp.replacingOccurrences(of: "_", with: "/")
            } else {
                return shortName
            }
        } else {
            return fileName
        }
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
