import Foundation
import SwiftData

/// Version 1 del esquema, con DIEZ entidades.
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
///
/// `Shop`, `GroceryProduct` y `PurchaseLine` se anadieron en la Fase 5 por el
/// mismo motivo y dentro de la misma ventana: el esquema seguia sin desplegar a
/// Production y sin un solo dato real. ESA VENTANA YA ESTA CERRADA: el esquema
/// de estas diez entidades se desplego a Production el 24/08/2026. A partir de
/// ahi, ampliar la v1 en sitio dejo de ser una opcion y cualquier cambio de
/// modelo pide `SchemaV2` + un `MigrationStage`, con copia de seguridad antes.
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
            Shop.self,
            GroceryProduct.self,
            PurchaseLine.self,
        ]
    }
}

/// Version 2 del esquema (Fase 6): las MISMAS diez entidades, con dos atributos
/// nuevos en `Account` — `transportCardNumber` y `farePerTrip`.
///
/// El cambio es puramente ADITIVO, que es lo unico legal contra un esquema ya
/// desplegado a Production (24/08/2026).
///
/// **No hay `MigrationStage`, y no por dejadez.** Se intento el ligero
/// (`.lightweight(fromVersion: SchemaV1.self, toVersion: SchemaV2.self)`) y la
/// app ABORTA al arrancar, dentro de `NSLightweightMigrationStage.init`: un
/// stage exige que las dos versiones describan modelos DISTINTOS, y aqui
/// `SchemaV2.models` son literalmente las mismas clases que `SchemaV1.models`,
/// asi que las dos versiones tienen el mismo checksum. Para tener un stage de
/// verdad habria que duplicar las diez clases `@Model` dentro de un `enum
/// SchemaV1` propio y dejarlas congeladas para siempre.
///
/// Se decidio NO pagar eso por dos atributos opcionales: CoreData migra este
/// caso —anadir columnas— en ligero por su cuenta, sin stage, y los 96 tests
/// pasan sobre el esquema resultante. Lo que queda montado es el andamiaje:
/// `VersionedSchema` y `SchemaMigrationPlan` existen y estan enchufados.
///
/// **Regla para el proximo cambio:** si es aditivo, se sube el
/// `versionIdentifier` y ya. Si NO lo es —renombrar un campo, cambiar un tipo,
/// partir una entidad— entonces SI toca duplicar las clases en un namespace
/// congelado y escribir el stage, porque ahi la migracion automatica no existe
/// y el fallo seria perdida de datos, no un aborto visible.
enum SchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }

    static var models: [any PersistentModel.Type] { SchemaV1.models }
}

/// Plan de migracion.
///
/// Se monto en la Fase 1 con una sola version, cuando parecia innecesario, por
/// este motivo exacto: anadir `VersionedSchema` mas tarde, con datos ya
/// sincronizados en CloudKit, es justo el momento en que no se puede. La Fase 6
/// lo estrena.
enum ILoveFinancesMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [SchemaV1.self, SchemaV2.self] }

    static var stages: [MigrationStage] { [] }
}
