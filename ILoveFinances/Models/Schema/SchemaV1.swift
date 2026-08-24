import Foundation
import SwiftData

/// Version 1 del esquema, con SIETE entidades.
///
/// `ImportProfile` e `ImportRule` no se usan hasta la Fase 3 y estan aqui a
/// proposito: el esquema de CloudKit en Production es ADITIVO e irreversible.
/// Se pueden anadir campos; no borrarlos ni cambiarles el tipo. Anadir una
/// entidad con datos reales ya sincronizados es la operacion que se quiere
/// evitar, y una tabla vacia no cuesta nada.
///
/// `RecurringBill` se anadio en la Fase 2 SIN crear una v2 y sin stage de
/// migracion: en ese momento no habia todavia datos reales desplegados a
/// Production, asi que ampliar la v1 en sitio era correcto y mas simple.
/// Contrapartida asumida entonces: un store local antiguo que no migrara en
/// ligero se resolvia reinstalando. A partir de que haya datos reales esta via
/// se cierra y cualquier cambio pide `SchemaV2` + `MigrationStage`.
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
            RecurringBill.self,
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
