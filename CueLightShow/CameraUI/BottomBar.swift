//
//  BottomBar.swift
//  CueLightShow
//
//  Created by Alexander Mokrushin on 23.10.2023.
//

import UIKit

protocol BottomBarDelegate: AnyObject {
    func photoButtonPressed()
    func videoButtonPressed()
    func exitButtonPressed()
}

class BottomBar: UIView {

    private lazy var photoButton = PhotoButton()
    private lazy var videoButton = VideoButton()
    var photoButtonLeftAnchor: NSLayoutConstraint? = nil
    var photoButtonMiddleAnchor: NSLayoutConstraint? = nil
    
    private lazy var exitButton: UIButton = {
        let button = UIButton()
        button.tintColor = .white
        button.backgroundColor = .white.withAlphaComponent(0.2)
        button.setImage(UIImage(systemName: "xmark", withConfiguration: UIImage.SymbolConfiguration.init(pointSize: 35)), for: .normal)
        button.imageView?.contentMode = .scaleAspectFill
        button.layer.cornerRadius = 32
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    weak var delegate: BottomBarDelegate?
    
    var cameraLayout: CameraLayout = .both {
        didSet {
            setUpUI()
        }
    }
    
    init() {
        super.init(frame: .zero)
        initUI()
    }
    
    override init(frame: CGRect) {
        super.init(frame: .zero)
        initUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setButtonsHidden(isHidden: Bool) {
        switch cameraLayout {
        case .both:
            photoButton.isHidden = isHidden
            videoButton.isHidden = isHidden
        case .photoOnly:
            photoButton.isHidden = isHidden
        case .videoOnly:
            videoButton.isHidden = isHidden
        }
    }
    
    private func initUI() {
        backgroundColor = .black.withAlphaComponent(0.5)
        translatesAutoresizingMaskIntoConstraints = false
        addSubview(photoButton)
        addSubview(videoButton)
        addSubview(exitButton)
        // Non-conditional anchors
        videoButton.centerXAnchor.constraint(equalTo: centerXAnchor).isActive = true
        videoButton.centerYAnchor.constraint(equalTo: centerYAnchor).isActive = true
        photoButton.centerYAnchor.constraint(equalTo: centerYAnchor).isActive = true
        exitButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20).isActive = true
        exitButton.centerYAnchor.constraint(equalTo: centerYAnchor).isActive = true
        exitButton.widthAnchor.constraint(equalToConstant: 64).isActive = true
        exitButton.heightAnchor.constraint(equalToConstant: 64).isActive = true
        // Conditional anchors
        photoButtonLeftAnchor = photoButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20)
        photoButtonMiddleAnchor = photoButton.centerXAnchor.constraint(equalTo: centerXAnchor)
        // Tap handlers
        photoButton.addTarget(self, action: #selector(photoButtonPressed(_:)), for: .touchUpInside)
        videoButton.addTarget(self, action: #selector(videoButtonPressed(_:)), for: .touchUpInside)
        exitButton.addTarget(self, action: #selector(exitButtonPressed(_:)), for: .touchUpInside)
    }
    
    private func setUpUI() {
        switch cameraLayout {
        case .both:
            videoButton.isHidden = false
            photoButton.isHidden = false
            photoButtonLeftAnchor?.isActive = true
            photoButtonMiddleAnchor?.isActive = false
        case .photoOnly:
            videoButton.isHidden = true
            photoButton.isHidden = false
            photoButtonLeftAnchor?.isActive = false
            photoButtonMiddleAnchor?.isActive = true
        case .videoOnly:
            photoButton.isHidden = true
            videoButton.isHidden = false
        }
    }

    @objc private func photoButtonPressed(_ sender: UIButton?) {
        delegate?.photoButtonPressed()
    }
    
    @objc private func videoButtonPressed(_ sender: UIButton?) {
        if let videoButton = sender as? VideoButton {
            videoButton.isRecording = !videoButton.isRecording
            if cameraLayout == .both {
                photoButton.isHidden  = videoButton.isRecording
            }
            exitButton.isHidden  = videoButton.isRecording
        }
        delegate?.videoButtonPressed()
    }

    @objc private func exitButtonPressed(_ sender: UIButton?) {
        delegate?.exitButtonPressed()
    }

}
