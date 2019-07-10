//
//  Conduit.swift
//  OpenArchive
//
//  Created by Benjamin Erhart on 03.07.19.
//  Copyright © 2019 Open Archive. All rights reserved.
//

import Foundation
import Alamofire
import FilesProvider

/**
 A conduit implements #upload and #remove methods to interact with a certain
 type of `Space`.
 */
class Conduit {

    /**
     This needs to be tied to an object, otherwise the SessionManager will get
     destroyed during the request and the request will break with error -999.

     See [Getting code=-999 using custom SessionManager](https://github.com/Alamofire/Alamofire/issues/1684)
     */
    static var sessionManager: SessionManager = {
        let conf = URLSessionConfiguration.background(withIdentifier:
            "\(Bundle.main.bundleIdentifier ?? "").background")
        conf.sharedContainerIdentifier = Constants.appGroup

        // Fix error "CredStore - performQuery - Error copying matching creds."
        conf.urlCredentialStorage = nil

        conf.httpAdditionalHeaders = SessionManager.defaultHTTPHeaders

        conf.isDiscretionary = false
        conf.shouldUseExtendedBackgroundIdleMode = true

        return SessionManager(configuration: conf, delegate: UploadManager.shared)
    }()

    /**
     A pretty-printing JSON encoder using ISO8601 date formats.
     */
    static let jsonEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        encoder.dateEncodingStrategy = .iso8601

        return encoder
    }()


    /**
     Evaluate the given `Asset`s `Space` and return the correct type of `Conduit`,
     if any available.

     - parameter asset: The `Asset` the `Conduit` is for.
    */
    class func get(for asset: Asset) -> Conduit? {
        if let space = asset.space {
            if space is WebDavSpace {
                return WebDavConduit(asset)
            }

            if space is IaSpace {
                return IaConduit(asset)
            }
        }

        return nil
    }

    /**
     Callback executed when upload/remove is done. Check `isUploaded` and `error`
     of the `Asset` object to evaluate the success.

     - parameter asset: The asset which was uploaded/removed.
     */
    public typealias DoneHandler = (_ asset: Asset) -> Void


    var asset: Asset

    init(_ asset: Asset) {
        self.asset = asset
    }


    // MARK: "Abstract" Methods

    /**
     Subclasses need to implement this method to upload assets.

     When done, subclasses need to post a `uploadManagerDone` notification with
     the `Upload.id` as the object.

     - parameter uploadId: The ID of the upload object which identifies this upload.
     - returns: Progress to track upload progress
     */
    func upload(uploadId: String) -> Progress {
        preconditionFailure("This method must be overridden.")
    }

    /**
     Subclasses need to implement this method to remove assets from server.

     - parameter asset: The asset to remove.
     */
    func remove(done: @escaping DoneHandler) {
        preconditionFailure("This method must be overridden.")
    }


    // MARK: Public Methods

    /**
     Uploads a file to a destination.

     This method deliberatly doesn't use the FilesProvider library, but Alamofire
     instead, since FilesProvider's latest version fails on uploading the
     metadata for an unkown reason. Addtionally, it's easier with the background
     upload, when using Alamofire directly.

     - parameter file: The file on the local file system.
     - parameter to: The destination on the WebDAV server.
     - parameter credential: The credentials to authenticate with.
     - parameter headers: Addtitional request headers.
     - parameter progress: The main progress to report on.
     - parameter completionHandler: The callback to call when the copy is done,
     or when an error happened.
     */
    func upload(_ file: URL, to: URL, _ progress: Progress, credential: URLCredential? = nil,
                headers: HTTPHeaders? = nil, _ completionHandler: SimpleCompletionHandler = nil) {

        let start = progress.completedUnitCount
        let share = progress.totalUnitCount - start

        let req = Conduit.sessionManager.upload(file, to: to, method: .put, headers: headers)
            .validate(statusCode: 200..<300)
            .uploadProgress {
                progress.completedUnitCount = start + $0.completedUnitCount * share / $0.totalUnitCount
            }
            .responseData { response in
                completionHandler?(response.error)
        }

        if let credential = credential {
            req.authenticate(usingCredential: credential)
        }

        #if DEBUG
        _ = req.debug()
        #endif
    }

    /**
     Boilerplate reducer. Sets an error on the `userInfo` notification object,
     if any provided and posts the `.uploadManagerDone` notification.

     You can even call it like this to reduce LOCs:

     ```Swift
     return self.done(uploadId)
     ```

     - parameter uploadId: The `ID` of the tracked upload.
     - parameter error: An optional `Error`, defaults to `nil`.
     - parameter url: An optional `URL`, where the file was uploaded to. Defaults to `nil`. Will only be set if error == nil.
     */
    func done(_ uploadId: String, error: Error? = nil, url: URL? = nil) {
        var userInfo = [AnyHashable: Any]()

        if let error = error {
            userInfo[.error] = error
        }
        else if let url = url {
            userInfo[.url] = url
        }

        NotificationCenter.default.post(name: .uploadManagerDone, object: uploadId,
                                        userInfo: userInfo)
    }


    // MARK: Helper Methods


    /**
     Construct a correct URL from given path components.

     If you don't provide any components, returns an empty file URL.

     - parameter url: The base `URL` to start from. Optional, defaults to nil.
     - parameter components: 0 or more path components.
     - returns: a new `URL` object constructed from the parameters.
     */
    func construct(url: String, _ components: String...) -> URL {
        return construct(url: URL(string: url), components)
    }

    /**
     Construct a correct URL from given path components.

     If you don't provide any components, returns an empty file URL.

     - parameter url: The base `URL` to start from. Optional, defaults to nil.
     - parameter components: 0 or more path components.
     - returns: a new `URL` object constructed from the parameters.
     */
    func construct(url: URL? = nil, _ components: String...) -> URL {
        return construct(url: url, components)
    }

    /**
     Construct a correct URL from given path components.

     If you don't provide any components, returns an empty file URL.

     - parameter url: The base `URL` to start from. Optional, defaults to nil.
     - parameter components: 0 or more path components.
     - returns: a new `URL` object constructed from the parameters.
     */
    func construct(url: URL? = nil, _ components: [String]) -> URL {
        if let first = components.first {

            var url = url?.appendingPathComponent(first) ?? URL(fileURLWithPath: first)

            var components = components
            components.remove(at: 0)

            for component in components {
                url.appendPathComponent(component)
            }

            return url
        }

        return url ?? URL(fileURLWithPath: "")
    }
}
