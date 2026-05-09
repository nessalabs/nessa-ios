import CoreData
import Foundation

public enum ChatMessageCoreDataSyncMode: Equatable, Sendable {
    case cloudKit(containerIdentifier: String)
    case localOnly
}

public final class CoreDataCloudKitChatMessageRepository: ChatMessagePersisting, @unchecked Sendable {
    private static let entityName = "ChatMessageEntity"
    private let lock = NSLock()
    private let container: NSPersistentContainer

    public init(
        storeURL: URL = CoreDataCloudKitChatMessageRepository.defaultStoreURL(),
        syncMode: ChatMessageCoreDataSyncMode = .cloudKit(containerIdentifier: "iCloud.com.clawdia.mobile")
    ) throws {
        let model = Self.makeModel()
        let container: NSPersistentContainer
        switch syncMode {
        case .cloudKit:
            container = NSPersistentCloudKitContainer(name: "ClawdiaChats", managedObjectModel: model)
        case .localOnly:
            container = NSPersistentContainer(name: "ClawdiaChats", managedObjectModel: model)
        }

        try FileManager.default.createDirectory(
            at: storeURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let description = NSPersistentStoreDescription(url: storeURL)
        description.type = NSSQLiteStoreType
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        if case .cloudKit(let containerIdentifier) = syncMode {
            description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: containerIdentifier)
        }
        container.persistentStoreDescriptions = [description]

        var loadError: Error?
        container.loadPersistentStores { _, error in
            loadError = error
        }
        if let loadError {
            throw loadError
        }
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergePolicy(merge: .mergeByPropertyObjectTrumpMergePolicyType)
        self.container = container
    }

    public static func productionRepository() -> any ChatMessagePersisting {
        if let cloudRepository = try? CoreDataCloudKitChatMessageRepository() {
            return cloudRepository
        }
        if let localRepository = try? CoreDataCloudKitChatMessageRepository(syncMode: .localOnly) {
            return localRepository
        }
        return InMemoryChatMessageRepository()
    }

    public func loadActiveMessages(now: Date) throws -> [StoredChatMessage] {
        try fetchMessages(predicate: NSPredicate(format: "expiresAt > %@", now as NSDate))
    }

    public func save(_ message: StoredChatMessage) throws {
        try synchronized { context in
            let object = try self.fetchOrCreateMessageObject(id: message.id, in: context)
            object.setValue(message.id, forKey: "id")
            object.setValue(message.conversationID, forKey: "conversationID")
            object.setValue(message.area, forKey: "area")
            object.setValue(message.sender.rawValue, forKey: "sender")
            object.setValue(message.text, forKey: "text")
            object.setValue(message.createdAt, forKey: "createdAt")
            object.setValue(message.expiresAt, forKey: "expiresAt")
            object.setValue(message.deliveryState.rawValue, forKey: "deliveryState")
            if context.hasChanges {
                try context.save()
            }
        }
    }

    public func deleteMessages(ids: Set<UUID>) throws {
        guard !ids.isEmpty else {
            return
        }
        try deleteMessages(predicate: NSPredicate(format: "id IN %@", Array(ids) as NSArray))
    }

    public func deleteMessages(conversationID: String) throws {
        try deleteMessages(predicate: NSPredicate(format: "conversationID == %@", conversationID))
    }

    public func deleteMessages(area: String) throws {
        try deleteMessages(predicate: NSPredicate(format: "area == %@", area))
    }

    public func deleteExpired(before date: Date) throws {
        try deleteMessages(predicate: NSPredicate(format: "expiresAt <= %@", date as NSDate))
    }

    public func deleteAll() throws {
        try deleteMessages(predicate: nil)
    }

    private func fetchMessages(predicate: NSPredicate?) throws -> [StoredChatMessage] {
        try synchronized { context in
            let request = NSFetchRequest<NSManagedObject>(entityName: Self.entityName)
            request.predicate = predicate
            request.sortDescriptors = [
                NSSortDescriptor(key: "createdAt", ascending: true),
                NSSortDescriptor(key: "id", ascending: true)
            ]
            return try context.fetch(request).compactMap(Self.message(from:))
        }
    }

    private func fetchOrCreateMessageObject(id: UUID, in context: NSManagedObjectContext) throws -> NSManagedObject {
        let request = NSFetchRequest<NSManagedObject>(entityName: Self.entityName)
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        if let existing = try context.fetch(request).first {
            return existing
        }
        guard let entity = NSEntityDescription.entity(forEntityName: Self.entityName, in: context) else {
            throw CoreDataChatMessageRepositoryError.missingEntity
        }
        return NSManagedObject(entity: entity, insertInto: context)
    }

    private func deleteMessages(predicate: NSPredicate?) throws {
        try synchronized { context in
            let request = NSFetchRequest<NSManagedObject>(entityName: Self.entityName)
            request.predicate = predicate
            let objects = try context.fetch(request)
            for object in objects {
                context.delete(object)
            }
            if context.hasChanges {
                try context.save()
            }
        }
    }

    private func synchronized<T>(_ work: (NSManagedObjectContext) throws -> T) throws -> T {
        try lock.withLock {
            try work(container.viewContext)
        }
    }

    private static func message(from object: NSManagedObject) -> StoredChatMessage? {
        guard let id = object.value(forKey: "id") as? UUID,
              let conversationID = object.value(forKey: "conversationID") as? String,
              let area = object.value(forKey: "area") as? String,
              let senderRaw = object.value(forKey: "sender") as? String,
              let sender = AgentMessageSender(rawValue: senderRaw),
              let text = object.value(forKey: "text") as? String,
              let createdAt = object.value(forKey: "createdAt") as? Date,
              let expiresAt = object.value(forKey: "expiresAt") as? Date,
              let deliveryStateRaw = object.value(forKey: "deliveryState") as? String,
              let deliveryState = ChatMessageDeliveryState(rawValue: deliveryStateRaw) else {
            return nil
        }
        return StoredChatMessage(
            id: id,
            conversationID: conversationID,
            area: area,
            sender: sender,
            text: text,
            createdAt: createdAt,
            expiresAt: expiresAt,
            deliveryState: deliveryState
        )
    }

    private static func makeModel() -> NSManagedObjectModel {
        let entity = NSEntityDescription()
        entity.name = entityName
        entity.managedObjectClassName = NSStringFromClass(NSManagedObject.self)
        entity.properties = [
            attribute("id", type: .UUIDAttributeType, isOptional: false),
            attribute("conversationID", type: .stringAttributeType, isOptional: false),
            attribute("area", type: .stringAttributeType, isOptional: false),
            attribute("sender", type: .stringAttributeType, isOptional: false),
            attribute("text", type: .stringAttributeType, isOptional: false),
            attribute("createdAt", type: .dateAttributeType, isOptional: false),
            attribute("expiresAt", type: .dateAttributeType, isOptional: false),
            attribute("deliveryState", type: .stringAttributeType, isOptional: false)
        ]

        let model = NSManagedObjectModel()
        model.entities = [entity]
        return model
    }

    private static func attribute(
        _ name: String,
        type: NSAttributeType,
        isOptional: Bool
    ) -> NSAttributeDescription {
        let attribute = NSAttributeDescription()
        attribute.name = name
        attribute.attributeType = type
        attribute.isOptional = isOptional
        return attribute
    }

    public static func defaultStoreURL() -> URL {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return baseURL
            .appendingPathComponent("Clawdia", isDirectory: true)
            .appendingPathComponent("ClawdiaChats.sqlite")
    }
}

private enum CoreDataChatMessageRepositoryError: Error {
    case missingEntity
}
