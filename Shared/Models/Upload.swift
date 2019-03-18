//
//  Upload.swift
//  OpenArchive
//
//  Created by Benjamin Erhart on 11.03.19.
//  Copyright © 2019 Open Archive. All rights reserved.
//

import UIKit
import DownloadButton
import YapDatabase

class Upload: NSObject, Item {

    // MARK: Item

    static let collection  = "uploads"

    static func fixArchiverName() {
        NSKeyedArchiver.setClassName("Upload", for: self)
        NSKeyedUnarchiver.setClass(self, forClassName: "Upload")
    }

    func compare(_ rhs: Upload) -> ComparisonResult {
        if order < rhs.order {
            return .orderedAscending
        }

        if order > rhs.order {
            return .orderedDescending
        }

        return .orderedSame
    }

    var id: String


    // MARK: Upload

    /**
     Remove uploads identified by their IDs and reorder the others, if necessary.

     - parameter ids: A list of upload IDs to remove.
    */
    class func remove(ids: [String]) {
        Db.writeConn?.asyncReadWrite { transaction in
            for id in ids {
                transaction.removeObject(forKey: id, inCollection: collection)
            }

            // Reorder uploads.
            (transaction.ext(UploadsView.name) as? YapDatabaseViewTransaction)?
                .enumerateKeysAndObjects(inGroup: UploadsView.groups[0])
                { collection, key, object, index, stop in
                    if let upload = object as? Upload,
                        upload.order != index {

                        upload.order = Int(index)

                        transaction.setObject(upload, forKey: upload.id, inCollection: collection)
                    }
            }
        }
    }

    /**
     Remove an upload identified by its ID and reorder the others, if necessary.

     - parameter id: An upload ID to remove.
     */
    class func remove(id: String) {
        remove(ids: [id])
    }

    var order: Int
    var paused = false
    var error: String?

    var liveProgress: Progress?

    private var _progress: Double = 0
    var progress: Double {
        get {
            return liveProgress?.fractionCompleted ?? _progress
        }
        set {
            _progress = newValue
        }
    }

    private(set) var assetId: String?
    private var _asset: Asset?

    var asset: Asset? {
        get {
            if _asset == nil,
                let id = assetId {

                Db.bgRwConn?.read { transaction in
                    self._asset = transaction.object(forKey: id, inCollection: Asset.collection) as? Asset
                }
            }

            return _asset
        }

        set {
            assetId = newValue?.id
            _asset = nil
        }
    }

    var isUploaded: Bool {
        get {
            return asset?.isUploaded ?? false
        }
        set {
            asset?.isUploaded = newValue
        }
    }

    var state: PKDownloadButtonState {
        if isUploaded || progress >= 1 {
            return .downloaded
        }

        if paused {
            return .startDownload
        }

        if progress > 0 {
            return .downloading
        }

        return .pending
    }

    var thumbnail: UIImage? {
        return asset?.getThumbnail()
    }

    var filename: String {
        return asset!.filename
    }

    init(order: Int, asset: Asset) {
        id = UUID().uuidString
        self.order = order
        assetId = asset.id
    }


    // MARK: NSCoding

    required init?(coder decoder: NSCoder) {
        id = decoder.decodeObject(forKey: "id") as? String ?? UUID().uuidString
        order = decoder.decodeInteger(forKey: "order")
        _progress = decoder.decodeDouble(forKey: "progress")
        paused = decoder.decodeBool(forKey: "paused")
        error = decoder.decodeObject(forKey: "error") as? String
        assetId = decoder.decodeObject(forKey: "assetId") as? String
    }

    func encode(with coder: NSCoder) {
        coder.encode(id, forKey: "id")
        coder.encode(order, forKey: "order")
        coder.encode(progress, forKey: "progress")
        coder.encode(paused, forKey: "paused")
        coder.encode(error, forKey: "error")
        coder.encode(assetId, forKey: "assetId")
    }


    // MARK: NSObject

    override var description: String {
        return "\(String(describing: type(of: self))): [id=\(id), order=\(order), "
            + "progress=\(progress), paused=\(paused), error=\(error ?? "nil"), "
            + "assetId=\(assetId ?? "nil")]"
    }


    // MARK: Public Methods

    func cancel() {
        if let liveProgress = liveProgress {
            liveProgress.cancel()
            self.liveProgress = nil
            progress = 0
        }
    }

    func hasProgressChanged() -> Bool {
        return _progress != liveProgress?.fractionCompleted ?? 0
    }
}
