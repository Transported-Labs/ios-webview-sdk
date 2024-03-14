
//
//  WebViewController.swift
//  CueLightShow
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
public typealias ProgressHandler = (_ progress: Int) -> ()

public class WebViewController: UIViewController, WKNavigationDelegate, WKUIDelegate {

    let cueSDKName = "cueSDK"
    let torchServiceName = "torch"
    let vibrationServiceName = "vibration"
    let permissionsServiceName = "permissions"
    let storageServiceName = "storage"
    let cameraServiceName = "camera"
    let onMethodName = "on"
    let offMethodName = "off"
    let checkIsOnMethodName = "isOn"
    let vibrateMethodName = "vibrate"
    let sparkleMethodName = "sparkle"
    let advancedSparkleMethodName = "advancedSparkle"
    let saveMediaMethodName = "saveMedia"
    let askMicMethodName = "getMicPermission"
    let askCamMethodName = "getCameraPermission"
    let askSavePhotoMethodName = "getSavePhotoPermission"
    let hasMicMethodName = "hasMicPermission"
    let hasCamMethodName = "hasCameraPermission"
    let hasSavePhotoMethodName = "hasSavePhotoPermission"
    let openCameraMethodName = "openCamera"
    let openPhotoCameraMethodName = "openPhotoCamera"
    let openVideoCameraMethodName = "openVideoCamera"
    
    let testErrorMethodName = "testError"
    
    var curRequestId: Int? = nil
    var hapticEngine: CHHapticEngine?
    var isTorchLocked: Bool = false
    public var isExitButtonHidden: Bool {
        get {
            return exitButton.isHidden
        }
        set {
            exitButton.isHidden = newValue
        }
    }
    private var progressHandler: ProgressHandler?
    
    lazy var webView: WKWebView = {
        let webConfiguration = WKWebViewConfiguration()
        webConfiguration.allowsInlineMediaPlayback = true
        webConfiguration.allowsAirPlayForMediaPlayback = true
        webConfiguration.allowsPictureInPictureMediaPlayback = true
        let wv = WKWebView(frame: .zero, configuration: webConfiguration)
        wv.uiDelegate = self
        wv.navigationDelegate = self
        wv.translatesAutoresizingMaskIntoConstraints = false
        return wv
    }()

    private lazy var cameraController: CameraController = {
        let camController = CameraController(webViewController: self)
        camController.modalPresentationStyle = .overFullScreen
        return camController
    }()
    
    private lazy var exitButton: UIButton = {
        let button = UIButton()
        button.tintColor = .white
        button.setImage(UIImage(systemName: "xmark", withConfiguration: UIImage.SymbolConfiguration.init(pointSize: 24, weight: .bold)), for: .normal)
        button.imageView?.contentMode = .scaleAspectFill
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
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
        // Adding cueSDK scripting object
        if #available(iOS 14.0, *) {
            webView.configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        }
        let contentController = self.webView.configuration.userContentController
        contentController.add(self, name: cueSDKName)
        // Init HapticEngine
//        initHapticEngine()
    }
    
    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        isTorchLocked = false
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
            if progress >= 100 {
                WKWebView.printAllObjects()
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
        isTorchLocked = true
        cameraController.turnTorchOff()
        // Clear webView
        webView.load(URLRequest(url: URL(string:"about:blank")!))
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
    
    public func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        // navigation types: linkActivated, formSubmitted,
        //                   backForward, reload, formResubmitted, other
        if let url = navigationAction.request.url {
            print("Load \(url.absoluteString)")
        }
        decisionHandler(.allow)

    }
    
    @available(iOS 15.0, *)
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
    
    fileprivate func adjustedIntenseLevel(_ level: Float) -> Float {
        let minLevel: Float = 0.001
        let maxLevel: Float = 1.0// - minLevel
        return (level < minLevel) ? minLevel : ((level > maxLevel) ? maxLevel : level)
    }
    
    private func turnTorchToLevel(level: Float) {
        guard !isTorchLocked else {
            sendToJavaScript(result: nil)
            return
        }
        if let device = torchDevice {
            do {
                let intenseLevel = adjustedIntenseLevel(level)
                try device.lockForConfiguration()
                try device.setTorchModeOn(level: intenseLevel)
                device.unlockForConfiguration()
                sendToJavaScript(result: nil)
            } catch {
                errorToJavaScript("Torch to level could not be used, error: \(error)")
            }
        }
    }
    
    private func turnTorch(isOn: Bool) {
        guard !isTorchLocked else {
            sendToJavaScript(result: nil)
            return
        }
        if let device = torchDevice {
            do {
                try device.lockForConfiguration()
                let mode: AVCaptureDevice.TorchMode = isOn ? .on : .off
                if device.isTorchModeSupported(mode) {
                    device.torchMode = mode
                }
                device.unlockForConfiguration()
                sendToJavaScript(result: nil)
            } catch {
                errorToJavaScript("Torch could not be used, error: \(error)")
            }
        }
    }
    
    private func checkIsTorchOn() {
        if let device = torchDevice {
            let isOn = (device.torchMode == .on)
            sendToJavaScript(result: isOn)
        }
    }
    
    fileprivate func debugMessageToJS(_ message: String) {
        // Is used for debug purposes
//        DispatchQueue.main.async {
//            self.sendToJavaScript(result: nil, errorMessage: message)
//        }
    }
    
    fileprivate func sleepMs(_ delayMs: Int) {
        usleep(UInt32(delayMs * 1000))
    }
    
    fileprivate func nowMs() -> Int {
        return Int(CACurrentMediaTime() * 1000.0)
    }
    
    private func advancedSparkle(rampUpMs: Int, sustainMs: Int, rampDownMs: Int, intensity: Float) {
        let blinkDelayMs: Int = 10
        let totalDuration = rampUpMs + sustainMs + rampDownMs
        if let device = torchDevice {
            do {
                let intenseLevel = adjustedIntenseLevel(intensity)
                try device.lockForConfiguration()
                var isSparkling = true
                // Create a work item for changing light
                let workItem = DispatchWorkItem { [self] in
                    do {
                        let rampUpStart = nowMs()
                        var currentRampUpTime = 0
                        while ((currentRampUpTime < rampUpMs) && isSparkling) {
                            let upIntensity = Float(currentRampUpTime) / Float(rampUpMs) * intenseLevel
                            debugMessageToJS("rampUp: \(upIntensity)")
                            if (upIntensity > 0.0) && !isTorchLocked {
                                try device.setTorchModeOn(level: upIntensity)
                            }
                            sleepMs(blinkDelayMs)
                            currentRampUpTime = nowMs() - rampUpStart
                        }
                        if isSparkling && !isTorchLocked {
                            debugMessageToJS("sustain: \(intenseLevel)")
                            try device.setTorchModeOn(level: intenseLevel)
                        }
                        sleepMs(sustainMs)
                        let rampDownStart = nowMs()
                        var currentRampDownTime = 0
                        while ((currentRampDownTime < rampDownMs) && isSparkling){
                            let downIntensity = (1.0 - Float(currentRampDownTime) / Float(rampDownMs)) * intenseLevel
                            debugMessageToJS("rampDownn: \(downIntensity)")
                            if (downIntensity > 0.0) && !isTorchLocked {
                                try device.setTorchModeOn(level: downIntensity)
                            }
                            sleepMs(blinkDelayMs)
                            currentRampDownTime = nowMs() - rampDownStart
                        }
                    } catch {
                        errorToJavaScript("Torch could not be used inside advancedSparkle, error: \(error)")
                    }
                }
                let dispatchGroup = DispatchGroup()
                // Use .default thread instead of .background due to higher delay accuracy
                DispatchQueue.global(qos: .default).async(group: dispatchGroup, execute: workItem)
                // Stop workItem after total duration milliseconds
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(totalDuration) / 1000.0 + 0.1, execute: {
                    isSparkling = false
                    workItem.cancel()
                    if device.isTorchModeSupported(.off) {
                        device.torchMode = .off
                    }
                    device.unlockForConfiguration()
                    self.debugMessageToJS("stopped after:\(totalDuration) ms")
                    self.sendToJavaScript(result: nil)
                })
            } catch {
                errorToJavaScript("Torch could not be used for advancedSparkle, error: \(error)")
            }
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
                            let mode: AVCaptureDevice.TorchMode = isOn ? .on : .off
                            if device.isTorchModeSupported(mode) && !self.isTorchLocked  {
                                device.torchMode = mode
                            }
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
                        if device.isTorchModeSupported(.off) {
                            device.torchMode = .off
                        }
                        device.unlockForConfiguration()
                        self.sendToJavaScript(result: nil)
                    })
                } catch {
                    errorToJavaScript("Torch could not be used for sparkle, error: \(error)")
                }
            }
        } else {
            errorToJavaScript("Duration: \(duration) is not valid value")
        }
    }
    
    private func saveMedia(data: String, filename: String) {
        if ((data != "") && (filename != "")) {
            let dataDecoded = Data(base64Encoded: data)
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
    
    private func initAudioSession() {
        let audioSession = AVAudioSession.sharedInstance()
        do {
            #if swift(>=5.0)
            try audioSession.setCategory(.playAndRecord, options: .mixWithOthers)
            #else
            try audioSession.setCategory(AVAudioSessionCategoryPlayAndRecord, with: AVAudioSession.CategoryOptions.mixWithOthers)
            #endif
            try audioSession.setAllowHapticsAndSystemSoundsDuringRecording(true)
            try audioSession.setActive(true)
        } catch {
            errorToJavaScript("initAudioSession failed: \(error.localizedDescription)")
        }
    }
    
    private func initHapticEngine() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }

        do {
            hapticEngine = try CHHapticEngine()
            // The reset handler provides an opportunity to restart the engine.
            hapticEngine?.stoppedHandler = { reason in
                print("Stop Handler: hapticEngine stopped for reason: \(reason.rawValue)")
                do {
                    // Try restarting the engine.
                    print("stoppedHandler: Try restarting the hapticEngine.")
                    try self.hapticEngine?.start()
                } catch {
                    self.errorToJavaScript("Failed to restart the hapticEngine: \(error.localizedDescription)")
                }
            }
            try hapticEngine?.start()
        } catch {
            errorToJavaScript("There was an error creating the hapticEngine: \(error.localizedDescription)")
        }
    }
    
    private func makeVibration(duration: Int) {
        initAudioSession()
        AudioServicesPlayAlertSound(kSystemSoundID_Vibrate)
//        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
    }
    
    private func makeVibration2(duration: Int) {
        initAudioSession()
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
    
    private func checkHasPermission(type: AVMediaType) {
        let result = (AVCaptureDevice.authorizationStatus(for: type) ==  .authorized)
        self.sendToJavaScript(result: result)
    }
    
    private func askForPermission(type: AVMediaType) {
        AVCaptureDevice.requestAccess(for: type) { allowed in
            DispatchQueue.main.async {
                self.sendToJavaScript(result: allowed)
            }
        }
    }
    
    private func checkHasSavePhotoPermission() {
        let result = (PHPhotoLibrary.authorizationStatus() == .authorized)
        self.sendToJavaScript(result: result)
    }
    
    private func askForSavePhotoPermission() {
        PHPhotoLibrary.requestAuthorization { status in
            DispatchQueue.main.async {
                self.sendToJavaScript(result: (status == .authorized))
            }
        }
    }
    
    private func openCamera(cameraLayout: CameraLayout) {
        initAudioSession()
        cameraController.initBottomBar(cameraLayout: cameraLayout)
        present(cameraController, animated:true, completion:nil)
        sendToJavaScript(result: nil)
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
                        if params.count > 3 {
                            // Float should be processed as Double to avoid error
                            if let level = params[3] as? Double {
                                turnTorchToLevel(level: Float(level))
                            } else {
                                let level = params[3]
                                errorToJavaScript("Level is not valid float value: \(level ?? "")")
                            }
                        } else {
                            turnTorch(isOn: true)
                        }
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
                    case advancedSparkleMethodName:
                        if params.count > 6 {
                            if let rampUpMs = params[3] as? Int {
                                if let sustainMs = params[4] as? Int {
                                    if let rampDownMs = params[5] as? Int {
                                        if let intensity = params[6] as? Double {
                                            advancedSparkle(rampUpMs: rampUpMs, sustainMs: sustainMs, rampDownMs: rampDownMs, intensity: Float(intensity))
                                        }}}}
                        } else {
                            errorToJavaScript("Needed more params for advancedSparkle: rampUpMs: Int, sustainMs: Int, rampDownMs: Int, intensity: Float")
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
                    case hasMicMethodName:
                        checkHasPermission(type: AVMediaType.audio)
                    case hasCamMethodName:
                        checkHasPermission(type: AVMediaType.video)
                    case hasSavePhotoMethodName:
                        checkHasSavePhotoPermission()
                    default: break
                    }
                } else if serviceName == cameraServiceName {
                    switch methodName {
                    case openCameraMethodName:
                        openCamera(cameraLayout: CameraLayout.both)
                    case openPhotoCameraMethodName:
                        openCamera(cameraLayout: CameraLayout.photoOnly)
                    case openVideoCameraMethodName:
                        openCamera(cameraLayout: CameraLayout.videoOnly)
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
        DispatchQueue.main.async {
            self.sendToJavaScript(result: nil, errorMessage: errorMessage)
        }
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

extension WKWebView {
    class func printAllObjects() {
        guard #available(iOS 9.0, *) else {return}

        WKWebsiteDataStore.default().fetchDataRecords(ofTypes: [WKWebsiteDataTypeMemoryCache, WKWebsiteDataTypeDiskCache, WKWebsiteDataTypeOfflineWebApplicationCache]) { records in
            records.forEach { record in
                print("Cache record:", record)
            }
        }
    }
}
