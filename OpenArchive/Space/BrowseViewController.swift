//
//  BrowseViewController.swift
//  OpenArchive
//
//  Created by Benjamin Erhart on 30.01.19.
//  Copyright © 2019 Open Archive. All rights reserved.
//

import UIKit
import FilesProvider

protocol BrowseDelegate {
    func didSelect(name: String)
}

class BrowseViewController: BaseTableViewController {

    class func instantiate() -> BrowseViewController? {
        return UIStoryboard(name: "Main", bundle: Bundle(for: self))
            .instantiateViewController(withIdentifier: String(describing: self)) as? BrowseViewController
    }

    var delegate: BrowseDelegate?

    private var provider: WebDAVFileProvider? {
        return (SelectedSpace.space as? WebDavSpace)?.provider
    }

    private var loading = true

    private var error: Error?

    private var folders = [FileObject]()


    override func viewDidLoad() {
        super.viewDidLoad()

        loadFolders()
    }


    // MARK: UITableViewDataSource

    override func numberOfSections(in tableView: UITableView) -> Int {
        return 2
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if section > 0 {
            return loading ? 0 : 1
        }

        return folders.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if indexPath.section > 0 {
            let cell = tableView.dequeueReusableCell(withIdentifier: MenuItemCell.reuseId,
                                                 for: indexPath) as! MenuItemCell

            if let error = error {
                return cell.set(error)
            }

            return cell.set("Add New".localize())
        }

        let cell = tableView.dequeueReusableCell(withIdentifier: FolderCell.reuseId,
                                                 for: indexPath) as! FolderCell

        return cell.set(folder: folders[indexPath.row])
    }

    override func tableView(_ tableView: UITableView, willSelectRowAt indexPath: IndexPath) -> IndexPath? {
        if error != nil {
            return nil
        }

        return indexPath
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if indexPath.section > 0 {
            tableView.deselectRow(at: indexPath, animated: true)

            let alert = AlertHelper.build(
                title: "Add New".localize(),
                actions: [AlertHelper.cancelAction()])

            AlertHelper.addTextField(alert, placeholder: "New Project Name".localize())

            alert.addAction(AlertHelper.defaultAction() { action in
                if let newName = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines),
                    !newName.isEmpty {

                    self.beginWork {
                        self.provider?.create(folder: newName, at: "") { error in
                            if error != nil {
                                self.endWork(error)
                            }
                            else {
                                self.loadFolders()
                            }
                        }
                    }
                }
                else {
                    AlertHelper.present(self, message:
                        "Please don't use an empty name or a name consisting only of white space!"
                            .localize())
                }
            })

            present(alert, animated: true)
        }
        else {
            delegate?.didSelect(name: folders[indexPath.row].name)

            navigationController?.popViewController(animated: true)
        }
    }


    // MARK: UITableViewDelegate

    override func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return 0
    }


    // MARK: Private Methods

    private func beginWork(_ block: () -> Void) {
        loading = true
        error = nil

        DispatchQueue.main.async {
            self.workingOverlay.isHidden = false
        }

        block()
    }

    private func endWork(_ error: Error?) {
        self.loading = false
        self.error = error

        DispatchQueue.main.async {
            self.tableView.reloadData()
            self.workingOverlay.isHidden = true
        }
    }

    private func loadFolders() {
        beginWork {
            folders.removeAll()

            provider?.contentsOfDirectory(path: "") { files, error in
                for file in files {
                    if file.isDirectory {
                        self.folders.append(file)
                    }
                }

                self.endWork(error)
            }
        }
    }
}
