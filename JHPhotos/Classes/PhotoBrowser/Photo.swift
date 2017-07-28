//
//  Photo.swift
//  JHPhotos
//
//  Created by winter on 2017/6/23.
//  Copyright © 2017年 DJ. All rights reserved.
//

import UIKit
import Photos
import Kingfisher

let PHOTO_PROGRESS_NOTIFICATION = NSNotification.Name(rawValue: "PHOTO_PROGRESS_NOTIFICATION")
let PHOTO_LOADING_DID_END_NOTIFICATION = NSNotification.Name(rawValue:"PHOTO_LOADING_DID_END_NOTIFICATION")

@objc protocol JHPhoto: class {
    
    var numberOfPhotos: Int { get }
    var underlyingImage: UIImage? { get }
    
    func loadUnderlyingImageAndNotify()
    func performLoadUnderlyingImageAndNotify()
    func unloadUnderlyingImage()
    
    @objc var emptyImage: Bool { get }
    func cancelAnyLoading()
}

extension JHPhoto {
    func cancelAnyLoading() {}
}

public class Photo: NSObject, JHPhoto {
    
    var underlyingImage: UIImage?
    var numberOfPhotos: Int = 0
    
    var emptyImage: Bool = true
    
    private var image: UIImage?
    private var photoURL: NSURL?
    private var asset: PHAsset?
    private var assetTargetSize: CGSize! = CGSize.zero
    
    private var hasCancelRequest: Bool = false
    private var kingfisherImageOperation: RetrieveImageDownloadTask?
    private var loadingInProgress: Bool = false
    private var assetRequestID: PHImageRequestID! = PHInvalidImageRequestID
    
//    private var timerCount = 0
//    private let TestConfigure = true
    
    // MARK: - class
    
    class public func photo(image: UIImage) -> Photo {
        return Photo(image: image)
    }
    
    class public func photo(url: NSURL) -> Photo {
        return Photo(url: url)
    }

    class public func photo(asset: PHAsset, targetSize: CGSize) -> Photo {
        return Photo(asset: asset, targetSize: targetSize)
    }
    
    // MARK: - init
    
    public init(image: UIImage) {
        super.init()
        self.image = image
    }
    
    public init(url: NSURL) {
        super.init()
        self.photoURL = url
    }
    
    public init(asset: PHAsset, targetSize: CGSize) {
        super.init()
        self.asset = asset
        self.assetTargetSize = targetSize
    }
    
    deinit {
        self.cancelAnyLoading()
    }
    
    // MARK: - load image
    
    @objc fileprivate func postCompleteNotification() {
        NotificationCenter.default.post(name: PHOTO_LOADING_DID_END_NOTIFICATION, object: self)
    }
    
    @objc fileprivate func imageLoadingComplete() {
        assert(Thread.current.isMainThread, "This method must be called on the main thread.")
        loadingInProgress = false
        self.perform(#selector(postCompleteNotification), with: nil, afterDelay: 0)
    }
    
    fileprivate func cancelImageRequest() {
        if assetRequestID != PHInvalidImageRequestID {
            PHImageManager.default().cancelImageRequest(assetRequestID)
            assetRequestID = PHInvalidImageRequestID
        }
    }
    
//    @objc private func fakeLoad(timer: Timer) {
//        timerCount += 1
//        
//        if timerCount == 100 {
//            timer.invalidate()
//            timerCount = 0
//            
//            postCompleteNotification()
//        }
//        else {
//            let progress = Float(timerCount) / 100
//            let dict = ["progress": progress, "photo": self] as [String : Any]
//            NotificationCenter.default.post(name: PHOTO_PROGRESS_NOTIFICATION, object: nil, userInfo: dict)
//        }
//    }

    private func _handleKingfisherResult(_ result: UIImage?, url: URL?) {
        if hasCancelRequest {
            // 已经取消了请求
            return
        }
        if let image = result {
            self.kingfisherImageOperation = nil
            self.underlyingImage = image
            self.imageLoadingComplete()
        }
        else {
            // 图片未下载
            let downloader = KingfisherManager.shared.downloader
            kingfisherImageOperation = downloader.downloadImage(with: url!,
                                                                retrieveImageTask: nil,
                                                                options: nil,
                                                                progressBlock: { [weak self] (receivedSize, totalSize) in
                                                                    if totalSize > 0 {
                                                                        if let strongSelf = self {
                                                                            let progress = Float(receivedSize) / Float(totalSize)
                                                                            let dict = ["progress": progress, "photo": strongSelf] as [String : Any]
                                                                            NotificationCenter.default.post(name: PHOTO_PROGRESS_NOTIFICATION, object: nil, userInfo: dict)
                                                                        }
                                                                    }
                                                                },
                                                                completionHandler: { [weak self] (image, error, imageUrl, data) in
                                                                    if let strongSelf = self {
                                                                        if error != nil {
                                                                            print("Kingfisher failed to download image: \(String(describing: error))")
                                                                            strongSelf.kingfisherImageOperation = nil
                                                                            strongSelf.imageLoadingComplete()
                                                                        }
                                                                        strongSelf.kingfisherImageOperation = nil
                                                                        strongSelf.underlyingImage = image
                                                                        DispatchQueue.main.async {
                                                                            strongSelf.imageLoadingComplete()
                                                                        }
                                                                    }
                                                                    else {
                                                                        print("Kingfisher failed to download image: \(String(describing: error))")
                                                                    }
                                                                })
//            print("downloadImage Operation \(String(describing: kingfisherImageOperation))");
        }
    }
    
    fileprivate func _performLoadUnderlyingImageAndNotifyWithWebURL(url: NSURL) {
        
//        guard !TestConfigure else {
//            Timer.scheduledTimer(timeInterval: 0.1, target: self, selector: #selector(fakeLoad(timer:)), userInfo: nil, repeats: true)
//            return
//        }
        
        hasCancelRequest = false
        let kfManager = KingfisherManager.shared
        let cache = kfManager.cache
        let optionsInfo: KingfisherOptionsInfo = [.targetCache(cache), .backgroundDecode]
        let resource = ImageResource(downloadURL: url as URL)
        // 先使用缓存，没有缓存再去下载
        kfManager.retrieveImage(with: resource,
                                options: optionsInfo,
                                progressBlock: { [weak self] (receivedSize, totalSize) in
                                    if let strongSelf = self {
                                        if totalSize > 0 {
                                            let progress = Float(receivedSize) / Float(totalSize)
                                            let dict = ["progress": progress, "photo": strongSelf] as [String : Any]
                                            NotificationCenter.default.post(name: PHOTO_PROGRESS_NOTIFICATION, object: nil, userInfo: dict)
                                        }
                                    }
                                },
                                completionHandler:{ [weak self] (image, error, cacheType, Url) in
                                    if let strongSelf = self {
                                        DispatchQueue.main.async {
                                            if error == nil {
                                                strongSelf._handleKingfisherResult(image, url: Url)
                                            }
                                            else {
                                                strongSelf._handleKingfisherResult(nil, url: Url)
                                            }
                                        }
                                    }
                                    else {
                                        print("Kingfisher failed to download image: \(String(describing: error))")
                                    }
                                })
    }
    
    fileprivate func _performLoadUnderlyingImageAndNotifyWithLocalFileURL(url: NSURL) {
        DispatchQueue.global(qos: .default).async {
            autoreleasepool(invoking: { [weak self] () -> Void in
                if let strongSelf = self {
                    if let image = UIImage(contentsOfFile: url.path!) {
                        strongSelf.underlyingImage = image
                    }
                    else {
                        strongSelf.performSelector(onMainThread: #selector(strongSelf.imageLoadingComplete), with: nil, waitUntilDone: false)
                    }
                }
            })
        }
    }
    
    // Load from photos library
    fileprivate func _performLoadUnderlyingImageAndNotifyWithAsset(asset: PHAsset, targetSize: CGSize) {
        let options = PHImageRequestOptions.init()
        options.isNetworkAccessAllowed = true
        options.resizeMode = .fast
        options.deliveryMode = .highQualityFormat
        options.isSynchronous = false
        options.progressHandler = { [weak self] (progress, error, stop, info) -> Void in
            if let strongSelf = self {
                let dict = ["progress": progress, "photo": strongSelf] as [String : Any]
                NotificationCenter.default.post(name: PHOTO_PROGRESS_NOTIFICATION, object: nil, userInfo: dict)
            }
        }
        
        assetRequestID = PHImageManager.default().requestImage(for: asset, targetSize: targetSize, contentMode: .aspectFit, options: options, resultHandler: { [weak self] (result, info) in
            if let strongSelf = self {
                DispatchQueue.main.async {
                    strongSelf.underlyingImage = result
                    strongSelf.imageLoadingComplete()
                }
            }
        })
    }
    
    // MARK: - protocol
    
    func cancelAnyLoading() {
        hasCancelRequest = true
        kingfisherImageOperation?.cancel()
        loadingInProgress = false
        self.cancelImageRequest()
    }

    func unloadUnderlyingImage() {
        loadingInProgress = false
        self.underlyingImage = nil
    }

    func loadUnderlyingImageAndNotify() {
        assert(Thread.current.isMainThread, "This method must be called on the main thread.")
        if loadingInProgress { return }
        loadingInProgress = true
        
        do {
            if self.underlyingImage != nil {
                self.imageLoadingComplete()
            }
            else {
                self.performLoadUnderlyingImageAndNotify()
            }
        }
//        catch {
//            self.underlyingImage = nil
//            loadingInProgress = false
//            self.imageLoadingComplete()
//            print(error.localizedDescription)
//        }
    }
    
    func performLoadUnderlyingImageAndNotify() {
        // Get underlying image
        if image != nil {
            // we have the image
            self.underlyingImage = image
            self.imageLoadingComplete()
        }
        else if let photoURL = photoURL {
            // Check what type of url it is
            if photoURL.isFileReferenceURL() {
                // load from local file async
                self._performLoadUnderlyingImageAndNotifyWithLocalFileURL(url: photoURL)
            }
            else {
                // load async from web 
                self._performLoadUnderlyingImageAndNotifyWithWebURL(url: photoURL)
            }
        }
        else if asset != nil {
            // load from photos asset
            self._performLoadUnderlyingImageAndNotifyWithAsset(asset: asset!, targetSize: assetTargetSize)
        }
        else {
            // image is empty
            self.imageLoadingComplete()
        }
    }
}
