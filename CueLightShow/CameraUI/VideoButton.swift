//
//  VideoButton.swift
//  CueLightShow
//
//  Created by Alexander Mokrushin on 23.10.2023.
//

import UIKit

class VideoButton: UIButton {
    
    override var intrinsicContentSize: CGSize {
        CGSize(width: 64, height: 64)
    }

    private lazy var innerView: UIView = {
        let view = UIView()
        view.backgroundColor = .red
        view.isUserInteractionEnabled = false
        view.clipsToBounds = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    var innerViewWidthAnchor: NSLayoutConstraint? = nil
    var innerViewHeightAnchor: NSLayoutConstraint? = nil
    var isRecording = false {
        didSet {
            setRecording(isRecording)
        }
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .white
        layer.cornerRadius = intrinsicContentSize.height / 2
        layer.borderWidth = 4
        layer.borderColor = UIColor.white.cgColor
        clipsToBounds = true
        translatesAutoresizingMaskIntoConstraints = false
        
        addSubview(innerView)
        innerView.centerXAnchor.constraint(equalTo: centerXAnchor).isActive = true
        innerView.centerYAnchor.constraint(equalTo: centerYAnchor).isActive = true
        innerViewWidthAnchor = innerView.widthAnchor.constraint(equalToConstant: 60)
        innerViewWidthAnchor?.isActive = true
        innerViewHeightAnchor = innerView.heightAnchor.constraint(equalToConstant: 60)
        innerViewHeightAnchor?.isActive = true
        setRecording(false)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func setRecording(_ recording: Bool) {
        if recording {
            UIView.animate(withDuration: 0.3, delay: 0.3) {
                self.innerView.layer.cornerRadius = 30
                self.innerViewWidthAnchor?.constant = 60
                self.innerViewHeightAnchor?.constant = 60
            }
        } else {
            UIView.animate(withDuration: 0.2, delay: 0.0) {
                self.innerView.layer.cornerRadius = 15
                self.innerViewWidthAnchor?.constant = 30
                self.innerViewHeightAnchor?.constant = 30
            }
        }
    }
}
