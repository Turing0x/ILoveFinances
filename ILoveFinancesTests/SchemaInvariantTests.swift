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

    private var schema: Schema { Schema(SchemaV1.models) }

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

    @Test("El esquema v1 contiene las siete entidades, importacion y facturas incluidas")
    func sieteEntidades() {
        let nombres = Set(schema.entities.map(\.name))
        #expect(nombres == [
            "Account", "Transaction", "TransactionCategory",
            "FamilyTag", "ImportProfile", "ImportRule", "RecurringBill",
        ])
    }
}
