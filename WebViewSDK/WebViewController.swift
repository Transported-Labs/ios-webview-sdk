
//
//  WebViewController.swift
//  WebViewSDK
//
//  Created by Alexander Mokrushin on 24.03.2023.
//

import UIKit
import WebKit
import AVKit
import CoreHaptics
import Photos

public enum InvalidUrlError: Error {
    case runtimeError(String)
}

typealias ParamsArray = [Any?]

public class WebViewController: UIViewController, WKNavigationDelegate, WKUIDelegate {

    let cueSDKName = "cueSDK"
    let torchServiceName = "torch"
    let vibrationServiceName = "vibration"
    let permissionsServiceName = "permissions"
    let storageServiceName = "storage"
    let onMethodName = "on"
    let offMethodName = "off"
    let checkIsOnMethodName = "isOn"
    let vibrateMethodName = "vibrate"
    let sparkleMethodName = "sparkle"
    let saveMediaMethodName = "saveMedia"
    let askMicMethodName = "getMicPermission"
    let askCamMethodName = "getCameraPermission"
    let askSavePhotoMethodName = "getSavePhotoPermission"
    let testErrorMethodName = "testError"
    
    var curRequestId: Int? = nil
    var hapticEngine: CHHapticEngine?
    
    lazy var webView: WKWebView = {
        let webConfiguration = WKWebViewConfiguration()
        webConfiguration.allowsInlineMediaPlayback = true
        let wv = WKWebView(frame: .zero, configuration: webConfiguration)
        wv.uiDelegate = self
        wv.navigationDelegate = self
        wv.translatesAutoresizingMaskIntoConstraints = false
        return wv
    }()
    
    lazy var torchDevice: AVCaptureDevice? = {
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
        // Init HapticEngine
        initHapticEngine()
    }
    
    ///  Navigates to the url in embedded WKWebView-object
    public func navigateTo(url: URL) throws {
        if UIApplication.shared.canOpenURL(url) {
            webView.load(URLRequest(url: url))
        } else {
            throw InvalidUrlError.runtimeError("Invalid URL: \(url.absoluteString)")
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
    
    public func webView(_ webView: WKWebView,
        requestMediaCapturePermissionFor
        origin: WKSecurityOrigin,initiatedByFrame
        frame: WKFrameInfo,type: WKMediaCaptureType,
        decisionHandler: @escaping (WKPermissionDecision) -> Void){
        if ((type == .microphone) || (type == .camera)) {
            decisionHandler(.grant)
          }
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
    
    private func turnTorch(isOn: Bool) {
        if let device = torchDevice {
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
        if let device = torchDevice {
            let isOn = (device.torchMode == .on)
            sendToJavaScript(result: isOn)
        }
    }
    
    private func sparkle(duration: Int) {
        // Delay in microseconds for usleep function
        let blinkDelay: UInt32 = 50000
        if (duration > 0) {
            if let device = torchDevice {
                do {
                    var isSparkling = true
                    try device.lockForConfiguration()
                    // Create a work item with repeating flash
                    let workItem = DispatchWorkItem {
                        var isOn = false
                        while (isSparkling) {
                            isOn = !isOn
                            device.torchMode = isOn ? .on : .off
                            usleep(blinkDelay)
                        }
                    }
                    // Create dispatch group for flash
                    let dispatchGroup = DispatchGroup()
                    // Use .default thread instead of .background due to higher delay accuracy
                    DispatchQueue.global(qos: .default).async(group: dispatchGroup, execute: workItem)
                    // Stop workItem after duration milliseconds
                    DispatchQueue.main.asyncAfter(deadline: .now() + Double(duration) / 1000.0, execute: {
                        isSparkling = false
                        workItem.cancel()
                        device.torchMode = .off
                        device.unlockForConfiguration()
                        self.sendToJavaScript(result: nil)
                    })
                } catch {
                    errorToJavaScript("Torch could not be used for sparkle")
                }
            }
        } else {
            errorToJavaScript("Duration: \(duration) is not valid value")
        }
    }
    
    private func saveMedia(data: String, filename: String) {
        if ((data != "") && (filename != "")) {
            let dataDecoded = Data(base64Encoded: data)
            let decodedimage = UIImage(data: dataDecoded!)!
            PHPhotoLibrary.shared().performChanges({
                let creationOptions = PHAssetResourceCreationOptions()
                creationOptions.originalFilename = filename
                let request:PHAssetCreationRequest = PHAssetCreationRequest.forAsset()
                request.addResource(with: .photo, data: dataDecoded!, options: creationOptions)
            }, completionHandler: { success, error in
                if success {
                    DispatchQueue.main.async {
                        self.sendToJavaScript(result: nil)
                    }
                }
                else if let error = error {
                    self.errorToJavaScript(error.localizedDescription)
                }
                else {
                    self.errorToJavaScript("Media was not saved correctly")
                }
            })
        } else {
            errorToJavaScript("Data and filename can not be empty")
        }
    }
    
    private func initHapticEngine() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }

        do {
            hapticEngine = try CHHapticEngine()
            try hapticEngine?.start()
        } catch {
            errorToJavaScript("There was an error creating the haptic engine: \(error.localizedDescription)")
        }
    }
    
    private func makeVibration(duration: Int) {
        if let engine = hapticEngine {
            let intensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0)
            let sharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: 1.0)
            
            var events = [CHHapticEvent]()
            let seconds: TimeInterval = Double(duration) / 1000.0
            let event = CHHapticEvent(eventType: .hapticContinuous, parameters: [intensity, sharpness], relativeTime: 0, duration: seconds)
            events.append(event)
            do {
                let pattern = try CHHapticPattern(events: events, parameters: [])
                let player = try engine.makePlayer(with: pattern)
                try player.start(atTime: 0)
                sendToJavaScript(result: nil)
            } catch {
                errorToJavaScript("Haptic Error: \(error.localizedDescription).")
            }
        }
    }
    
    private func askForPermission(type: AVMediaType) {
        AVCaptureDevice.requestAccess(for: type) { allowed in
            DispatchQueue.main.async {
                self.sendToJavaScript(result: allowed)
            }
        }
    }
    
    private func askForSavePhotoPermission() {
        PHPhotoLibrary.requestAuthorization { status in
            DispatchQueue.main.async {
                self.sendToJavaScript(result: (status == .authorized))
            }
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
                    case sparkleMethodName:
                        if let duration = params[3] as? Int {
                            sparkle(duration: duration)
                        } else {
                            errorToJavaScript("Duration: null is not valid value")
                        }
                    case testErrorMethodName:
                        errorToJavaScript("This is the test error message")
                    default: break
                    }
                } else if serviceName == vibrationServiceName {
                    switch methodName {
                    case vibrateMethodName:
                        if let duration = params[3] as? Int {
                            makeVibration(duration: duration)
                        } else {
                            errorToJavaScript("Duration: null is not valid value")
                        }
                    default: break
                    }
                } else if serviceName == storageServiceName {
                    switch methodName {
                    case saveMediaMethodName:
                        if let data = params[3] as? String,
                            let filename = params[4] as? String  {
                            saveMedia(data: data, filename: filename)
                        } else {
                            errorToJavaScript("Duration: null is not valid value")
                        }
                    default: break
                    }
                } else if serviceName == permissionsServiceName {
                    switch methodName {
                    case askMicMethodName:
                        askForPermission(type: AVMediaType.audio)
                    case askCamMethodName:
                        askForPermission(type: AVMediaType.video)
                    case askSavePhotoMethodName:
                        askForSavePhotoPermission()
                    default: break
                    }
                } else {
                    errorToJavaScript("Only services '\(torchServiceName)', '\(vibrationServiceName)', '\(permissionsServiceName)' are supported")
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
