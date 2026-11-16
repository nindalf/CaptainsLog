import SwiftData

/// The current schema. Build containers from this, not from a numbered version.
public typealias CaptainsLogSchema = CaptainsLogSchemaV4

// The top-level model classes. Each older version keeps a frozen copy of its models
// (`CaptainsLogSchemaV1` to `CaptainsLogSchemaV3`) so the migration plan can recognise stores written by it.
public enum CaptainsLogSchemaV4: VersionedSchema {
    public static let versionIdentifier = Schema.Version(4, 0, 0)

    public static var models: [any PersistentModel.Type] {
        [
            Person.self,
            Project.self,
            LogEntry.self,
            CalendarEvent.self,
            Meeting.self,
            PullRequest.self,
            Interview.self,
            Feedback.self,
            Todo.self,
        ]
    }
}

public enum CaptainsLogMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] {
        [CaptainsLogSchemaV1.self, CaptainsLogSchemaV2.self, CaptainsLogSchemaV3.self, CaptainsLogSchemaV4.self]
    }

    public static var stages: [MigrationStage] {
        [v1ToV2, v2ToV3, v3ToV4]
    }

    // Drops CalendarEvent.participantCount and confirmedCount, and Meeting.tags and
    // PullRequest.tags, which nothing set.
    static let v1ToV2 = MigrationStage.lightweight(
        fromVersion: CaptainsLogSchemaV1.self,
        toVersion: CaptainsLogSchemaV2.self
    )

    // Adds CalendarEvent.isOrganizedByMe, false until sync fills it in.
    static let v2ToV3 = MigrationStage.lightweight(
        fromVersion: CaptainsLogSchemaV2.self,
        toVersion: CaptainsLogSchemaV3.self
    )

    // Adds Person.isAddedManually, false until added by hand or from a roster, and
    // PullRequest.isAssignedToMe, false until the next GitHub sync.
    static let v3ToV4 = MigrationStage.lightweight(
        fromVersion: CaptainsLogSchemaV3.self,
        toVersion: CaptainsLogSchemaV4.self
    )
}
