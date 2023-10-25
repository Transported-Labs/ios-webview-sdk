//
//  CameraLink.swift
//  WebViewSDK
//
//  Created by Alexander Mokrushin on 23.10.2023.
//

import Foundation
import AVFoundation
import UIKit

class CameraLink: NSObject {
    
    enum CameraError: Swift.Error {
        case sessionAlreadyRunning
        case sessionIsMissing
        case inputIsInvalid
        case operationIsInvalid
        case cameraNotAvailable
        case other
    }
    
    public enum CameraPosition {
        case frontPosition
        case backPosition
    }
    
    public enum OutputType {
        case photoOutputType
        case videoOutputType
    }
    
    var captureSession: AVCaptureSession?
    var frontCamera: AVCaptureDevice?
    var backCamera: AVCaptureDevice?
    var audioCaptureDevice: AVCaptureDevice?
    
    var currentCameraPosition: CameraPosition?
    var frontCameraInput: AVCaptureDeviceInput?
    var backCameraInput: AVCaptureDeviceInput?
    var photoOutput: AVCapturePhotoOutput?
    var previewLayer: AVCaptureVideoPreviewLayer?
    var flashMode: AVCaptureDevice.FlashMode = AVCaptureDevice.FlashMode.off
    var photoCaptureCompletionBlock: ((UIImage?, Error?) -> Void)?
    var videoRecordCompletionBlock: ((URL?, Error?) -> Void)?
    
    var videoOutput: AVCaptureMovieFileOutput?
    var audioInput: AVCaptureDeviceInput?
    var outputType: OutputType?
}

extension CameraLink {
    
    func setup(handler: @escaping (Error?)-> Void ) {
        
        func createCaptureSession() {
            self.captureSession = AVCaptureSession()
        }
        
        func configureCaptureDevices() throws {
            let session = AVCaptureDevice.DiscoverySession.init(deviceTypes: [.builtInWideAngleCamera], mediaType: AVMediaType.video, position: AVCaptureDevice.Position.unspecified)
            
            let cameras = (session.devices.compactMap{$0})

            for camera in cameras {
                if camera.position == .front {
                    self.frontCamera = camera
                }
                if camera.position == .back {
                    self.backCamera = camera
                    
                    try camera.lockForConfiguration()
                    camera.focusMode = .continuousAutoFocus
                    camera.unlockForConfiguration()
                }
            }
            self.audioCaptureDevice = AVCaptureDevice.default(for: AVMediaType.audio)
        }
        
        //Configure inputs with capture session
        //only allows one camera-based input per capture session at a time.
        func configureDeviceInputs() throws {
            guard let captureSession = self.captureSession else {
                throw CameraError.sessionIsMissing
            }
            
            if let backCamera = self.backCamera {
                self.backCameraInput = try AVCaptureDeviceInput(device: backCamera)
                if captureSession.canAddInput(self.backCameraInput!) {
                    captureSession.addInput(self.backCameraInput!)
                    self.currentCameraPosition = .backPosition
                } else {
                    throw CameraError.inputIsInvalid
                }
            }
                
            else if let frontCamera = self.frontCamera {
                self.frontCameraInput = try AVCaptureDeviceInput(device: frontCamera)
                if captureSession.canAddInput(self.frontCameraInput!) {
                    captureSession.addInput(self.frontCameraInput!)
                    self.currentCameraPosition = .frontPosition
                } else {
                    throw CameraError.inputIsInvalid
                }
            }
                
            else {
                throw CameraError.cameraNotAvailable
            }
            
            if let audioDevice = self.audioCaptureDevice {
                self.audioInput = try AVCaptureDeviceInput(device: audioDevice)
                if captureSession.canAddInput(self.audioInput!) {
                    captureSession.addInput(self.audioInput!)
                } else {
                    throw CameraError.inputIsInvalid
                }
            }
        }
        
        //Configure outputs with capture session
        func configurePhotoOutput() throws {
            guard let captureSession = self.captureSession else {
                throw CameraError.sessionIsMissing
            }
            
            self.photoOutput = AVCapturePhotoOutput()
            self.photoOutput?.setPreparedPhotoSettingsArray([AVCapturePhotoSettings(format: [AVVideoCodecKey : AVVideoCodecType.jpeg ])], completionHandler: nil)
            if captureSession.canAddOutput(self.photoOutput!) {
                captureSession.addOutput(self.photoOutput!)
            }
            self.outputType = .photoOutputType
            captureSession.startRunning()
        }
        
        func configureVideoOutput() throws {
            guard let captureSession = self.captureSession else {
                throw CameraError.sessionIsMissing
            }

            self.videoOutput = AVCaptureMovieFileOutput()
            if captureSession.canAddOutput(self.videoOutput!) {
                captureSession.addOutput(self.videoOutput!)
            }
            
        }
        
        DispatchQueue(label: "setup").async {
            do {
                createCaptureSession()
                try configureCaptureDevices()
                try configureDeviceInputs()
                try configurePhotoOutput()
                try configureVideoOutput()
            } catch {
                DispatchQueue.main.async {
                    handler(error)
                }
                return
            }
            
            DispatchQueue.main.async {
                handler(nil)
            }
        }
    }
    
    func displayPreview(_ view: UIView) throws {
        guard let captureSession = self.captureSession, captureSession.isRunning else { throw CameraError.sessionIsMissing }
        
        self.previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        self.previewLayer?.videoGravity = AVLayerVideoGravity.resizeAspectFill
        self.previewLayer?.connection?.videoOrientation = .portrait
        
        view.layer.insertSublayer(self.previewLayer!, at: 0)
        self.previewLayer?.frame = CGRect(x: 0, y: 0, width: view.frame.width , height: view.frame.height)
    }
    
    func switchCameras() throws {
        guard let currentCameraPosition = currentCameraPosition, let captureSession = self.captureSession, captureSession.isRunning else { throw CameraError.sessionIsMissing }
        captureSession.beginConfiguration()
        let inputs = captureSession.inputs
        
        func switchToFrontCamera() throws {
            guard let backCameraInput = self.backCameraInput, inputs.contains(backCameraInput),let frontCamera = self.frontCamera else { throw CameraError.operationIsInvalid }
            captureSession.removeInput(backCameraInput)
            self.frontCameraInput = try AVCaptureDeviceInput(device: frontCamera)
            if captureSession.canAddInput(self.frontCameraInput!) {
                captureSession.addInput(self.frontCameraInput!)
                self.currentCameraPosition = .frontPosition
            }
            
            else { throw CameraError.operationIsInvalid }
        }
        
        func switchToBackCamera() throws {
            guard let frontCameraInput = self.frontCameraInput, inputs.contains(frontCameraInput), let backCamera = self.backCamera else { throw CameraError.operationIsInvalid }
            captureSession.removeInput(frontCameraInput)
            self.backCameraInput = try AVCaptureDeviceInput(device: backCamera)
            if captureSession.canAddInput(backCameraInput!) {
                captureSession.addInput(backCameraInput!)
                self.currentCameraPosition = .backPosition
            }
            
            else { throw CameraError.operationIsInvalid }
        }
        
        switch currentCameraPosition {
        case .frontPosition:
            try switchToBackCamera()
            
        case .backPosition:
            try switchToFrontCamera()
        }
        captureSession.commitConfiguration()
    }
    
    func captureImage(completion: @escaping (UIImage?, Error?) -> Void) {
        guard let captureSession = self.captureSession, captureSession.isRunning else {
            completion(nil, CameraError.sessionIsMissing)
            return
        }
        let settings = AVCapturePhotoSettings()
        settings.flashMode = self.flashMode
        self.photoOutput?.capturePhoto(with: settings, delegate: self)
        self.photoCaptureCompletionBlock = completion
    }
    
    func recordVideo(completion: @escaping (URL?, Error?)-> Void) {
        guard let captureSession = self.captureSession, captureSession.isRunning else {
            completion(nil, CameraError.sessionIsMissing)
            return
        }
        
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        let fileUrl = paths[0].appendingPathComponent("output.mp4")
        try? FileManager.default.removeItem(at: fileUrl)
        videoOutput!.startRecording(to: fileUrl, recordingDelegate: self)
        self.videoRecordCompletionBlock = completion
    }
    
    func stopRecording(completion: @escaping (Error?)->Void) {
        guard let captureSession = self.captureSession, captureSession.isRunning else {
            completion(CameraError.sessionIsMissing)
            return
        }
        self.videoOutput?.stopRecording()
    }
}

extension CameraLink: AVCapturePhotoCaptureDelegate {
    
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error = error { self.photoCaptureCompletionBlock?(nil, error) }
        if let data = photo.fileDataRepresentation() {
            let image = UIImage(data: data)
            self.photoCaptureCompletionBlock?(image, nil)
        }
        else {
            self.photoCaptureCompletionBlock?(nil, CameraError.other)
        }
    }
    
    func convert(cmage:CIImage) -> UIImage
    {
        let context:CIContext = CIContext.init(options: nil)
        let cgImage:CGImage = context.createCGImage(cmage, from: cmage.extent)!
        let image:UIImage = UIImage.init(cgImage: cgImage)
        return image
    }
    
}

extension CameraLink: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        if error == nil {
            self.videoRecordCompletionBlock?(outputFileURL, nil)
        } else {
            self.videoRecordCompletionBlock?(nil, error)
        }
    }
}
