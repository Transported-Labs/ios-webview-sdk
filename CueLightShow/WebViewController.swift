
//
//  WebViewController.swift
//  CueLightShow
//
//  Created by Alexander Mokrushin on 24.03.2023.
//

import UIKit
import WebKit
import UniformTypeIdentifiers

public typealias LogHandler = (_ urlString: String) -> ()

enum ContentLoadType {
    case none
    case prefetch
    case navigate
}

struct AppConstant {
    static let cueScheme = "cue-data"
    static let httpsScheme = "https"
    static let cacheDirectoryName = "cache"
    static let cacheFilesPattern = "/files/"
    static let regexAllowedLetters = "[^0-9a-zA-Z.\\-]"
}

public class WebViewController: UIViewController, WKNavigationDelegate, WKURLSchemeHandler {

    private var cueSDK: CueSDK!
    private var logHandler: LogHandler?
    private var contentLoadType: ContentLoadType = .none
    private var cachePattern = "" // will be set up in runtime
    private var savedBrightness: CGFloat = CGFloat(0.0)

    public var isExitButtonHidden: Bool {
        get {
            return exitButton.isHidden
        }
        set {
            exitButton.isHidden = newValue
        }
    }
    
    fileprivate func initWebView() -> WKWebView {
        let webConfiguration = WKWebViewConfiguration()
        webConfiguration.allowsInlineMediaPlayback = true
        webConfiguration.allowsAirPlayForMediaPlayback = true
        webConfiguration.allowsPictureInPictureMediaPlayback = true
        webConfiguration.setURLSchemeHandler(self, forURLScheme: AppConstant.cueScheme)
        if #available(iOS 14.0, *) {
            webConfiguration.defaultWebpagePreferences.allowsContentJavaScript = true
        }
        let wv = WKWebView(frame: .zero, configuration: webConfiguration)
        wv.translatesAutoresizingMaskIntoConstraints = false
        wv.navigationDelegate = self
        return wv
    }
    
    lazy var webView: WKWebView = {
        return initWebView()
    }()

    private lazy var exitButton: UIButton = {
        let button = UIButton()
        button.tintColor = .white
        button.setImage(UIImage(systemName: "xmark", withConfiguration: UIImage.SymbolConfiguration.init(pointSize: 24, weight: .bold)), for: .normal)
        button.imageView?.contentMode = .scaleAspectFill
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    public override var prefersStatusBarHidden: Bool {
        return true
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        
        view.addSubview(webView)
        let safeArea = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: safeArea.leadingAnchor),
            webView.topAnchor.constraint(equalTo: safeArea.topAnchor),
            webView.rightAnchor.constraint(equalTo: safeArea.rightAnchor),
            webView.bottomAnchor.constraint(equalTo: safeArea.bottomAnchor)])
        view.addSubview(exitButton)
        NSLayoutConstraint.activate([
            exitButton.widthAnchor.constraint(equalToConstant: 30),
            exitButton.heightAnchor.constraint(equalToConstant: 30),
            exitButton.topAnchor.constraint(equalTo: view.topAnchor, constant: 20),
            exitButton.leftAnchor.constraint(equalTo: view.leftAnchor, constant: 16)])
        exitButton.addTarget(self, action: #selector(exitButtonPressed(_:)), for: .touchUpInside)
        // Adding control for reload web-page on pull down
        let refreshControl = UIRefreshControl()
        refreshControl.addTarget(self, action: #selector(reloadWebView(_:)), for: .valueChanged)
        webView.scrollView.addSubview(refreshControl)
        cueSDK = CueSDK(viewController: self, webView: self.webView)
    }
    
    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        cueSDK.isTorchLocked = false
        // Keep alive during the show
        UIApplication.shared.isIdleTimerDisabled = true
        savedBrightness = UIScreen.main.brightness
        UIScreen.main.brightness = CGFloat(1.0)
    }
    
    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // Return keep alive back to false
        UIApplication.shared.isIdleTimerDisabled = false
        UIScreen.main.brightness = savedBrightness
    }
    
    ///  Navigates to the url in embedded WKWebView-object
    public func navigateTo(urlString: String, logHandler: LogHandler? = nil) throws {
        if let url = URL(string: urlString) {
            if UIApplication.shared.canOpenURL(url) {
                contentLoadType = .navigate
                self.logHandler = logHandler
                adjustOriginParams(url: url)
                let cueURL = url
                // Commented out to avoid Exception: This task has already been stopped, url: Optional(https://idea-cue.stagingdxp.com/games/light-show/assets/index.8c9b7e3e.js)
//                if !urlString.contains("qrCode=true") {
//                    cueURL = self.changeURLScheme(newScheme: AppConstant.cueScheme, forURL: url)!
//                }
                addToLog("*** Started new NAVIGATE process ***")
                webView.load(URLRequest(url: cueURL))
            } else {
                throw InvalidUrlError.runtimeError("Invalid URL: \(url.absoluteString)")
            }
        }
    }
    
    public func prefetch(urlString: String, mainView: UIView? = nil, logHandler: LogHandler? = nil) throws {
        if let url = URL(string: "\(urlString)&preload=true") {
            if UIApplication.shared.canOpenURL(url) {
                contentLoadType = .prefetch
                self.logHandler = logHandler
                adjustOriginParams(url: url)
                let cueURL = self.changeURLScheme(newScheme: AppConstant.cueScheme, forURL: url)!
                addToLog("*** Started new PREFETCH process ***")
                // Create separate webView and make it visible on mainView to allow scripts to run correctly
                let prefetchWebView = initWebView()
                if let view = mainView {
                    view.addSubview(prefetchWebView)
                    let prefetchCueSDK = CueSDK(viewController: self, webView: prefetchWebView)
                    print("Created prefetchCueSDK: \(prefetchCueSDK)")
                }
                prefetchWebView.load(URLRequest(url: cueURL))
            } else {
                throw InvalidUrlError.runtimeError("Invalid URL: \(url.absoluteString)")
            }
        }
    }
    
    @objc private func exitButtonPressed(_ sender: UIButton?) {
        dismiss(animated: true, completion: nil)
        cueSDK.isTorchLocked = true
        cueSDK.cameraController.turnTorchOff()
        // Clear webView
        webView.load(URLRequest(url: URL(string:"about:blank")!))
    }
    
    ///  Navigates to the local file url in embedded WKWebView-object
    public func navigateToFile(url: URL) {
        webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
    }

    @objc func reloadWebView(_ sender: UIRefreshControl) {
        webView.reload()
        sender.endRefreshing()
    }
    
    func changeURLScheme(newScheme: String, forURL: URL?) -> URL? {
        var components: NSURLComponents?
        if let forURL {
            components = NSURLComponents(url: forURL, resolvingAgainstBaseURL: true)
        }
        components?.scheme = newScheme
        return components?.url
    }
    
    public func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        // Handle WKURLSchemeTask delegate methods
        if let url = changeURLScheme(newScheme: AppConstant.httpsScheme, forURL: urlSchemeTask.request.url) {
            let urlString = url.absoluteString
            let fileName = makeFileNameFromUrl(url: url)
            let shortFileName = shorten(fileName)
            print("Start loading: \(urlString)")
            // Check condition for cached files
            if urlString.contains(cachePattern) {
                switch contentLoadType {
                case .none:
                    print("Not prefetch or navigate")
                case .prefetch:
                    saveToCache(url: url, task: urlSchemeTask)
                case .navigate:
                    if loadFromCache(url: url, task: urlSchemeTask) {
                        addToLog("Loaded from cache: \(shortFileName)")
                    } else {
                        downloadFromWeb(url: url, task: urlSchemeTask)
                        addToLog("Loaded NOT from cache, from url: \(urlString)")
                    }
                }
            } else {
                // Usual download from web without cache
                downloadFromWeb(url: url, task: urlSchemeTask)
            }
            
        }
    }

    public func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        print("Stopped loading \(urlSchemeTask.request.url?.absoluteString ?? "")\n")
    }
    
    public func showCache() -> String {
        var resultMessage = ""
        var index = 0
        let fileManager = FileManager.default
        do {
            let documentsDirectory = try fileManager.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
            let cacheDirectory = documentsDirectory.appendingPathComponent(AppConstant.cacheDirectoryName, isDirectory: true)
            if let enumerator = fileManager.enumerator(at: cacheDirectory,
                                                               includingPropertiesForKeys: nil,
                                                               options: .skipsHiddenFiles) {
                for case let fileURL as URL in enumerator {
                    index += 1
                    resultMessage += "\(index). \(shorten(fileURL.path))\n"
                }
            }
        } catch {
            resultMessage += "Error: \(error)"
        }
        return resultMessage
    }
    
    public func clearCache() -> String {
        var resultMessage = ""
        let fileManager = FileManager.default
        do {
            let documentsDirectory = try fileManager.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
            let cacheDirectory = documentsDirectory.appendingPathComponent(AppConstant.cacheDirectoryName, isDirectory: true)
            if let enumerator = fileManager.enumerator(at: cacheDirectory,
                                                               includingPropertiesForKeys: nil,
                                                               options: .skipsHiddenFiles) {
                for case let fileURL as URL in enumerator {
                    resultMessage += "Deleted: '\(shorten(fileURL.path))'\n"
                    try fileManager.removeItem(at: fileURL)
                }
            }
        } catch {
            resultMessage += "Error in delete: \(error)"
        }
        return resultMessage
    }
    
    fileprivate func saveToCache(url: URL, task: WKURLSchemeTask) {
        let fileName = makeFileNameFromUrl(url: url)
        let shortFileName = shorten(fileName)
        URLSession.shared.dataTask(with: url) { (cueData, cueResponse, error) in
            if let data = cueData, let response = cueResponse {
                let fileManager = FileManager.default
                // Get the Document Directory URL
                if let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
                    var resultMessage: String = ""
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
                        resultMessage = "Failed to save in cache, error: \(error.localizedDescription)"
                    }
                    self.addToLog("\(resultMessage): \(shortFileName)")
                }                
                self.processTaskFinish(task, response, data)
            }
        }.resume()
    }
    
    fileprivate func loadFromCache(url: URL, task: WKURLSchemeTask) -> Bool {
        let mimeType = url.absoluteString.mimeType()
        guard let fileUrl = fileUrlFromUrl(url: url),
              let data = try? Data(contentsOf: fileUrl) else { return false }
       
        let response = HTTPURLResponse(url: url,
                                       mimeType: mimeType,
                                       expectedContentLength: data.count, textEncodingName: nil)
        self.processTaskFinish(task, response, data)
        return true
    }
    
    fileprivate func downloadFromWeb(url: URL, task: WKURLSchemeTask) {
        URLSession.shared.dataTask(with: url) { (cueData, cueResponse, error) in
            if let data = cueData, let response = cueResponse {
                self.processTaskFinish(task, response, data)
            }
        }.resume()
    }
    
    // Safely finishes the task, catching the possible exception
    fileprivate func processTaskFinish(_ task: WKURLSchemeTask, _ response: URLResponse, _ data: Data) {
        let exception = tryBlock {
            task.didReceive(response)
            task.didReceive(data)
            task.didFinish()
        }
        if let error = exception {
            print("processTaskFinish Exception: \(error), url: \(String(describing: response.url))")
        }
    }
    
    fileprivate func  adjustOriginParams(url: URL) {
        cachePattern = ".\(url.rootDomain)\(AppConstant.cacheFilesPattern)"
    }
    
    fileprivate func makeFileNameFromUrl(url: URL) -> String {
        var fileName = url.absoluteString
        fileName.removingRegexMatches(pattern: AppConstant.regexAllowedLetters, replaceWith: "_")
        return fileName
    }
    
    fileprivate func fileUrlFromUrl(url: URL) -> URL? {
        let fileManager = FileManager.default
        if let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
            let localFileName = makeFileNameFromUrl(url: url)
            let fileURL = documentsDirectory.appendingPathComponent("\(AppConstant.cacheDirectoryName)/\(localFileName)")
            return fileURL
        } else {
            return nil
        }
    }
    
    fileprivate func shorten(_ fileName: String) -> String {
        if let index = fileName.range(of: "_", options: .backwards)?.upperBound {
            let afterEqualsTo = String(fileName.suffix(from: index))
            return afterEqualsTo
        } else {
            return fileName
        }
    }
    
    fileprivate func addToLog(_ logLine: String) {
        if let logHandler = self.logHandler {
            logHandler(logLine)
            print("Log: \(logLine)")
        }
    }
}

extension String {
    mutating func removingRegexMatches(pattern: String, replaceWith: String = "") {
        do {
            let regex = try NSRegularExpression(pattern: pattern, options: .caseInsensitive)
            let range = NSRange(location: 0, length: count)
            self = regex.stringByReplacingMatches(in: self, options: [], range: range, withTemplate: replaceWith)
        } catch { return }
    }
}

extension URL {
    var rootDomain: String {
        guard let hostName = self.host else { return "" }
        let components = hostName.components(separatedBy: ".")
        if components.count > 1 {
            return components.last ?? ""
        } else {
            return hostName
        }
    }
}
