//
//  BottomBar.swift
//  WebViewSDK
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

    private var cameraLayout: CameraLayout = .both
    private lazy var photoButton = PhotoButton()
    private lazy var videoButton = VideoButton()
    
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

    init(cameraLayout: CameraLayout) {
        super.init(frame: .zero)
        self.cameraLayout = cameraLayout
        setUpUI()
    }
    
    override init(frame: CGRect) {
        super.init(frame: .zero)

        setUpUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setUpUI() {
        backgroundColor = .black.withAlphaComponent(0.5)
        translatesAutoresizingMaskIntoConstraints = false
        addSubview(exitButton)
        switch cameraLayout {
        case .both:
            addSubview(photoButton)
            addSubview(videoButton)
            videoButton.centerXAnchor.constraint(equalTo: centerXAnchor).isActive = true
            videoButton.centerYAnchor.constraint(equalTo: centerYAnchor).isActive = true
            photoButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20).isActive = true
            photoButton.centerYAnchor.constraint(equalTo: centerYAnchor).isActive = true
        case .photoOnly:
            addSubview(photoButton)
            photoButton.centerXAnchor.constraint(equalTo: centerXAnchor).isActive = true
            photoButton.centerYAnchor.constraint(equalTo: centerYAnchor).isActive = true
        case .videoOnly:
            addSubview(videoButton)
            videoButton.centerXAnchor.constraint(equalTo: centerXAnchor).isActive = true
            videoButton.centerYAnchor.constraint(equalTo: centerYAnchor).isActive = true
        }

        exitButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20).isActive = true
        exitButton.centerYAnchor.constraint(equalTo: centerYAnchor).isActive = true
        exitButton.widthAnchor.constraint(equalToConstant: 64).isActive = true
        exitButton.heightAnchor.constraint(equalToConstant: 64).isActive = true

        photoButton.addTarget(self, action: #selector(photoButtonPressed(_:)), for: .touchUpInside)
        videoButton.addTarget(self, action: #selector(videoButtonPressed(_:)), for: .touchUpInside)
        exitButton.addTarget(self, action: #selector(exitButtonPressed(_:)), for: .touchUpInside)
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
