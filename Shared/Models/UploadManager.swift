//
//  UploadManager.swift
//  OpenArchive
//
//  Created by Benjamin Erhart on 14.03.19.
//  Copyright © 2019 Open Archive. All rights reserved.
//

import Foundation
import YapDatabase
import Reachability
import FilesProvider

extension Notification.Name {
    static let uploadManagerPause = Notification.Name("uploadManagerPause")

    static let uploadManagerUnpause = Notification.Name("uploadManagerUnpause")

    static let uploadManagerDone = Notification.Name("uploadManagerDone")
}

extension AnyHashable {
    static let error = "error"
    static let url = "url"
}

class UploadManager {

    /**
     Maximum number of upload retries per upload item before giving up.
    */
    static let maxRetries = 10

    static let shared = UploadManager()

    private var readConn = Db.newLongLivedReadConn()

    private var mappings = YapDatabaseViewMappings(groups: UploadsView.groups,
                                               view: UploadsView.name)

    private var uploads = [Upload]()

    private var reachability = Reachability()

    /**
     Polls tracked Progress objects and updates `Update` objects every second.
    */
    private let progressTimer: DispatchSourceTimer

    private let queue = DispatchQueue(label: "\(Bundle.main.bundleIdentifier!).UploadManager")

    private init() {
        progressTimer = DispatchSource.makeTimerSource(flags: .strict, queue: queue)
        progressTimer.schedule(deadline: .now(), repeating: .seconds(1))
        progressTimer.setEventHandler {
            Db.writeConn?.asyncReadWrite { transaction in
                for upload in self.uploads {
                    if upload.hasProgressChanged() {
                        self.debug("#progress tracker changed for \(upload))")

                        transaction.setObject(upload, forKey: upload.id, inCollection: Upload.collection)
                    }
                }
            }
        }
        progressTimer.resume()

        // Initialize mapping and current uploads.
        readConn?.read { transaction in
            self.mappings.update(with: transaction)

            (transaction.ext(UploadsView.name) as? YapDatabaseViewTransaction)?
                .enumerateKeysAndObjects(inGroup: UploadsView.groups[0]) { collection, key, object, index, stop in
                    if let upload = object as? Upload {
                        self.uploads.append(upload)
                    }
            }
        }

        let nc = NotificationCenter.default

        nc.addObserver(self, selector: #selector(yapDatabaseModified),
                       name: .YapDatabaseModified, object: nil)

        nc.addObserver(self, selector: #selector(yapDatabaseModified),
                       name: .YapDatabaseModifiedExternally, object: nil)

        nc.addObserver(self, selector: #selector(pause),
                       name: .uploadManagerPause, object: nil)

        nc.addObserver(self, selector: #selector(unpause),
                       name: .uploadManagerUnpause, object: nil)

        nc.addObserver(self, selector: #selector(done),
                       name: .uploadManagerDone, object: nil)

        nc.addObserver(self, selector: #selector(reachabilityChanged),
                       name: .reachabilityChanged, object: reachability)

        try? reachability?.startNotifier()

        // Schedule a timer, which calls #uploadNext every 60 seconds beginning
        // in 1 second.
        RunLoop.main.add(Timer(fireAt: Date().addingTimeInterval(1), interval: 60,
                               target: self, selector: #selector(self.uploadNext),
                               userInfo: nil, repeats: true),
                         forMode: .common)
    }

    // MARK: Observers

    /**
     Callback for `YapDatabaseModified` and `YapDatabaseModifiedExternally` notifications.
     */
    @objc func yapDatabaseModified(notification: Notification) {
        debug("#yapDatabaseModified")

        var rowChanges = NSArray()

        (readConn?.ext(UploadsView.name) as? YapDatabaseViewConnection)?
            .getSectionChanges(nil,
                               rowChanges: &rowChanges,
                               for: readConn?.beginLongLivedReadTransaction() ?? [],
                               with: mappings)

        guard let changes = rowChanges as? [YapDatabaseViewRowChange] else {
            return
        }

        queue.async {
            for change in changes {
                switch change.type {
                case .delete:
                    if let indexPath = change.indexPath {
                        let upload = self.uploads.remove(at: indexPath.row)
                        upload.cancel()
                    }
                case .insert:
                    if let newIndexPath = change.newIndexPath,
                        let upload = self.readUpload(newIndexPath) {

                        self.uploads.insert(upload, at: newIndexPath.row)
                    }
                case .move:
                    if let indexPath = change.indexPath, let newIndexPath = change.newIndexPath {
                        let upload = self.uploads.remove(at: indexPath.row)
                        upload.order = newIndexPath.row
                        self.uploads.insert(upload, at: newIndexPath.row)
                    }
                case .update:
                    if let indexPath = change.indexPath,
                        let upload = self.readUpload(indexPath) {

                            upload.liveProgress = self.uploads[indexPath.row].liveProgress
                            self.uploads[indexPath.row] = upload
                    }
                @unknown default:
                    break
                }
            }

            self.uploadNext()
        }
    }

    @objc func pause(notification: Notification) {
        debug("#pause")

        guard let id = notification.object as? String else {
            return
        }

        debug("#pause id=\(id)")

        queue.async {
            guard let upload = self.get(id) else {
                return
            }

            upload.cancel()
            upload.paused = true

            Db.writeConn?.asyncReadWrite { transaction in
                transaction.setObject(upload, forKey: id, inCollection: Upload.collection)
            }
        }
    }

    @objc func unpause(notification: Notification) {
        debug("#unpause")

        guard let id = notification.object as? String else {
            return
        }

        debug("#unpause id=\(id)")

        queue.async {
            guard let upload = self.get(id),
                upload.liveProgress == nil else {
                    return
            }

            upload.paused = false
            upload.error = nil
            upload.tries = 0
            upload.lastTry = nil
            upload.progress = 0

            // Also reset circuit-breaker. Otherwise users will get confused.
            let space = upload.asset?.space
            space?.tries = 0
            space?.lastTry = nil

            Db.writeConn?.asyncReadWrite { transaction in
                transaction.setObject(upload, forKey: id, inCollection: Upload.collection)

                if let space = space {
                    transaction.setObject(space, forKey: space.id, inCollection: Space.collection)
                }
            }
        }
    }

    @objc func done(notification: Notification) {
        debug("#done")

        guard let id = notification.object as? String else {
            return
        }

        let error = notification.userInfo?[.error] as? Error
        let url = notification.userInfo?[.url] as? URL

        debug("#done id=\(id), error=\(String(describing: error)), url=\(url?.absoluteString ?? "nil")")

        queue.async {
            guard let upload = self.get(id),
                let asset = upload.asset else {
                    return
            }

            let collection: Collection?
            let space = asset.space

            if error != nil || url == nil {
                asset.isUploaded = false

                // Circuit breaker pattern: Increase circuit breaker counter on error.
                space?.tries += 1
                space?.lastTry = Date()

                upload.tries += 1
                // We stop retrying, if the server denies us, or as soon as we hit the maximum number of retries.
                upload.paused = error is FileProviderHTTPError || UploadManager.maxRetries <= upload.tries
                upload.lastTry = Date()
                upload.liveProgress = nil
                upload.progress = 0
                upload.error = error?.localizedDescription ?? (url == nil ? "No URL provided." : "Unknown error.")

                collection = nil
            }
            else {
                asset.publicUrl = url
                asset.isUploaded = true

                // Circuit breaker pattern: Reset circuit breaker counter on success.
                space?.tries = 0
                space?.lastTry = nil

                collection = asset.collection
                collection?.setUploadedNow()
            }

            Db.writeConn?.asyncReadWrite { transaction in
                if asset.isUploaded {
                    transaction.removeObject(forKey: id, inCollection: Upload.collection)

                    transaction.setObject(collection, forKey: collection!.id, inCollection: Collection.collection)
                }
                else {
                    transaction.setObject(upload, forKey: id, inCollection: Upload.collection)
                }

                if let space = space {
                    transaction.setObject(space, forKey: space.id, inCollection: Space.collection)
                }

                transaction.setObject(asset, forKey: asset.id, inCollection: Asset.collection)
            }
        }
    }

    @objc func reachabilityChanged(notification: Notification) {
        debug("#reachabilityChanged connection=\(reachability?.connection ?? .none)")

        if reachability?.connection ?? .none != .none {
            uploadNext()
        }
    }


    // MARK: Private Methods

    private func get(_ id: String) -> Upload? {
        return uploads.first { $0.id == id }
    }

    @objc private func uploadNext() {
        queue.async {
            self.debug("#uploadNext \(self.uploads.count) items in upload queue")

            // Check if there's at least on item currently uploading.
            if self.isUploading() {
                return self.debug("#uploadNext already one uploading")
            }

            guard let upload = self.getNext(),
                let asset = upload.asset else {
                    return self.debug("#uploadNext nothing to upload")
            }

            if self.reachability?.connection ?? Reachability.Connection.none == .none {
                return self.debug("#uploadNext no connection")
            }

            self.debug("#uploadNext try upload=\(upload)")

            upload.liveProgress = asset.space?.upload(asset, uploadId: upload.id)
            upload.error = nil

            Db.writeConn?.asyncReadWrite { transaction in
                let collection = asset.collection

                if collection.closed == nil {
                    collection.close()

                    transaction.setObject(collection, forKey: collection.id, inCollection: Collection.collection)
                }

                transaction.setObject(upload, forKey: upload.id, inCollection: Upload.collection)
            }
        }
    }

    private func isUploading() -> Bool {
        return uploads.first { $0.liveProgress != nil } != nil
    }

    private func getNext() -> Upload? {
        return uploads.first {
            $0.liveProgress == nil && !$0.paused && $0.asset != nil && !$0.isUploaded
                && $0.nextTry.compare(Date()) == .orderedAscending
                && $0.asset?.space?.uploadAllowed ?? false
        }
    }

    private func readUpload(_ indexPath: IndexPath) -> Upload? {
        var upload: Upload?

        readConn?.read() { transaction in
            upload = (transaction.ext(UploadsView.name) as? YapDatabaseViewTransaction)?
                .object(at: indexPath, with: self.mappings) as? Upload
        }

        return upload
    }

    private func debug(_ text: String) {
        #if DEBUG
        print("[\(String(describing: type(of: self)))] \(text)")
        #endif
    }
}
