# CueLightShow

This framework contains SDK for CUE Live Lightshow 2.0.

## CocoaPods
To install library using CocoaPods your Podfile should look like the following:
``` swift
# Use iOS platform version 13+
platform :ios, '13.0'
target 'MyCueLights' do
  # Comment the next line if you don't want to use dynamic frameworks
  use_frameworks!  
  # Using CocoaPods
  source 'https://github.com/CocoaPods/Specs.git'
  pod 'CueLightShow', '~> 1.0'
end
```

## SPM
Add the ios-webview-sdk framework using the Package manager in Xcode. Use the URL: `https://github.com/Transported-Labs/ios-webview-sdk.git`

![](images/xcode-1.png)

Once the dialog for the package manager is opened, search for the SPM in the search field at the top right. Enter the following URL to help discover the package: `https://github.com/Transported-Labs/ios-webview-sdk.git`. Set up `Dependency Rule`, if it's needed. Finally press `Add Package` button

![](images/xcode-2.png)

You will see the installed package in Project Navigator in the _Package Dependencies_

![](images/xcode-3.png)

## Setting up description keys for Camera/Microphone/Photo library access

Please write description texts for the following Info.plist keys:

- NSCameraUsageDescription
- NSMicrophoneUsageDescription
- NSPhotoLibraryAddUsageDescription
- NSPhotoLibraryUsageDescription

Result should be looking like that:

![](images/xcode-4.png)


## Integration

Simply execute the following code:

```swift
    @IBAction func navigateButtonPressed(_ sender: Any) {
        let urlString = "<your URL from CUE>"
        if let url = URL(string: urlString) {
            do {
                try sdkController.navigateTo(url: url)
                sdkController.modalPresentationStyle = .fullScreen
                present(sdkController, animated: true)
            } catch InvalidUrlError.runtimeError(let message){
                print("URL is not valid: \(message)")
            } catch {
                // Any other error occured
                print(error.localizedDescription)
            }
        }
    }
```
## Pre-fetch

To pre-fetch lightshow resources is very similar to navigation, but we should keep sdkController hidden and add to URL preload parameter.
Just execute the following code:

```swift
    @IBAction func prefetchButtonPressed(_ sender: Any) {
        let urlString = "<your URL from CUE>"
        // Add parameter to original URL
        if let url = URL(string: "\(urlString)&preload=true") {
            do {
                try sdkController.navigateTo(url: url) {progress in
                    // You can get progress from 0 to 100 during the pre-fetch process
                    self.prefetchButton.setTitle("Fetched:\(progress)%", for: .normal)
                }
            } catch InvalidUrlError.runtimeError(let message){
                print("URL is not valid: \(message)")
            } catch {
                // Any other error occured
                print(error.localizedDescription)
            }
        }
    }
```

## Using PRIVACY flag

You can pass optional PRIVACY flag to prevent collecting and sending to the server any user information. SDK initialization in this case looks like that:

[insert code example] 

## CLIENT_URL_STRING

We do not recommend hard-coding a URL string, as it varies by client. You can set this dynamicaly in your code or via a .plist file. The branding is controlled dynamically. In order to pre-fetch this branding so it shows as soon as the CUE SDK is opened, please execute this code once your app launches:

[INSERT INSTRUCTIONS ON HOW TO DO THIS, SIMILAR TO THIS FROM 1.0: https://github.com/CUEAudio/sdk_demo_ios?tab=readme-ov-file#api-key]

## HOW TO TEST

In order to test, you can play an audio file to trigger a light show with the CUE SDK open. The audio file is specific to the CLIENT_URL_STRING. In order to get the right audio file for your CLIENT_URL_STRING, simply:

[insert instructions on how someone can download the demo audio file based on your client URL string]
