
//
//  WebViewController.swift
//  WebViewSDK
//
//  Created by Alexander Mokrushin on 24.03.2023.
//

import UIKit
import WebKit
import AVKit

public enum InvalidUrlError: Error {
    case runtimeError(String)
}

typealias ParamsArray = [Any?]

public class WebViewController: UIViewController, WKNavigationDelegate, WKUIDelegate {

    let cueSDKName = "cueSDK"
    let torchServiceName = "torch"
    let onMethodName = "on"
    let offMethodName = "off"
    let checkIsOnMethodName = "isOn"
    let testErrorMethodName = "testError"
    
    var curRequestId: Int? = nil
    
    lazy var webView: WKWebView = {
        let wv = WKWebView()
        wv.uiDelegate = self
        wv.navigationDelegate = self
        wv.translatesAutoresizingMaskIntoConstraints = false
        return wv
    }()
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        
        view.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.rightAnchor.constraint(equalTo: view.rightAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor)])
        // Adding control for reload web-page on pull down
        let refreshControl = UIRefreshControl()
        refreshControl.addTarget(self, action: #selector(reloadWebView(_:)), for: .valueChanged)
        webView.scrollView.addSubview(refreshControl)
        // Adding cueSDK scripting object
        webView.configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        let contentController = self.webView.configuration.userContentController
        contentController.add(self, name: cueSDKName)
    }
    
    ///  Navigates to the url in embedded WKWebView-object
    public func navigateTo(url: URL) throws {
        if UIApplication.shared.canOpenURL(url) {
            webView.load(URLRequest(url: url))
        } else {
            throw InvalidUrlError.runtimeError("Invalid URL")
        }
    }
    
    ///  Navigates to the local file url in embedded WKWebView-object
    public func navigateToFile(url: URL) {
        webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
    }
    
    public func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let alertController = UIAlertController(title: message,message: nil,preferredStyle: .alert)
        alertController.addAction(UIAlertAction(title: "OK", style: .cancel) {_ in completionHandler()})
        self.present(alertController, animated: true, completion: nil)
    }
    
    @objc func reloadWebView(_ sender: UIRefreshControl) {
        webView.reload()
        sender.endRefreshing()
    }
    
    private func bestCamera(for position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        var deviceTypes: [AVCaptureDevice.DeviceType] = [.builtInDualCamera, .builtInWideAngleCamera]
        if position == .back {
            if #available(iOS 11.1, *) {
                deviceTypes.insert(.builtInTrueDepthCamera, at: 0)
            }
        }
        let discoverySession = AVCaptureDevice.DiscoverySession(deviceTypes: deviceTypes, mediaType: .video, position: .unspecified)
        let devices = discoverySession.devices

        guard !devices.isEmpty else { return nil }

        return devices.first { $0.position == position }
    }
    
    private func torchDevice() -> AVCaptureDevice? {
        if let device = bestCamera(for: .back) {
            if device.hasTorch {
                return device
            } else {
                errorToJavaScript("Torch is not available")
            }
        }  else  {
            errorToJavaScript("Device has no back camera")
        }
        return nil
    }
    
    private func turnTorch(isOn: Bool) {
        if let device = torchDevice() {
            do {
                try device.lockForConfiguration()
                device.torchMode = isOn ? .on : .off
                device.unlockForConfiguration()
                sendToJavaScript(result: nil)
            } catch {
                errorToJavaScript("Torch could not be used")
            }
        }
    }
    
    private func checkIsTorchOn() {
        if let device = torchDevice() {
            let isOn = (device.torchMode == .on)
            sendToJavaScript(result: isOn)
        }
    }
}

extension WebViewController: WKScriptMessageHandler{
    
    fileprivate func processParams(_ params: ParamsArray) {
        if let requestId = params[0] as? Int {
            curRequestId = requestId
            if let serviceName = params[1] as? String, let methodName = params[2] as? String {
                if serviceName == torchServiceName {
                    switch methodName {
                    case onMethodName:
                        turnTorch(isOn: true)
                    case offMethodName:
                        turnTorch(isOn: false)
                    case checkIsOnMethodName:
                        checkIsTorchOn()
                    case testErrorMethodName:
                        errorToJavaScript("This is the test error message")
                    default: break
                    }
                } else {
                    errorToJavaScript("Only serviceName '\(torchServiceName)' is supported")
                }
            }
        } else {
            errorToJavaScript("No correct serviceName or/and methodName were passsed")
        }
    }
    
    public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        print("Received message from JS: \(message.body)")
        guard message.name == cueSDKName else { return }
        if let body = message.body as? String {
            if let params = convertToParamsArray(text: body) {
                processParams(params)
            }
        }
    }
    
    private func convertToParamsArray(text: String) -> ParamsArray? {
        if let data = text.data(using: .utf8) {
            do {
                return try JSONSerialization.jsonObject(with: data, options: []) as? ParamsArray
            } catch {
                errorToJavaScript(error.localizedDescription)
            }
        }
        return nil
    }

    private func errorToJavaScript(_ errorMessage: String) {
        print(errorMessage)
        sendToJavaScript(result: nil, errorMessage: errorMessage)
    }
    
    private func sendToJavaScript(result: Any?, errorMessage: String = "") {
        if curRequestId != nil {
            var params: ParamsArray = [curRequestId]
            if result != nil {
                params.append(result)
            } else if errorMessage != "" {
                params.append(nil)
                params.append(errorMessage)
            }
            if let data = try? JSONSerialization.data(withJSONObject: params, options: [.prettyPrinted]),
                let paramData = String(data: data, encoding: .utf8) {
                let js2:String = "cueSDKCallback(JSON.stringify(\(paramData)))"
                print("Sent to Javascript: \(js2)")
                self.webView.evaluateJavaScript(js2, completionHandler: { (result, error) -> Void in
                    print(error?.localizedDescription ?? "Sent successfully, no errors")
                })
            }
        } else {
            print("curRequestId is nil")
        }
    }
}
