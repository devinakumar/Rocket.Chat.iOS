//
//  Subscription.swift
//  Rocket.Chat
//
//  Created by Rafael K. Streit on 7/9/16.
//  Copyright © 2016 Rocket.Chat. All rights reserved.
//

import Foundation
import RealmSwift
import SwiftyJSON

enum SubscriptionType: String {
    case directMessage = "d"
    case channel = "c"
    case group = "p"
}

final class Subscription: BaseModel {
    dynamic var auth: Auth?

    fileprivate dynamic var privateType = SubscriptionType.channel.rawValue
    var type: SubscriptionType {
        get { return SubscriptionType(rawValue: privateType) ?? SubscriptionType.group }
        set { privateType = newValue.rawValue }
    }

    dynamic var rid = ""

    dynamic var name = ""
    dynamic var unread = 0
    dynamic var open = false
    dynamic var alert = false
    dynamic var favorite = false

    dynamic var createdAt: Date?
    dynamic var lastSeen: Date?

    dynamic var otherUserId: String?
    var directMessageUser: User? {
        guard let otherUserId = otherUserId else { return nil }
        guard let messages = try? Realm().objects(User.self).filter("identifier = '\(otherUserId)'") else { return nil }

        return messages.first
    }

    let messages = LinkingObjects(fromType: Message.self, property: "subscription")

    // MARK: ModelMapping

    override func update(_ dict: JSON) {
        if self.identifier == nil {
            self.identifier = dict["_id"].string ?? ""
        }

        self.rid = dict["rid"].string ?? ""
        self.name = dict["name"].string ?? ""
        self.unread = dict["unread"].int ?? 0
        self.open = dict["open"].bool ?? false
        self.alert = dict["alert"].bool ?? false
        self.favorite = dict["f"].bool ?? false
        self.privateType = dict["t"].string ?? SubscriptionType.channel.rawValue

        if self.type == .directMessage {
            let userId = dict["u"]["_id"].string ?? ""
            self.otherUserId = rid.replacingOccurrences(of: userId, with: "")
        }

        if let createdAt = dict["ts"]["$date"].double {
            self.createdAt = Date.dateFromInterval(createdAt)
        }

        if let lastSeen = dict["ls"]["$date"].double {
            self.lastSeen = Date.dateFromInterval(lastSeen)
        }
    }
}

extension Subscription {

    func isValid() -> Bool {
        return self.rid.characters.count > 0
    }

    func isJoined() -> Bool {
        return auth != nil || type != .channel
    }

    func fetchRoomIdentifier(_ completion: @escaping MessageCompletionObject <Subscription>) {
        if type == .channel {
            SubscriptionManager.getRoom(byName: name, completion: { [weak self] (response) in
                guard !response.isError() else { return }

                let result = response.result["result"]
                Realm.execute { _ in
                    self?.update(result)
                }

                guard let strongSelf = self else { return }
                completion(strongSelf)
            })
        } else if type == .directMessage {
            SubscriptionManager.createDirectMessage(name, completion: { [weak self] (response) in
                guard !response.isError() else { return }

                let rid = response.result["result"]["rid"].string ?? ""
                Realm.execute { _ in
                    self?.rid = rid
                }

                guard let strongSelf = self else { return }
                completion(strongSelf)
            })
        }
    }

    func fetchMessages() -> Results<Message> {
        return self.messages.sorted(byProperty: "createdAt", ascending: true)
    }

}
