import SwiftData

/// The current schema. Build containers from this, not from a numbered version.
public typealias CaptainsLogSchema = CaptainsLogSchemaV2

// The top-level model classes. Each older version keeps a frozen copy of its models
// (`CaptainsLogSchemaV1`) so the migration plan can recognise stores written by it.
public enum CaptainsLogSchemaV2: VersionedSchema {
    public static let versionIdentifier = Schema.Version(2, 0, 0)

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
        [CaptainsLogSchemaV1.self, CaptainsLogSchemaV2.self]
    }

    public static var stages: [MigrationStage] {
        [v1ToV2]
    }

    // Drops CalendarEvent.participantCount and confirmedCount.
    static let v1ToV2 = MigrationStage.lightweight(
        fromVersion: CaptainsLogSchemaV1.self,
        toVersion: CaptainsLogSchemaV2.self
    )
}
