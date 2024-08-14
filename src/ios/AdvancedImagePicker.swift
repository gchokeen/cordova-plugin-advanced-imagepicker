import YPImagePicker
import UIKit
import CoreGraphics
import Accelerate

@objc(AdvancedImagePicker) class AdvancedImagePicker : CDVPlugin  {

    var _callbackId: String?
    var OWN_PREFIX: String?

    @objc(pluginInitialize)
    override func pluginInitialize() {
        super.pluginInitialize()
        self.OWN_PREFIX = "advanced_image_picker_";
    }

    @objc(present:)
    func present(command: CDVInvokedUrlCommand) {
        _callbackId = command.callbackId;
        let options = command.argument(at: 0) as? NSDictionary;
        if(options == nil) {
            self.returnError(error: ErrorCodes.WrongJsonObject, message: "The first Argument must be the Configuration");
            return;
        }

        let mediaType = options?.value(forKey: "mediaType") as? String ?? "IMAGE";
        let startOnScreen = options?.value(forKey: "startOnScreen") as? String ?? "LIBRARY";
        let showCameraTile = options?.value(forKey: "showCameraTile") as? Bool ?? true;
        let min = options?.value(forKey: "min") as? NSInteger ?? 1;
        let max = options?.value(forKey: "max") as? NSInteger ?? 1;
        let defaultMaxCountMessage = "You can select a maximum of " + String(max) + " files";
        let maxCountMessage = options?.value(forKey: "maxCountMessage") as? String ?? defaultMaxCountMessage;
        let buttonText = options?.value(forKey: "buttonText") as? String ?? "";
        let asBase64 = options?.value(forKey: "asBase64") as? Bool ?? false;
        let videoCompression = options?.value(forKey: "videoCompression") as? String ?? "AVAssetExportPresetHighestQuality";
        let asJpeg = options?.value(forKey: "asJpeg") as? Bool ?? false;
        let recordingTimeLimit = options?.value(forKey: "recordingTimeLimit") as? Double ?? 60.0;
        let libraryTimeLimit = options?.value(forKey: "libraryTimeLimit") as? Double ?? 60.0;
        let minimumTimeLimit = options?.value(forKey: "minimumTimeLimit") as? Double ?? 3.0;


        
        if(max < 0 || min < 0) {
            self.returnError(error: ErrorCodes.WrongJsonObject, message: "Min and Max can not be less then zero.");
            return;
        }

        if(max < min) {
            self.returnError(error: ErrorCodes.WrongJsonObject, message: "Max can not be smaller than Min.");
            return;
        }

        var config = YPImagePickerConfiguration();
        config.onlySquareImagesFromCamera = false;
        config.showsPhotoFilters = false;
        config.showsVideoTrimmer = false;
        config.shouldSaveNewPicturesToAlbum = false;
        config.albumName = Bundle.main.infoDictionary![kCFBundleNameKey as String] as! String;
        config.library.isSquareByDefault = false;
        config.library.itemOverlayType = .none;
        config.library.skipSelectionsGallery = true;
        config.library.preSelectItemOnMultipleSelection = false;
        config.video.compression = videoCompression;
        config.video.recordingTimeLimit = recordingTimeLimit;
        config.video.libraryTimeLimit = libraryTimeLimit;
        config.video.minimumTimeLimit = minimumTimeLimit;
        //config.quality = quality;


        if(startOnScreen == "IMAGE") {
            config.startOnScreen = .photo;
        } else if(startOnScreen == "VIDEO") {
            config.startOnScreen = .video;
        } else {
            config.startOnScreen = .library;
        }

        var screens: [YPPickerScreen] = [.library];
        if(showCameraTile) {
            if(mediaType != "VIDEO") {
                screens.append(.photo);
            }
            if(mediaType != "IMAGE") {
                screens.append(.video);
            }
        }
        config.screens = screens;
        config.library.defaultMultipleSelection = (max > 1);
        if(mediaType == "IMAGE") {
            config.library.mediaType = YPlibraryMediaType.photo
        } else if(mediaType == "VIDEO") {
            config.library.mediaType = YPlibraryMediaType.video
        } else {
            config.library.mediaType = YPlibraryMediaType.photoAndVideo
        }
        config.library.minNumberOfItems = min;
        config.library.maxNumberOfItems = max;
        config.wordings.warningMaxItemsLimit = maxCountMessage;
        if(buttonText != "") {
            config.wordings.next = buttonText;
        }

        let picker = YPImagePicker(configuration: config);

        if #available(iOS 15.0, *) {
            let navBarAppearance = UINavigationBarAppearance()
            navBarAppearance.configureWithOpaqueBackground()
            picker.navigationBar.scrollEdgeAppearance = navBarAppearance
        }

        picker.didFinishPicking {items, cancelled in
            if(cancelled) {
                self.returnError(error: ErrorCodes.PickerCanceled)
            } else if(items.count > 0) {
                self.handleResult(items: items, asBase64: asBase64, asJpeg: asJpeg);
            }
            picker.dismiss(animated: true, completion: nil);
        }

        self.viewController.present(picker, animated: true, completion: nil);
    }

    func handleResult(items: [YPMediaItem], asBase64: Bool, asJpeg: Bool) {
        var array = [] as Array;
        for item in items {
            switch item {
            case .photo(let photo):
                let encodedImage = self.encodeImage(image: photo.image, asBase64: asBase64, asJpeg: asJpeg);
                array.append([
                    "type": "image",
                    "isBase64": asBase64,
                    "src": encodedImage
                ]);
                break;
            case .video(let video):
                var resultSrc:String;
                if(asBase64) {
                    resultSrc = self.encodeVideo(url: video.url);
                    if(resultSrc == "") {
                        self.returnError(error: ErrorCodes.UnknownError, message: "Failed to encode Video")
                        return;
                    }
                } else {
                    resultSrc = video.url.absoluteString;
                }
                array.append([
                    "type": "video",
                    "isBase64": asBase64,
                    "src": resultSrc
                ]);
                break;
            }
        }
        let result:CDVPluginResult = CDVPluginResult(status: CDVCommandStatus_OK, messageAs: array);
        self.commandDelegate.send(result, callbackId: _callbackId)
    }

    
    func encodeImage(image: UIImage, asBase64: Bool, asJpeg: Bool) -> String {
        let imageData: NSData;
        
        let scaledImage = image.resizeWithScaleAspectFitMode(to:1080)
        
        if(asJpeg) {
           imageData = UIImageJPEGRepresentation(scaledImage!,0.5)! as NSData;
        } else {
           imageData = UIImagePNGRepresentation(scaledImage!)! as NSData;
        }
        
        if(asBase64) {
            return imageData.base64EncodedString();
        } else {
            let filePath = self.tempFilePath();
            do {
                try imageData.write(to: filePath, options: .atomic);
                return filePath.absoluteString;
            } catch {
                return error.localizedDescription;
            }
        }
    }

    func tempFilePath(ext: String = "png") -> URL {
        let filename: String = self.OWN_PREFIX! + UUID().uuidString;
        var contentUrl = URL(fileURLWithPath: NSTemporaryDirectory());
        contentUrl.appendPathComponent(filename);
        contentUrl.appendPathExtension(ext);
        return contentUrl;
    }

    func encodeVideo(url: URL) -> String {
        do {
            let fileData = try Data.init(contentsOf: url)
            return fileData.base64EncodedString();
        } catch {
            return "";
        }
    }

    func returnError(callbackId: String?, error: ErrorCodes, message: String = "") {
        if(callbackId != nil) {
            let result:CDVPluginResult = CDVPluginResult(
                status: CDVCommandStatus_ERROR, messageAs: [
                    "code": error.rawValue,
                    "message": message
            ]);
            self.commandDelegate.send(result, callbackId: callbackId)
        }
    }

    func returnError(error: ErrorCodes, message: String = "") {
        self.returnError(callbackId: _callbackId, error: error, message: message)
        _callbackId = nil;
    }

    @objc(cleanup:)
    func cleanup(command: CDVInvokedUrlCommand) {
        do {
            let tmpFiles: [String] = try FileManager().contentsOfDirectory(atPath: NSTemporaryDirectory());
            for tmpFile in tmpFiles {
                // only delete files from this plugin:
                if(tmpFile.hasPrefix(self.OWN_PREFIX!)) {
                    try FileManager().removeItem(atPath: NSTemporaryDirectory() + tmpFile)
                }
            }
        } catch {
            returnError(callbackId: command.callbackId, error: ErrorCodes.UnknownError, message: error.localizedDescription);
            return;
        }
        let result:CDVPluginResult = CDVPluginResult(status: CDVCommandStatus_OK);
        self.commandDelegate.send(result, callbackId: command.callbackId);
    }

    enum ErrorCodes:NSNumber {
        case UnsupportedAction = 1
        case WrongJsonObject = 2
        case PickerCanceled = 3
        case UnknownError = 10
    }
}






extension UIImage {

    public enum ResizeFramework {
        case uikit, coreImage, coreGraphics, imageIO, accelerate
    }

    /// Resize image with ScaleAspectFit mode and given size.
    ///
    /// - Parameter dimension: width or length of the image output.
    /// - Parameter resizeFramework: Technique for image resizing: UIKit / CoreImage / CoreGraphics / ImageIO / Accelerate.
    /// - Returns: Resized image.

    func resizeWithScaleAspectFitMode(to dimension: CGFloat, resizeFramework: ResizeFramework = .coreGraphics) -> UIImage? {

        if max(size.width, size.height) <= dimension { return self }

        var newSize: CGSize!
        let aspectRatio = size.width/size.height

        if aspectRatio > 1 {
            // Landscape image
            newSize = CGSize(width: dimension, height: dimension / aspectRatio)
        } else {
            // Portrait image
            newSize = CGSize(width: dimension * aspectRatio, height: dimension)
        }

        return resize(to: newSize, with: resizeFramework)
    }

    /// Resize image from given size.
    ///
    /// - Parameter newSize: Size of the image output.
    /// - Parameter resizeFramework: Technique for image resizing: UIKit / CoreImage / CoreGraphics / ImageIO / Accelerate.
    /// - Returns: Resized image.
    public func resize(to newSize: CGSize, with resizeFramework: ResizeFramework = .coreGraphics) -> UIImage? {
        switch resizeFramework {
            case .uikit: return resizeWithUIKit(to: newSize)
            case .coreGraphics: return resizeWithCoreGraphics(to: newSize)
            case .coreImage: return resizeWithCoreImage(to: newSize)
            case .imageIO: return resizeWithImageIO(to: newSize)
            case .accelerate: return resizeWithAccelerate(to: newSize)
        }
    }

    // MARK: - UIKit

    /// Resize image from given size.
    ///
    /// - Parameter newSize: Size of the image output.
    /// - Returns: Resized image.
    private func resizeWithUIKit(to newSize: CGSize) -> UIImage? {
        UIGraphicsBeginImageContextWithOptions(newSize, true, 1.0)
        self.draw(in: CGRect(origin: .zero, size: newSize))
        defer { UIGraphicsEndImageContext() }
        return UIGraphicsGetImageFromCurrentImageContext()
    }

    // MARK: - CoreImage

    /// Resize CI image from given size.
    ///
    /// - Parameter newSize: Size of the image output.
    /// - Returns: Resized image.
    // https://developer.apple.com/library/archive/documentation/GraphicsImaging/Reference/CoreImageFilterReference/index.html
    private func resizeWithCoreImage(to newSize: CGSize) -> UIImage? {
        guard let cgImage = cgImage, let filter = CIFilter(name: "CILanczosScaleTransform") else { return nil }

        let ciImage = CIImage(cgImage: cgImage)
        let scale = (Double)(newSize.width) / (Double)(ciImage.extent.size.width)

        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(NSNumber(value:scale), forKey: kCIInputScaleKey)
        filter.setValue(1.0, forKey: kCIInputAspectRatioKey)
        guard let outputImage = filter.value(forKey: kCIOutputImageKey) as? CIImage else { return nil }
        let context = CIContext()
        guard let resultCGImage = context.createCGImage(outputImage, from: outputImage.extent) else { return nil }
        return UIImage(cgImage: resultCGImage)
    }

    // MARK: - CoreGraphics

    /// Resize image from given size.
    ///
    /// - Parameter newSize: Size of the image output.
    /// - Returns: Resized image.
    private func resizeWithCoreGraphics(to newSize: CGSize) -> UIImage? {
        guard let cgImage = cgImage, let colorSpace = cgImage.colorSpace else { return nil }

        let width = Int(newSize.width)
        let height = Int(newSize.height)
        let bitsPerComponent = cgImage.bitsPerComponent
        let bytesPerRow = cgImage.bytesPerRow
        let bitmapInfo = cgImage.bitmapInfo

        guard let context = CGContext(data: nil, width: width, height: height,
                                      bitsPerComponent: bitsPerComponent,
                                      bytesPerRow: bytesPerRow, space: colorSpace,
                                      bitmapInfo: bitmapInfo.rawValue) else { return nil }
        context.interpolationQuality = .high
        let rect = CGRect(origin: CGPoint.zero, size: newSize)
        context.draw(cgImage, in: rect)

        return context.makeImage().flatMap { UIImage(cgImage: $0) }
    }

    // MARK: - ImageIO

    /// Resize image from given size.
    ///
    /// - Parameter newSize: Size of the image output.
    /// - Returns: Resized image.
    private func resizeWithImageIO(to newSize: CGSize) -> UIImage? {
        var resultImage = self

        guard let data = UIImageJPEGRepresentation(resultImage, 1.0) else { return resultImage }
        
        let imageCFData = NSData(data: data) as CFData
        let options = [
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: max(newSize.width, newSize.height)
            ] as CFDictionary
        guard   let source = CGImageSourceCreateWithData(imageCFData, nil),
                let imageReference = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return resultImage }
        resultImage = UIImage(cgImage: imageReference)

        return resultImage
    }

    // MARK: - Accelerate

    /// Resize image from given size.
    ///
    /// - Parameter newSize: Size of the image output.
    /// - Returns: Resized image.
    private func resizeWithAccelerate(to newSize: CGSize) -> UIImage? {
        var resultImage = self

        guard let cgImage = cgImage, let colorSpace = cgImage.colorSpace else { return nil }

        // create a source buffer
        var format = vImage_CGImageFormat(bitsPerComponent: numericCast(cgImage.bitsPerComponent),
                                          bitsPerPixel: numericCast(cgImage.bitsPerPixel),
                                          colorSpace: Unmanaged.passUnretained(colorSpace),
                                          bitmapInfo: cgImage.bitmapInfo,
                                          version: 0,
                                          decode: nil,
                                          renderingIntent: .absoluteColorimetric)
        var sourceBuffer = vImage_Buffer()
        defer {
            sourceBuffer.data.deallocate()
        }

        var error = vImageBuffer_InitWithCGImage(&sourceBuffer, &format, nil, cgImage, numericCast(kvImageNoFlags))
        guard error == kvImageNoError else { return resultImage }

        // create a destination buffer
        let destWidth = Int(newSize.width)
        let destHeight = Int(newSize.height)
        let bytesPerPixel = cgImage.bitsPerPixel
        let destBytesPerRow = destWidth * bytesPerPixel
        let destData = UnsafeMutablePointer<UInt8>.allocate(capacity: destHeight * destBytesPerRow)
        defer {
            destData.deallocate()
        }
        var destBuffer = vImage_Buffer(data: destData, height: vImagePixelCount(destHeight), width: vImagePixelCount(destWidth), rowBytes: destBytesPerRow)

        // scale the image
        error = vImageScale_ARGB8888(&sourceBuffer, &destBuffer, nil, numericCast(kvImageHighQualityResampling))
        guard error == kvImageNoError else { return resultImage }

        // create a CGImage from vImage_Buffer
        let destCGImage = vImageCreateCGImageFromBuffer(&destBuffer, &format, nil, nil, numericCast(kvImageNoFlags), &error)?.takeRetainedValue()
        guard error == kvImageNoError else { return resultImage }

        // create a UIImage
        if let scaledImage = destCGImage.flatMap({ UIImage(cgImage: $0) }) {
            resultImage = scaledImage
        }

        return resultImage
    }
}
