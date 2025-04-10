
//
//  WebViewController.swift
//  CueLightShow
//
//  Created by Alexander Mokrushin on 24.03.2023.
//

import UIKit
import WebKit
import UniformTypeIdentifiers
import Network

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
    static let indexHtml = "index.html"
    static let indexFileName = "index.json"
    static let gameAssetsPath = "games/light-show"
}

public class WebViewController: UIViewController, WKNavigationDelegate, WKURLSchemeHandler {

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
    
    public func initWebView() -> WKWebView {
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
//        if #available(iOS 16.4, *) {
//            wv.isInspectable = true
//        }
        return wv
    }
    
    public lazy var webView: WKWebView = {
        return initWebView()
    }()

    public lazy var cueSDK: CueSDK = {
        return CueSDK(viewController: self, webView: self.webView)
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
        let isOffline = !Reachability.isConnected()
        let offlineParam = if isOffline { "&offline=true" } else { "" }
        if let url = URL(string: "\(urlString)\(offlineParam)") {
            if UIApplication.shared.canOpenURL(url) {
                contentLoadType = .navigate
                self.logHandler = logHandler
                adjustOriginParams(url: url)
                if let cueURL = self.changeURLScheme(newScheme: AppConstant.cueScheme, forURL: url) {
                    addToLog("*** Started new NAVIGATE process, offline mode = \(isOffline) ***")
                    webView.load(URLRequest(url: cueURL))
                }
            } else {
                throw InvalidUrlError.runtimeError("Invalid URL: \(url.absoluteString)")
            }
        }
    }
    
    public func prefetchWithWebView(mainView: UIView?, url: URL) {
        if let cueURL = self.changeURLScheme(newScheme: AppConstant.cueScheme, forURL: url) {
            // Create separate webView and make it visible on mainView to allow scripts to run correctly
            let prefetchWebView = initWebView()
            if let view = mainView {
                view.addSubview(prefetchWebView)
                _ = CueSDK(viewController: self, webView: prefetchWebView)
            }
            prefetchWebView.load(URLRequest(url: cueURL))
        }
    }
    
    public func prefetch(urlString: String, mainView: UIView? = nil, logHandler: LogHandler? = nil) throws {
        if let url = URL(string: "\(urlString)&preload=true") {
            if UIApplication.shared.canOpenURL(url) {
                contentLoadType = .prefetch
                addToLog("*** Started new PREFETCH process ***")
                IOUtils.prefetchJSONData(urlString: urlString, logHandler: logHandler)
                self.logHandler = logHandler
                adjustOriginParams(url: url)
                prefetchWithWebView(mainView: mainView, url: url)
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
        if let cueUrl = urlSchemeTask.request.url, 
           let url = changeURLScheme(newScheme: AppConstant.httpsScheme, forURL: cueUrl) {
            let urlString = url.absoluteString
            let fileName = IOUtils.makeFileNameFromUrl(url: url)
            let shortFileName = shorten(fileName)
            print("Start loading: \(urlString)")
            switch contentLoadType {
            case .none:
                print("Not prefetch or navigate")
            case .prefetch:
                downloadFromWebSaveToCache(cueUrl: cueUrl, url: url, task: urlSchemeTask)
            case .navigate:
                if loadFromCache(cueUrl: cueUrl, url: url, task: urlSchemeTask) {
                    addToLog("Loaded from cache: \(shortFileName)")
                } else {
                    addToLog("Loaded NOT from cache, from url: \(urlString)")
                    downloadFromWebSaveToCache(cueUrl: cueUrl, url: url, task: urlSchemeTask)
                }
            }
        }
    }

    public func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        print("Stopped loading \(urlSchemeTask.request.url?.absoluteString ?? "")\n")
    }
    
//    public func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
//
//        print("decidePolicyFor for")
//        let response = navigationResponse.response as? HTTPURLResponse
//        response?.allHeaderFields.forEach({ key, value in
//            print("key: ", key)
//            print("value: ", value)
//        })
//        decisionHandler(.allow)
//    }
    
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
    
    fileprivate func loadFromCache(cueUrl: URL, url: URL, task: WKURLSchemeTask) -> Bool {
        guard let fileUrl = fileUrlFromUrl(url: url),
              let data = try? Data(contentsOf: fileUrl) else { return false }
        
//        if !processAsPatchedTextResource(url: url, task: task, data: data) {
            let mimeType = IOUtils.prepareUrlString(urlString: url.absoluteString).mimeType()
            let response = HTTPURLResponse(url: cueUrl,
                                           mimeType: mimeType,
                                           expectedContentLength: data.count, textEncodingName: nil)
            processTaskFinish(task, response, data)
//        }
        return true
    }
    
    fileprivate func saveDataToCache(url: URL, data: Data?) {
        let resultMessage = IOUtils.saveDataToCache(url: url, data: data)
        addToLog(resultMessage)
    }
    
    fileprivate func downloadFromWebSaveToCache(cueUrl: URL, url: URL, task: WKURLSchemeTask) {
        URLSession.shared.dataTask(with: url) { [self] (cueData, _, cueError) in
            if let error = cueError {
                self.addToLog("ERROR downloading by WebView: \(error.localizedDescription), url:\(url)")
            } else {
                if (url.absoluteString.contains(cachePattern)) {
                    saveDataToCache(url: url, data: cueData)
                }
                if let data = cueData {
//                    if !processAsPatchedTextResource(url: url, task: task, data: data) {
                        let mimeType = IOUtils.prepareUrlString(urlString: url.absoluteString).mimeType()
                        let response = HTTPURLResponse(url: cueUrl,
                                                       mimeType: mimeType,
                                                       expectedContentLength: data.count, textEncodingName: nil)
                        processTaskFinish(task, response, data)
//                    }
                }
            }
        }.resume()
    }
    
//    fileprivate func processAsPatchedTextResource(url: URL, task: WKURLSchemeTask, data: Data) -> Bool {
//        let mimeType = IOUtils.prepareUrlString(urlString: url.absoluteString).mimeType()
//        
//        if mimeType.contains("javascript") {
//            if let dataString = String(data: data, encoding: .utf8),
//               let cueUrl = changeURLScheme(newScheme: AppConstant.cueScheme, forURL: url) {
//                //https://dev-test-sergey.developdxp.com
//                let patchedDataString = dataString.replacingOccurrences(
//                    of: url.host!, //"https://services.developdxp.com",
//                    with: cueUrl.host! //"cue-data://services.developdxp.com"
//                )
//                if patchedDataString != dataString {
//                    addToLog("PATCHED: \(url)")
//                } else {
//                    addToLog("NOT PATCHED: \(url)")
//                }
//                let modifiedResponse = HTTPURLResponse(
//                    url: cueUrl,
//                    mimeType: mimeType,
//                    expectedContentLength: data.count, textEncodingName: nil)
//                
//                let modifiedData = patchedDataString.data(using: .utf8)!
//                processTaskFinish(task, modifiedResponse, modifiedData)
//                return true
//            }
//        }
//        return false
//    }
    
    // Safely finishes the task, catching the possible exception
    fileprivate func processTaskFinish(_ webTask: WKURLSchemeTask?, _ response: URLResponse, _ data: Data) {
        if let task = webTask {
            let exception = tryBlock {
                task.didReceive(response)
                task.didReceive(data)
                task.didFinish()
            }
            if let error = exception {
                print("EXCEPTION: \(error), url: \(String(describing: response.url))")
            }
        }
    }
    
    fileprivate func  adjustOriginParams(url: URL) {
        cachePattern = ".\(url.rootDomain)\(AppConstant.cacheFilesPattern)"
    }
    
    fileprivate func fileUrlFromUrl(url: URL) -> URL? {
        let fileManager = FileManager.default
        if let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
            let localFileName = IOUtils.makeFileNameFromUrl(url: url)
            let fileURL = documentsDirectory.appendingPathComponent("\(AppConstant.cacheDirectoryName)/\(localFileName)")
            return fileURL
        } else {
            return nil
        }
    }
    
    fileprivate func shorten(_ fileName: String) -> String {
        return IOUtils.shorten(fileName)
    }
    
    fileprivate func addToLog(_ logLine: String) {
        print("Log: \(logLine)")
        if let logHandler = self.logHandler {
            logHandler(logLine)
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
