//
//  CueSDK.swift
//  CueLightShow
//
//  Created by Alexander Mokrushin on 05.04.2024.
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

public class CueSDK: NSObject, WKUIDelegate {
    let cueSDKName = "cueSDK"
    let torchServiceName = "torch"
    let vibrationServiceName = "vibration"
    let permissionsServiceName = "permissions"
    let storageServiceName = "storage"
    let cameraServiceName = "camera"
    let networkServiceName = "network"
    let timelineServiceName = "timeline"
    let onMethodName = "on"
    let offMethodName = "off"
    let checkIsOnMethodName = "isOn"
    let vibrateMethodName = "vibrate"
    let sparkleMethodName = "sparkle"
    let advancedSparkleMethodName = "advancedSparkle"
    let saveMediaMethodName = "saveMedia"
    let saveCacheFileName = "saveCacheFile"
    let getCacheFileName = "getCacheFile"
    let askMicMethodName = "getMicPermission"
    let askCamMethodName = "getCameraPermission"
    let askSavePhotoMethodName = "getSavePhotoPermission"
    let hasMicMethodName = "hasMicPermission"
    let hasCamMethodName = "hasCameraPermission"
    let hasSavePhotoMethodName = "hasSavePhotoPermission"
    let openCameraMethodName = "openCamera"
    let openPhotoCameraMethodName = "openPhotoCamera"
    let openVideoCameraMethodName = "openVideoCamera"
    let getStateMethodName = "getState"
    let startMethodName = "start"
    let stopMethodName = "stop"
    
    let testErrorMethodName = "testError"
    
    var hapticEngine: CHHapticEngine?
    
    var viewController: UIViewController!
    var webView: WKWebView!
    public var isTorchLocked: Bool = false
    private var networkStatus = ""
    
    var onSwitchTimelineActive: ((Bool) -> Void)?

    lazy var cameraController: CameraController = {
        let camController = CameraController(cueSDK: self)
        camController.modalPresentationStyle = .overFullScreen
        return camController
    }()
    
    lazy var torchDevice: AVCaptureDevice? = {
        if let device = bestCamera(for: .back) {
            if device.hasTorch {
                return device
            }
        }
        return nil
    }()
    
    public init(viewController: UIViewController, webView: WKWebView) {
        super.init()
        self.viewController = viewController
        self.webView = webView
        self.webView.uiDelegate = self
        let contentController = self.webView.configuration.userContentController
        contentController.add(self, name: cueSDKName)
//        initHapticEngine()
    }
    
    public func setSwitchTimelineActive(_ newHandler: @escaping (Bool) -> Void) {
        onSwitchTimelineActive = newHandler
    }
    
    // MARK: WebView methods
    
    public func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let alertController = UIAlertController(title: message,message: nil,preferredStyle: .alert)
        alertController.addAction(UIAlertAction(title: "OK", style: .cancel) {_ in completionHandler()})
        viewController.present(alertController, animated: true, completion: nil)
    }
    
    public func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
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
        if ((type == .microphone) || (type == .camera) || (type == .cameraAndMicrophone)) {
            decisionHandler(.grant)
          }
     }
    
    // MARK: Camera/torch methods

    private func openCamera(_ requestId: Int, cameraLayout: CameraLayout) {
        initAudioSession()
        cameraController.initBottomBar(cameraLayout: cameraLayout)
        viewController.present(cameraController, animated:true, completion:nil)
        sendToJavaScript(requestId, result: nil)
    }

    private func bestCamera(for position: AVCaptureDevice.Position) -> AVCaptureDevice? {
//        var deviceTypes: [AVCaptureDevice.DeviceType] = [.builtInDualCamera, .builtInWideAngleCamera]
//        if position == .back {
//            if #available(iOS 11.1, *) {
//                deviceTypes.insert(.builtInTrueDepthCamera, at: 0)
//            }
//        }
//        let discoverySession = AVCaptureDevice.DiscoverySession(deviceTypes: deviceTypes, mediaType: .video, position: .unspecified)
//        let devices = discoverySession.devices
//
//        guard !devices.isEmpty else { return nil }
//
//        return devices.first { $0.position == position }
        if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
              device.hasTorch {
            return device
        }  else {
            print("Torch is not available on this device")
            return nil
        }
    }
    
    fileprivate func adjustedIntenseLevel(_ level: Float) -> Float {
        let minLevel: Float = 0.001
        let maxLevel: Float = 1.0// - minLevel
        return (level < minLevel) ? minLevel : ((level > maxLevel) ? maxLevel : level)
    }
    
    private func turnTorchToLevel(_ requestId: Int, level: Float) {
        guard !isTorchLocked else {
            errorToJavaScript(requestId, "Torch is locked by another subsystem")
            return
        }
        if let device = torchDevice {
            do {
                let intenseLevel = adjustedIntenseLevel(level)
                try device.lockForConfiguration()
                try device.setTorchModeOn(level: intenseLevel)
                device.unlockForConfiguration()
                sendToJavaScript(requestId, result: nil)
            } catch {
                errorToJavaScript(requestId, "Torch to level could not be used, error: \(error)")
            }
        } else {
            errorToJavaScript(requestId, "Torch is not available")
        }
    }
    
    private func turnTorch(_ requestId: Int, isOn: Bool) {
        guard !isTorchLocked else {
            sendToJavaScript(requestId, result: nil)
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
                sendToJavaScript(requestId, result: nil)
            } catch {
                errorToJavaScript(requestId, "Torch could not be used, error: \(error)")
            }
        } else {
            errorToJavaScript(requestId, "Torch is not available")
        }
    }
    
    private func checkIsTorchOn(_ requestId: Int) {
        if let device = torchDevice {
            let isOn = (device.torchMode == .on)
            sendToJavaScript(requestId, result: isOn)
        } else {
            errorToJavaScript(requestId, "Torch is not available")
        }
    }
    
    fileprivate func debugMessageToJS(_ requestId: Int, _ message: String) {
        // Is used for debug purposes
//        DispatchQueue.main.async {
//            self.sendToJavaScript(requestId, result: nil, errorMessage: message)
//        }
    }
    
    fileprivate func sleepMs(_ delayMs: Int) {
        usleep(UInt32(delayMs * 1000))
    }
    
    fileprivate func nowMs() -> Int {
        return Int(CACurrentMediaTime() * 1000.0)
    }
    
    private func advancedSparkle(_ requestId: Int, rampUpMs: Int, sustainMs: Int, rampDownMs: Int, intensity: Float) {
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
                            debugMessageToJS(requestId, "rampUp: \(upIntensity)")
                            if (upIntensity > 0.0) && !isTorchLocked {
                                try device.setTorchModeOn(level: upIntensity)
                            }
                            sleepMs(blinkDelayMs)
                            currentRampUpTime = nowMs() - rampUpStart
                        }
                        if isSparkling && !isTorchLocked {
                            debugMessageToJS(requestId, "sustain: \(intenseLevel)")
                            try device.setTorchModeOn(level: intenseLevel)
                        }
                        sleepMs(sustainMs)
                        let rampDownStart = nowMs()
                        var currentRampDownTime = 0
                        while ((currentRampDownTime < rampDownMs) && isSparkling){
                            let downIntensity = (1.0 - Float(currentRampDownTime) / Float(rampDownMs)) * intenseLevel
                            debugMessageToJS(requestId, "rampDownn: \(downIntensity)")
                            if (downIntensity > 0.0) && !isTorchLocked {
                                try device.setTorchModeOn(level: downIntensity)
                            }
                            sleepMs(blinkDelayMs)
                            currentRampDownTime = nowMs() - rampDownStart
                        }
                    } catch {
                        errorToJavaScript(requestId, "Torch could not be used inside advancedSparkle, error: \(error)")
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
                    self.debugMessageToJS(requestId, "stopped after:\(totalDuration) ms")
                    self.sendToJavaScript(requestId, result: nil)
                })
            } catch {
                errorToJavaScript(requestId, "Torch could not be used for advancedSparkle, error: \(error)")
            }
        } else {
            errorToJavaScript(requestId, "Torch is not available")
        }
    }
    
    private func sparkle(_ requestId: Int, duration: Int) {
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
                        self.sendToJavaScript(requestId, result: nil)
                    })
                } catch {
                    errorToJavaScript(requestId, "Torch could not be used for sparkle, error: \(error)")
                }
            } else {
                errorToJavaScript(requestId, "Torch is not available")
            }
        } else {
            errorToJavaScript(requestId, "Duration: \(duration) is not valid value")
        }
    }
    
    private func saveMedia(_ requestId: Int, data: String, filename: String) {
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
                        self.sendToJavaScript(requestId, result: nil)
                    }
                }
                else if let error = error {
                    self.errorToJavaScript(requestId, error.localizedDescription)
                }
                else {
                    self.errorToJavaScript(requestId, "Media was not saved correctly")
                }
            })
        } else {
            errorToJavaScript(requestId, "Data and filename can not be empty")
        }
    }
    
    private func saveCacheFile(_ requestId: Int, fileName: String, dataStr: String) {
        let data = Data(dataStr.utf8)
        let logMessage = IOUtils.saveMediaToFile(fileName: fileName, data: data, isOverwrite: true)
        print("CueSDK saveCacheFile: \(fileName), \(logMessage)")
        if (logMessage.contains("Error")) {
            errorToJavaScript(requestId, "\(logMessage), file: \(fileName)")
        } else {
            sendToJavaScript(requestId, result: nil)
        }
    }
    
    private func sendCacheFileToJavascript(_ requestId: Int, fileName: String) {
        let mediaFromCache = IOUtils.loadMediaFromCacheFile(fileName: fileName)
        print(mediaFromCache.logMessage)
        if let data = mediaFromCache.data {
            let inputAsString = String(decoding: data, as: UTF8.self)
            sendToJavaScript(requestId, result: inputAsString)
        } else {
            errorToJavaScript(requestId, "Error with file \(fileName): \(mediaFromCache.logMessage)")
        }
    }
    
    // MARK: Audio/vibration methods
    
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
            print("initAudioSession failed: \(error.localizedDescription)")
        }
    }
    
    func stopAudioSession() {
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setActive(false)
        } catch {
            print("stopAudioSession failed: \(error.localizedDescription)")
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
                    print("Failed to restart the hapticEngine: \(error.localizedDescription)")
                }
            }
            try hapticEngine?.start()
        } catch {
            print("There was an error creating the hapticEngine: \(error.localizedDescription)")
        }
    }
    
    private func makeVibration(_ requestId: Int, duration: Int) {
        initAudioSession()
        AudioServicesPlayAlertSound(kSystemSoundID_Vibrate)
//        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        sendToJavaScript(requestId, result: nil)
    }
    
    private func makeVibration2(_ requestId: Int, duration: Int) {
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
                sendToJavaScript(requestId, result: nil)
            } catch {
                errorToJavaScript(requestId, "Haptic Error: \(error.localizedDescription).")
            }
        } else {
            errorToJavaScript(requestId, "Haptic Engine is not initialized")
        }
    }
    
    // MARK: Permissions methods
    
    private func checkHasPermission(_ requestId: Int, type: AVMediaType) {
        let result = (AVCaptureDevice.authorizationStatus(for: type) ==  .authorized)
        self.sendToJavaScript(requestId, result: result)
    }
    
    private func askForPermission(_ requestId: Int, type: AVMediaType) {
        AVCaptureDevice.requestAccess(for: type) { allowed in
            DispatchQueue.main.async {
                self.sendToJavaScript(requestId, result: allowed)
            }
        }
    }
    
    private func checkHasSavePhotoPermission(_ requestId: Int) {
        let result = (PHPhotoLibrary.authorizationStatus() == .authorized)
        self.sendToJavaScript(requestId, result: result)
    }
    
    private func askForSavePhotoPermission(_ requestId: Int) {
        PHPhotoLibrary.requestAuthorization { status in
            DispatchQueue.main.async {
                self.sendToJavaScript(requestId, result: (status == .authorized))
            }
        }
    }
}

// MARK: SDK methods, WebView communication

extension CueSDK: WKScriptMessageHandler{
    
    fileprivate func processParams(_ params: ParamsArray) {
        if let requestId = params[safe: 0] as? Int {
            if let serviceName = params[safe: 1] as? String, let methodName = params[safe: 2] as? String {
                switch serviceName {
                case torchServiceName:
                    handleTorchService(requestId, methodName, params)
                case vibrationServiceName:
                    handleVibrationService(requestId, methodName, params)
                case storageServiceName:
                    handleStorageService(requestId, methodName, params)
                case permissionsServiceName:
                    handlePermissionsService(requestId, methodName)
                case cameraServiceName:
                    handleCameraService(requestId, methodName)
                case networkServiceName:
                    handleNetworkService(requestId, methodName)
                case timelineServiceName:
                    handleTimelineService(requestId, methodName)
                default:
                    errorToJavaScript(requestId, "Unsupported service: \(serviceName)")
                }
            } else {
                errorToJavaScript(requestId, "No correct serviceName or/and methodName were passed")
            }
        } else {
            print("No correct requestId was passed: \(String(describing: params[safe: 0]))")
        }
    }
    
    fileprivate func handleTimelineService(_ requestId: Int, _ methodName: String) {
        switch methodName {
        case startMethodName:
            switchTimelineActive(requestId, newState: true)
        case stopMethodName:
            switchTimelineActive(requestId, newState: false)
        default: break
        }
    }
    
    fileprivate func handleNetworkService(_ requestId: Int, _ methodName: String) {
        switch methodName {
        case getStateMethodName:
            checkNetworkState(requestId)
        default: break
        }
    }
    
    fileprivate func handleCameraService(_ requestId: Int, _ methodName: String) {
        switch methodName {
        case openCameraMethodName:
            openCamera(requestId, cameraLayout: CameraLayout.both)
        case openPhotoCameraMethodName:
            openCamera(requestId, cameraLayout: CameraLayout.photoOnly)
        case openVideoCameraMethodName:
            openCamera(requestId, cameraLayout: CameraLayout.videoOnly)
        default: break
        }
    }
    
    fileprivate func handlePermissionsService(_ requestId: Int, _ methodName: String) {
        switch methodName {
        case askMicMethodName:
            askForPermission(requestId, type: AVMediaType.audio)
        case askCamMethodName:
            askForPermission(requestId, type: AVMediaType.video)
        case askSavePhotoMethodName:
            askForSavePhotoPermission(requestId)
        case hasMicMethodName:
            checkHasPermission(requestId, type: AVMediaType.audio)
        case hasCamMethodName:
            checkHasPermission(requestId, type: AVMediaType.video)
        case hasSavePhotoMethodName:
            checkHasSavePhotoPermission(requestId)
        default: break
        }
    }
    
    fileprivate func handleStorageService(_ requestId: Int, _ methodName: String, _ params: ParamsArray) {
        switch methodName {
        case saveMediaMethodName:
            if let data = params[safe: 3] as? String,
               let filename = params[safe: 4] as? String  {
                saveMedia(requestId, data: data, filename: filename)
            } else {
                errorToJavaScript(requestId, "Params data and filename must be not null")
            }
        case saveCacheFileName:
            if let fileName = params[safe: 3] as? String,
               let data = params[safe: 4] as? String {
                saveCacheFile(requestId, fileName: fileName, dataStr: data)
            } else {
                errorToJavaScript(requestId, "Params fileName and data must be not null")
            }
        case getCacheFileName:
            if let fileName = params[safe: 3] as? String {
                sendCacheFileToJavascript(requestId, fileName: fileName)
            } else {
                errorToJavaScript(requestId, "Param fileName must be not null")
            }
        default: break
        }
    }
    
    fileprivate func handleVibrationService(_ requestId: Int, _ methodName: String, _ params: ParamsArray) {
        switch methodName {
        case vibrateMethodName:
            if let duration = params[safe: 3] as? Int {
                makeVibration(requestId, duration: duration)
            } else {
                errorToJavaScript(requestId, "Duration: null is not valid value")
            }
        default: break
        }
    }
    
    fileprivate func handleTorchService(_ requestId: Int, _ methodName: String, _ params: ParamsArray) {
        switch methodName {
        case onMethodName:
            if params.count > 3 {
                // Float should be processed as Double to avoid error
                if let level = params[safe: 3] as? Double {
                    turnTorchToLevel(requestId, level: Float(level))
                } else {
                    let level = params[safe: 3]
                    errorToJavaScript(requestId, "Level is not valid float value: \(String(describing: level))")
                }
            } else {
                turnTorch(requestId, isOn: true)
            }
        case offMethodName:
            turnTorch(requestId, isOn: false)
        case checkIsOnMethodName:
            checkIsTorchOn(requestId)
        case sparkleMethodName:
            if let duration = params[safe: 3] as? Int {
                sparkle(requestId, duration: duration)
            } else {
                errorToJavaScript(requestId, "Duration: null is not valid value")
            }
        case advancedSparkleMethodName:
            if let rampUpMs = params[safe: 3] as? Int,
               let sustainMs = params[safe: 4] as? Int,
               let rampDownMs = params[safe: 5] as? Int,
               let intensity = params[safe: 6] as? Double {
                advancedSparkle(requestId, rampUpMs: rampUpMs, sustainMs: sustainMs, rampDownMs: rampDownMs, intensity: Float(intensity))
            } else {
                errorToJavaScript(requestId, "Needed more params for advancedSparkle: rampUpMs: Int, sustainMs: Int, rampDownMs: Int, intensity: Float")
            }
        case testErrorMethodName:
            errorToJavaScript(requestId, "This is the test error message")
        default: break
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
                print(error.localizedDescription)
            }
        }
        return nil
    }

    private func errorToJavaScript(_ requestId: Int, _ errorMessage: String) {
        print(errorMessage)
        DispatchQueue.main.async {
            self.sendToJavaScript(requestId, result: nil, errorMessage: errorMessage)
        }
    }
    
    private func sendToJavaScript(_ requestId: Int, result: Any?, errorMessage: String = "") {
        var params: ParamsArray = [requestId]
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
    }
    
    private func notifyJavaScript(channel:String, result: Any?, errorMessage: String = "") {
        var params: ParamsArray = [channel]
        if result != nil {
            params.append(result)
        } else if errorMessage != "" {
            params.append(nil)
            params.append(errorMessage)
        }
        if let data = try? JSONSerialization.data(withJSONObject: params, options: [.prettyPrinted]),
            let paramData = String(data: data, encoding: .utf8) {
            let js2:String = "cueSDKNotification(JSON.stringify(\(paramData)))"
            print("Sent Notification to Javascript: \(js2)")
            self.webView.evaluateJavaScript(js2, completionHandler: { (result, error) -> Void in
                print(error?.localizedDescription ?? "Sent successfully, no errors")
            })
        }
    }
    
    func notifyInternetConnection(param: String) {
        networkStatus = param
        notifyJavaScript(channel: "network-state", result: networkStatus)
    }
    
    public func notifyTimelineBreak() {
        notifyJavaScript(channel: "timeline", result: "break")
    }

    private func checkNetworkState(_ requestId: Int) {
        sendToJavaScript(requestId, result: networkStatus)
    }
    
    private func switchTimelineActive(_ requestId: Int, newState: Bool) {
        if let handler = onSwitchTimelineActive {
            handler(newState)
            sendToJavaScript(requestId, result: true)
        }
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}
