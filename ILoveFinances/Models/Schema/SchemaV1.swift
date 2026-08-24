import Foundation
import SwiftData

/// Version 1 del esquema, con las SEIS entidades desde el primer commit.
///
/// `ImportProfile` e `ImportRule` no se usan hasta la Fase 3 y estan aqui a
/// proposito: el esquema de CloudKit en Production es ADITIVO e irreversible.
/// Se pueden anadir campos; no borrarlos ni cambiarles el tipo. Anadir una
/// entidad con datos reales ya sincronizados es la operacion que se quiere
/// evitar, y una tabla vacia no cuesta nada.
enum SchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [
            Account.self,
            Transaction.self,
            TransactionCategory.self,
            FamilyTag.self,
            ImportProfile.self,
            ImportRule.self,
        ]
    }
}

/// Plan de migracion con una sola version.
///
/// Parece innecesario hoy y ese es justo el motivo de ponerlo: anadir
/// `VersionedSchema` mas tarde, con datos ya sincronizados en CloudKit, es
/// exactamente el momento en que no se puede.
enum ILoveFinancesMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [SchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}
