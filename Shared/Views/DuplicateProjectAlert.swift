//
//  RemoveAssetAlert.swift
//  OpenArchive
//
//  Created by Benjamin Erhart on 25.03.19.
//  Copyright © 2019 Open Archive. All rights reserved.
//

import UIKit

class DuplicateProjectAlert: UIAlertController {

    /**
     - parameter foo: Just there to avoid endless recursion.
    */
    convenience init(_ foo: String?) {
        let message = "Please choose another name/project or use the existing one instead.".localize()

        self.init(title: "Project Already Exists".localize(),
                   message: message,
                   preferredStyle: .alert)

        addAction(AlertHelper.defaultAction())
    }

    private override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
    }

    required init?(coder decoder: NSCoder) {
        super.init(coder: decoder)
    }

    /**
     Tests, if a name is already taken as a project for the given space.

     - parameter spaceId: The space to check against.
     - parameter name: The project name.
    */
    func exists(spaceId: String, name: String) -> Bool {
        var exists = false

        Db.bgRwConn?.read { transaction in
            transaction.iterateKeysAndObjects(inCollection: Project.collection) { (key, project: Project, stop) in
                if project.spaceId == spaceId && project.name == name {
                    exists = true
                    stop = true
                }
            }
        }

        return exists
    }
}
