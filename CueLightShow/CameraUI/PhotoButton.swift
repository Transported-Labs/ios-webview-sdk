//
//  PhotoButton.swift
//  CueLightShow
//
//  Created by Alexander Mokrushin on 23.10.2023.
//

import UIKit

class PhotoButton: UIButton {

    override var intrinsicContentSize: CGSize {
        CGSize(width: 64, height: 64)
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .white
        layer.cornerRadius = intrinsicContentSize.height / 2
        layer.borderWidth = 4
        layer.borderColor = UIColor.white.cgColor
        clipsToBounds = true
        translatesAutoresizingMaskIntoConstraints = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
