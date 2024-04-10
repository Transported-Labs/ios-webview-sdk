
//
//  WebViewController.swift
//  CueLightShow
//
//  Created by Alexander Mokrushin on 24.03.2023.
//

import UIKit
import WebKit

public typealias ProgressHandler = (_ progress: Int) -> ()

public class WebViewController: UIViewController {

    private var cueSDK: CueSDK!
    private var progressHandler: ProgressHandler?

    public var isExitButtonHidden: Bool {
        get {
            return exitButton.isHidden
        }
        set {
            exitButton.isHidden = newValue
        }
    }
    
    lazy var webView: WKWebView = {
        let webConfiguration = WKWebViewConfiguration()
        webConfiguration.allowsInlineMediaPlayback = true
        webConfiguration.allowsAirPlayForMediaPlayback = true
        webConfiguration.allowsPictureInPictureMediaPlayback = true
        if #available(iOS 14.0, *) {
            webConfiguration.defaultWebpagePreferences.allowsContentJavaScript = true
        }
        let wv = WKWebView(frame: .zero, configuration: webConfiguration)
        wv.translatesAutoresizingMaskIntoConstraints = false
        return wv
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
    }
    
    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // Return keep alive back to false
        UIApplication.shared.isIdleTimerDisabled = false
    }
    
    public override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if keyPath == "estimatedProgress" {
            let progress = Int(webView.estimatedProgress * 100.0)
            if let progressHandler = self.progressHandler {
                progressHandler(progress)
            }
        }
    }
    
    ///  Navigates to the url in embedded WKWebView-object
    public func navigateTo(url: URL, progressHandler: ProgressHandler? = nil) throws {
        if UIApplication.shared.canOpenURL(url) {
            if progressHandler != nil {
                self.progressHandler = progressHandler
                webView.addObserver(self, forKeyPath: #keyPath(WKWebView.estimatedProgress), options: .new, context: nil)
            }
            webView.load(URLRequest(url: url))
        } else {
            throw InvalidUrlError.runtimeError("Invalid URL: \(url.absoluteString)")
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
    
}
