//
//  ViewController.swift
//  WebViewDemo
//
//  Created by Alexander Mokrushin on 15.02.2024.
//

import UIKit
import WebViewSDK

class ViewController: UIViewController {

    @IBOutlet weak var urlTextField: UITextField!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        navigateToTargetURL()
    }
    
    func navigateToURL(urlString: String) {
        guard urlString != "" else {
            showToast("Empty target URL is received from server")
            return
        }
        let sdkController = WebViewController()
        if let url = URL(string: urlString) {
            do {
                try sdkController.navigateTo(url: url)
                sdkController.modalPresentationStyle = .fullScreen
                sdkController.isExitButtonHidden = true
                present(sdkController, animated: true)
            } catch InvalidUrlError.runtimeError(let message){
                self.showToast(message)
            } catch {
                self.showToast(error.localizedDescription)
            }
        }
    }
    
    func navigateToTargetURL(){
        let session = URLSession.shared
        guard let appVersion = Bundle.main.infoDictionary?["Version"] as? String else {
            showToast("No 'Version' attribute found")
            return
        }
        let urlVersion = appVersion.replacingOccurrences(of: ".", with: "_")
        let url = URL(string: "https://dev-dxp.azurewebsites.net/api/light-show/get-version-url?version=\(urlVersion)")!
        let task = session.dataTask(with: url) { data, response, error in
            if error != nil {
                self.showToast("Client error: \(String(describing: error?.localizedDescription))")
                return
            }
            if data == nil {
                self.showToast("Error: no data loaded")
                return
            }
            guard let response = response as? HTTPURLResponse, (200...299).contains(response.statusCode) else {
                self.showToast("Server error")
                return
            }
            if let target = String(data: data!, encoding: .utf8) {
                DispatchQueue.main.async {
                    self.navigateToURL(urlString: target)
                }
            } else {
                self.showToast("Null URL received")
            }
        }
        task.resume()
    }
}

extension UIViewController{

    func showToast(_ message : String){
        let seconds: Double = 3.0
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.view.backgroundColor = .systemBackground
        alert.view.alpha = 0.5
        alert.view.layer.cornerRadius = 15
        DispatchQueue.main.async {
            self.present(alert, animated: true)
        }
        DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + seconds) {
            alert.dismiss(animated: true)
        }
    }
}
