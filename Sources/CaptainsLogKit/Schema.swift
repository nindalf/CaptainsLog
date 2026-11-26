import SwiftData

/// The current schema. Build containers from this, not from a numbered version.
public typealias CaptainsLogSchema = CaptainsLogSchemaV7

// The top-level model classes. Each older version keeps a frozen copy of its models
// (`CaptainsLogSchemaV1` to `CaptainsLogSchemaV6`) so the migration plan can recognise stores written by it.
public enum CaptainsLogSchemaV7: VersionedSchema {
    public static let versionIdentifier = Schema.Version(7, 0, 0)

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
        [CaptainsLogSchemaV1.self, CaptainsLogSchemaV2.self, CaptainsLogSchemaV3.self, CaptainsLogSchemaV4.self, CaptainsLogSchemaV5.self, CaptainsLogSchemaV6.self, CaptainsLogSchemaV7.self]
    }

    public static var stages: [MigrationStage] {
        [v1ToV2, v2ToV3, v3ToV4, v4ToV5, v5ToV6, v6ToV7]
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

    // Drops PullRequest.deploymentStatus, which nothing set, and adds the fields GitHub sync's
    // enrichment fills in for open PRs: CI, conflicts, auto-merge, a summary of the reviews, and
    // review requests.
    static let v4ToV5 = MigrationStage.lightweight(
        fromVersion: CaptainsLogSchemaV4.self,
        toVersion: CaptainsLogSchemaV5.self
    )

    // Adds CalendarEvent.isFromOutside and isAcceptedByMe, false until the next calendar sync.
    static let v5ToV6 = MigrationStage.lightweight(
        fromVersion: CaptainsLogSchemaV5.self,
        toVersion: CaptainsLogSchemaV6.self
    )

    // Adds Feedback.isPrivate, false for existing feedback.
    static let v6ToV7 = MigrationStage.lightweight(
        fromVersion: CaptainsLogSchemaV6.self,
        toVersion: CaptainsLogSchemaV7.self
    )
}
