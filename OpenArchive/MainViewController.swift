//
//  MainViewController.swift
//  OpenArchive
//
//  Created by Benjamin Erhart on 28.06.18.
//  Copyright © 2018 Open Archive. All rights reserved.
//

import UIKit
import MobileCoreServices
import YapDatabase

class MainViewController: UITableViewController, UIImagePickerControllerDelegate, UINavigationControllerDelegate {

    lazy var imagePicker: UIImagePickerController = {
        let imagePicker = UIImagePickerController()
        imagePicker.delegate = self
        imagePicker.sourceType = .photoLibrary
        imagePicker.mediaTypes = [kUTTypeImage as String]
        imagePicker.modalPresentationStyle = .popover

        return imagePicker
    }()

    lazy var readConn: YapDatabaseConnection? = {
        let conn = (UIApplication.shared.delegate as? AppDelegate)?.db?.newConnection()
        conn?.beginLongLivedReadTransaction()

        return conn
    }()

    lazy var mappings: YapDatabaseViewMappings = {
        let mappings = YapDatabaseViewMappings(groups: [Asset.COLLECTION], view: Asset.COLLECTION)

        readConn?.read() { transaction in
            mappings.update(with: transaction)
        }

        return mappings
    }()

    lazy var writeConn = (UIApplication.shared.delegate as? AppDelegate)?.db?.newConnection()

    override func viewDidLoad() {
        super.viewDidLoad()

        NotificationCenter.default.addObserver(self, selector: #selector(yapDatabaseModified),
                                               name: Notification.Name.YapDatabaseModified,
                                               object: readConn?.database)
    }

    // MARK: actions

    @IBAction func add(_ sender: UIBarButtonItem) {
        imagePicker.popoverPresentationController?.barButtonItem = sender
        present(imagePicker, animated: true)
    }

    // MARK: UITableViewDataSource

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return Int(mappings.numberOfItems(inSection: 0))
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "ImageCell", for: indexPath) as! ImageCell

        readConn?.read() { transaction in
            cell.imageObject = (transaction.ext(Asset.COLLECTION) as? YapDatabaseViewTransaction)?
                .object(at: indexPath, with: self.mappings) as? Image
        }

        return cell
    }

    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCellEditingStyle,
                            forRowAt indexPath: IndexPath) {
        if editingStyle == .delete,
            let key = (tableView.cellForRow(at: indexPath) as? ImageCell)?.imageObject?.getKey() {

            writeConn?.asyncReadWrite() { transaction in
                transaction.removeObject(forKey: key, inCollection: Asset.COLLECTION)
            }
        }
    }

    // MARK: UIImagePickerControllerDelegate

    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [String : Any]) {
        if let image = info[UIImagePickerControllerEditedImage] as? UIImage ??
            info[UIImagePickerControllerOriginalImage] as? UIImage
        {
            let image = Image(image)

            writeConn?.asyncReadWrite() { transaction in
                transaction.setObject(image, forKey: image.getKey(), inCollection: Asset.COLLECTION)
            }

            dismiss(animated: true, completion: nil)
        }
    }

    // MARK: Observers

    @objc func yapDatabaseModified(notification: Notification) {
        if let readConn = readConn {
            var changes = NSArray()

            (readConn.ext(Asset.COLLECTION) as? YapDatabaseViewConnection)?
                .getSectionChanges(nil,
                                   rowChanges: &changes,
                                   for: readConn.beginLongLivedReadTransaction(),
                                   with: mappings)

            if let changes = changes as? [YapDatabaseViewRowChange],
                changes.count > 0 {

                tableView.beginUpdates()

                for change in changes {
                    switch change.type {
                    case .delete:
                        if let indexPath = change.indexPath {
                            tableView.deleteRows(at: [indexPath], with: .automatic)
                        }
                    case .insert:
                        if let newIndexPath = change.newIndexPath {
                            tableView.insertRows(at: [newIndexPath], with: .automatic)
                        }
                    case .move:
                        if let indexPath = change.indexPath, let newIndexPath = change.newIndexPath {
                            tableView.moveRow(at: indexPath, to: newIndexPath)
                        }
                    case .update:
                        if let indexPath = change.indexPath {
                            tableView.reloadRows(at: [indexPath], with: .none)
                        }
                    }
                }

                tableView.endUpdates()
            }
        }
    }
}

