import Foundation
import SwiftData
import Testing
@testable import ILoveFinances

/// PLAN.md seccion 7 bis: "Un test que recorra el esquema por reflexion y falle
/// si algun atributo es no-opcional sin valor por defecto, o si hay una
/// relacion sin inversa."
///
/// Es lo unico que avisa de que la sincronizacion se ha roto ANTES de que se
/// rompa en silencio. CloudKit no acepta atributos obligatorios sin valor por
/// defecto ni relaciones sin inversa declarada, y cuando incumples una de las
/// dos no falla el build: falla el sync, semanas despues, sin mensaje.
@Suite("Invariantes de CloudKit sobre el esquema")
struct SchemaInvariantTests {

    private var schema: Schema { Schema(SchemaV2.models) }

    @Test("Ningun atributo es obligatorio sin valor por defecto")
    func todoOpcionalOConDefecto() {
        var infractores: [String] = []

        for entity in schema.entities {
            for attribute in entity.attributes {
                // Los generados por SwiftData no cuentan.
                guard !attribute.name.hasPrefix("_") else { continue }
                if !attribute.isOptional && attribute.defaultValue == nil {
                    infractores.append("\(entity.name).\(attribute.name)")
                }
            }
        }

        #expect(infractores.isEmpty, "Sin valor por defecto: \(infractores.joined(separator: ", "))")
    }

    @Test("Toda relacion declara su inversa")
    func todaRelacionTieneInversa() {
        var infractores: [String] = []

        for entity in schema.entities {
            for relationship in entity.relationships {
                if relationship.inverseName == nil {
                    infractores.append("\(entity.name).\(relationship.name)")
                }
            }
        }

        #expect(infractores.isEmpty, "Sin inversa: \(infractores.joined(separator: ", "))")
    }

    @Test("Ninguna relacion usa deleteRule .deny")
    func sinDeleteRuleDeny() {
        var infractores: [String] = []

        for entity in schema.entities {
            for relationship in entity.relationships where relationship.deleteRule == .deny {
                infractores.append("\(entity.name).\(relationship.name)")
            }
        }

        #expect(infractores.isEmpty, "Con .deny: \(infractores.joined(separator: ", "))")
    }

    /// La jerarquia de categorias va por `parentID: UUID?` justamente para
    /// evitar esto: las relaciones de una entidad consigo misma son fragiles
    /// bajo NSPersistentCloudKitContainer. El test impide que alguien "mejore"
    /// el modelo anadiendo parent/children mas adelante.
    @Test("Ninguna entidad se relaciona consigo misma")
    func sinRelacionesAutoReferenciales() {
        var infractores: [String] = []

        for entity in schema.entities {
            for relationship in entity.relationships
            where relationship.destination == entity.name {
                infractores.append("\(entity.name).\(relationship.name)")
            }
        }

        #expect(infractores.isEmpty, "Auto-referencial: \(infractores.joined(separator: ", "))")
    }

    @Test("El esquema contiene las diez entidades, importacion, facturas y compras incluidas")
    func diezEntidades() {
        let nombres = Set(schema.entities.map(\.name))
        #expect(nombres == [
            "Account", "Transaction", "TransactionCategory",
            "FamilyTag", "ImportProfile", "ImportRule", "RecurringBill",
            "Shop", "GroceryProduct", "PurchaseLine",
        ])
    }

    /// El contenedor de la app usa `SchemaV2` (Fase 6). Si alguien lo cambia sin
    /// tocar el plan de migracion, o al reves, esto lo pilla: el esquema que se
    /// valida arriba tiene que ser el ULTIMO del plan, que es el que la app abre.
    @Test("El plan de migracion termina en la version que la app usa")
    func planTerminaEnLaVersionActual() {
        let ultima = ILoveFinancesMigrationPlan.schemas.last
        #expect(ultima?.versionIdentifier == SchemaV2.versionIdentifier)
        #expect(SchemaV2.versionIdentifier > SchemaV1.versionIdentifier)
    }

    /// La casa usa `.nullify` en todas partes. `Transaction.purchaseLines` es
    /// la unica excepcion y es deliberada (ver el comentario en `Transaction`):
    /// una linea sin su ticket pierde fecha y tienda, las dos coordenadas del
    /// historial de precios, y se queda como basura imposible de limpiar.
    ///
    /// Este test no comprueba que el modelo sea correcto: fija la desviacion,
    /// para que "normalizarla" a `.nullify` mas adelante falle en rojo en vez
    /// de llenar la base de lineas huerfanas en silencio.
    @Test("La unica relacion .cascade es la de un ticket con sus lineas")
    func unicoCascade() {
        var cascadas: Set<String> = []

        for entity in schema.entities {
            for relationship in entity.relationships where relationship.deleteRule == .cascade {
                cascadas.insert("\(entity.name).\(relationship.name)")
            }
        }

        #expect(cascadas == ["Transaction.purchaseLines"])
    }
}
