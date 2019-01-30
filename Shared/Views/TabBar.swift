//
//  TabBar.swift
//  OpenArchive
//
//  Created by Benjamin Erhart on 29.01.19.
//  Copyright © 2019 Open Archive. All rights reserved.
//

import UIKit
import MaterialComponents.MaterialTabs
import YapDatabase
import Localize

class TabBar: MDCTabBar {

    static let addTabItemTag = 666

    weak var connection: YapDatabaseConnection?

    init(frame: CGRect, connection: YapDatabaseConnection?) {
        super.init(frame: frame)

        self.connection = connection

        setup()
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)

        setup()
    }


    // MARK: Public Methods

    func addToSubview(_ view: UIView) {
        view.addSubview(self)

        if #available(iOS 11.0, *) {
            translatesAutoresizingMaskIntoConstraints = false

            topAnchor.constraint(equalTo: view.topAnchor).isActive = true
            bottomAnchor.constraint(equalTo: view.bottomAnchor).isActive = true
            leadingAnchor.constraint(equalTo: view.leadingAnchor).isActive = true
            trailingAnchor.constraint(equalTo: view.trailingAnchor).isActive = true
        }
        else {
            sizeToFit()
        }
    }

    func handle(_ change: YapDatabaseViewRowChange, with mappings: YapDatabaseViewMappings) {
        switch change.type {
        case .delete:
            if let indexPath = change.indexPath {
                items.remove(at: indexPath.row + 1)
            }
        case .insert:
            if let newIndexPath = change.newIndexPath,
                let item = getItem(at: newIndexPath, with: mappings) {

                items.insert(item, at: newIndexPath.row + 1)
            }
        case .move:
            if let indexPath = change.indexPath, let newIndexPath = change.newIndexPath {
                items.insert(items.remove(at: indexPath.row + 1), at: newIndexPath.row + 1)
            }
        case .update:
            if let indexPath = change.indexPath,
                let item = getItem(at: indexPath, with: mappings) {

                items[indexPath.row + 1] = item
            }
        }
    }


    // MARK: Private Methods

    private func setup() {
        itemAppearance = .titles

        displaysUppercaseTitles = false

        setTitleColor(UIColor.gray, for: .normal)
        setTitleColor(UIColor.black, for: .selected)
        bottomDividerColor = UIColor.lightGray

        items = [getItem("All".localize(), -1)]

        read() { transaction in
            transaction.enumerateKeysAndObjects(inGroup: Project.collection) {
                collection, key, object, index, stop in

                if let item = self.getItem(object: object, Int(index)) {
                    self.items.append(item)
                }
            }
        }

        items.append(getItem("+".localize(), TabBar.addTabItemTag))
    }

    private func read(_ callback: @escaping (_ transaction: YapDatabaseViewTransaction) -> Void) {
        connection?.read() { transaction in
            if let viewTransaction = transaction.ext(AssetsProjectsView.name) as? YapDatabaseViewTransaction {
                callback(viewTransaction)
            }
        }
    }

    private func getItem(_ title: String?, _ tag: Int) -> UITabBarItem {
        return UITabBarItem(title: title, image: nil, tag: tag)
    }

    private func getItem(object: Any?, _ index: Int) -> UITabBarItem? {
        if let project = object as? Project {
            return getItem(project.name, index)
        }

        return nil
    }

    private func getItem(at indexPath: IndexPath, with mappings: YapDatabaseViewMappings) -> UITabBarItem? {
        var item: UITabBarItem? = nil

        read() { transaction in
            item = self.getItem(object: transaction.object(at: indexPath, with: mappings), indexPath.row)
        }

        return item
    }
}