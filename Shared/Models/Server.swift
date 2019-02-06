//
//  Server.swift
//  OpenArchive
//
//  Created by Benjamin Erhart on 09.07.18.
//  Copyright © 2018 Open Archive. All rights reserved.
//

import UIKit
import Alamofire

class Server: NSObject, NSCoding {

    /**
     Callback executed when monitoring upload progress.

     - parameter server: The calling object.
     - parameter progress: Progress information.
    */
    public typealias ProgressHandler = (_ server: Server, _ progress: Progress) -> Void

    /**
     Callback executed when upload is done. Check `isUploaded` and `error` of the `Server` object
     to evaluate the success.

     - parameter server: The calling object.
    */
    public typealias DoneHandler = (_ server: Server) -> Void

    static let sessionConf: URLSessionConfiguration = {
        let conf = URLSessionConfiguration.background(withIdentifier:
            "org.open-archive.OpenArchive.background")
        conf.sharedContainerIdentifier = Constants.appGroup

        return conf
    }()

    let id: String

    init(_ id: String = "___invalid_id___") {
        self.id = id

        super.init()
    }

    // MARK: NSCoding

    required init(coder decoder: NSCoder) {
        id = decoder.decodeObject() as! String
    }

    func encode(with coder: NSCoder) {
        coder.encode(id)
    }


    // MARK: Methods

    /**
     Subclasses need to return a pretty name to show in the UI.

     - returns: A pretty name of this server.
    */
    func getPrettyName() -> String {
        preconditionFailure("This method must be overridden.")
    }

    /**
     Subclasses need to implement this method to upload assets.

     - parameter asset: The asset to upload.
     - parameter progress: Callback to communicate upload progress.
     - parameter done: Callback to indicate end of upload. Check server object for status!
    */
    func upload(_ asset: Asset, progress: @escaping ProgressHandler, done: @escaping DoneHandler) {
        preconditionFailure("This method must be overridden.")
    }

    /**
     Subclasses need to implement this method to remove assets from server.

     - parameter asset: The asset to remove.
    */
    func remove(_ asset: Asset, done: @escaping DoneHandler) {
        preconditionFailure("This method must be overridden.")
    }


    // MARK: NSObject

    override var description: String {
        return "\(String(describing: type(of: self))): [id=\(id)]"
    }
}
