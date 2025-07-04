//
//  CameraController.swift
//  CueLightShow
//
//  Created by Alexander Mokrushin on 23.10.2023.
//

import UIKit
import AVFoundation

enum CameraLayout {
    case both
    case photoOnly
    case videoOnly
}

class CameraController: UIViewController {

    private lazy var previewArea: UIImageView = {
        let view = UIImageView()
        view.backgroundColor = .black
        view.isUserInteractionEnabled = false
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private lazy var waitingSpinner: UIActivityIndicatorView = {
        #if swift(>=4.2)
        let spinner = UIActivityIndicatorView(style: .large)
        #else
        let spinner = UIActivityIndicatorView(activityIndicatorStyle: UIActivityIndicatorViewStyle.large)
        #endif
        
        spinner.color = .white
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.startAnimating()
        return spinner
    }()
    
    private var cueSDK: CueSDK!
    private var bottomBar: BottomBar!
    private lazy var cameraLink = CameraLink()
    
    init(cueSDK: CueSDK) {
        super.init(nibName: nil, bundle: nil)
        self.cueSDK = cueSDK
        self.bottomBar = BottomBar()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        cameraLink.stopSession()
        cueSDK.stopAudioSession()
    }

    private func prepareCameraLink() {
        bottomBar.setButtonsHidden(isHidden: true)
        waitingSpinner.isHidden = false
        cueSDK.isTorchLocked = true
        cameraLink.turnTorchOff()
        
        // Set the custom session interruption handler
        cameraLink.onSessionInterrupted = { [self] message in
            print("Capture Session Interrupted: \(message)")
            if bottomBar.cameraLayout != .photoOnly {
                bottomBar.resetVideoRecordingStatus()
            }
        }
        cameraLink.setup { [self] (error) in
            if error != nil {
                showToast(message: "Camera cannot be prepared, try again later")
                print("Camera SETUP Error: \(String(describing: error?.localizedDescription))")
            } else {
                do {
                    try cameraLink.displayPreview(previewArea) { [self] in
                        bottomBar.setButtonsHidden(isHidden: false)
                    }
                } catch {
                    showToast(message: "Preview cannot be prepared, try again later")
                    print("Camera PREVIEW Error: sessionIsMissing")
                }
            }
            cueSDK.isTorchLocked = false
            waitingSpinner.isHidden = true
        }
    }
    
    func turnTorchOff() {
        cameraLink.turnTorchOff()
    }
    
    func initBottomBar(cameraLayout: CameraLayout) {
        bottomBar.cameraLayout = cameraLayout
    }
    
    func checkSessionIsStarted() {
        prepareCameraLink()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        checkSessionIsStarted()
    }

    private func setupUI() {
        view.addSubview(previewArea)
        previewArea.leadingAnchor.constraint(equalTo: view.leadingAnchor).isActive = true
        previewArea.trailingAnchor.constraint(equalTo: view.trailingAnchor).isActive = true
        previewArea.topAnchor.constraint(equalTo: view.topAnchor).isActive = true
        previewArea.bottomAnchor.constraint(equalTo: view.bottomAnchor).isActive = true

        view.addSubview(bottomBar)
        bottomBar.delegate = self
        bottomBar.bottomAnchor.constraint(equalTo: view.bottomAnchor).isActive = true
        bottomBar.leadingAnchor.constraint(equalTo: view.leadingAnchor).isActive = true
        bottomBar.trailingAnchor.constraint(equalTo: view.trailingAnchor).isActive = true
        bottomBar.heightAnchor.constraint(equalTo: view.heightAnchor, multiplier: 0.16).isActive = true
        
        view.addSubview(waitingSpinner)
        waitingSpinner.centerXAnchor.constraint(equalTo: view.centerXAnchor).isActive = true
        waitingSpinner.centerYAnchor.constraint(equalTo: view.centerYAnchor).isActive = true
    }
    
    @objc func image(_ image: UIImage, didFinishSavingWithError error: NSError?, contextInfo: UnsafeRawPointer) {
        if error != nil {
            showToast(message: "Could not save photo, try again later")
        } else {
            showToast(message: "Photo has been saved")
        }
    }
    
    @objc func video(_ video: String, didFinishSavingWithError error: NSError?, contextInfo: UnsafeRawPointer) {
        if error != nil {
            showToast(message: "Could not save video, try again later")
        } else {
            showToast(message: "Video has been saved")
        }
    }
}

extension CameraController: BottomBarDelegate {
    func photoButtonPressed() {
        cameraLink.captureImage { (image, error) in
            guard let image = image else {
                self.showToast(message: "Photo capture error, try again later")
                print("Photo capture error \(String(describing: error))")
                return
            }
            UIImageWriteToSavedPhotosAlbum(image, self, #selector(self.image(_:didFinishSavingWithError:contextInfo:)), nil)
        }
    }
    
    func videoButtonPressed(isRecording: Bool) {
        if !isRecording {
            cameraLink.stopRecording { (error) in
                self.showToast(message: "Video recording error, try again later")
                print("Video recording error on stop \(String(describing: error))")
            }
        } else {
            cameraLink.recordVideo { (url, error) in
                guard let url = url else {
                    // Reset video recording buttons
                    self.bottomBar.resetVideoRecordingStatus()
                    self.showToast(message: "Video session starting error, try again later")
                    print("Video recording error on start \(String(describing: error))")
                    return
                }
                UISaveVideoAtPathToSavedPhotosAlbum(url.path, self, #selector(self.video(_:didFinishSavingWithError:contextInfo:)), nil)
            }
        }
    }
    
    func exitButtonPressed() {
        // Stop capture session here
        cameraLink.stopSession()
        cueSDK.stopAudioSession()
        dismiss(animated: true, completion: nil)
    }
}

extension UIViewController {
    public func showToast(message : String) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.view.backgroundColor = .black
        alert.view.alpha = 0.5
        alert.view.layer.cornerRadius = 15
        self.present(alert, animated: true)
        DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 2) {
            alert.dismiss(animated: true)
        }
    }
}
