//
//  Collection.swift
//  OpenArchive
//
//  Created by Benjamin Erhart on 31.01.19.
//  Copyright © 2019 Open Archive. All rights reserved.
//

import UIKit
import YapDatabase

/**
 A `Collection` is the aggregation of one or more `Assets` which were edited
 and uploaded at the same time.

 A `Collection` belongs to exactly one `Project`. It can't live without one.

 Each `Project` only ever has one open `Collection` at a time. All `Assets` the
 user adds to a `Project` become member of the currently open `Collection`.

 If there currently is no open `Collection`, a new one shall be created.
 */
class Collection: NSObject, Item, YapDatabaseRelationshipNode {

    // MARK: Item

    static let collection  = "collections"

    static func fixArchiverName() {
        NSKeyedArchiver.setClassName("Collection", for: self)
        NSKeyedUnarchiver.setClass(self, forClassName: "Collection")
    }

    func compare(_ rhs: Collection) -> ComparisonResult {
        return (closed ?? created).compare(rhs.closed ?? rhs.created)
    }

    var id: String


    // MARK: Collection

    /**
     Get an open collection for the given project.

     Creates one, if necessary.
     */
    class func getOrCreate(for project: Project) -> Collection {
        var c: Collection?

        Db.newConnection()?.read { transaction in
            transaction.enumerateKeysAndObjects(inCollection: collection) { key, object, stop in
                if let collection = object as? Collection,
                    collection.isOpen && collection.projectId == project.id {

                    c = collection
                    stop.pointee = true
                }
            }
        }

        return c ?? Collection(project)
    }

    private(set) var projectId: String

    var project: Project? {
        get {
            var project: Project?

            Db.newConnection()?.read { transaction in
                project = transaction.object(forKey: self.projectId, inCollection: Project.collection) as? Project
            }

            return project
        }
        set {
            if let id = newValue?.id {
                projectId = id
            }
        }
    }

    var created: Date
    var closed: Date?
    var uploaded: Date?

    var isOpen: Bool {
        return closed == nil && uploaded == nil
    }

    init(_ project: Project) {
        id = UUID().uuidString
        projectId = project.id
        created = Date()
    }


    // MARK: NSCoding

    required init?(coder: NSCoder) {
        id = coder.decodeObject() as? String ?? UUID().uuidString
        projectId = coder.decodeObject() as! String
        created = coder.decodeObject() as? Date ?? Date()
        closed = coder.decodeObject() as? Date
        uploaded = coder.decodeObject() as? Date
    }

    func encode(with coder: NSCoder) {
        coder.encode(id)
        coder.encode(projectId)
        coder.encode(created)
        coder.encode(closed)
        coder.encode(uploaded)
    }


    // MARK: NSObject

    override var description: String {
        return "\(String(describing: type(of: self))): [id=\(id), "
            + "projectId=\(projectId), created=\(created), "
            + "closed=\(String(describing: closed)), "
            + "uploaded=\(String(describing: uploaded))]"
    }


    // MARK: YapDatabaseRelationshipNode

    func yapDatabaseRelationshipEdges() -> [YapDatabaseRelationshipEdge]? {
        return [YapDatabaseRelationshipEdge(
            name: "project", destinationKey: projectId, collection: Project.collection,
            nodeDeleteRules: .deleteSourceIfDestinationDeleted)]
    }


    // MARK: Public Methods

    func close() {
        closed = Date()
    }
}
