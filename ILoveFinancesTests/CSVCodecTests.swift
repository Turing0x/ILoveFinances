import Foundation
import Testing
@testable import ILoveFinances

@Suite("Codec CSV")
struct CSVCodecTests {

    @Test("Entrecomillado RFC 4180", arguments: [
        ("simple", "simple"),
        ("con,coma", "\"con,coma\""),
        ("con\"comilla", "\"con\"\"comilla\""),
        ("con\nsalto", "\"con\nsalto\""),
        ("", ""),
    ])
    func escapado(entrada: String, esperado: String) {
        #expect(CSVCodec.escape(entrada) == esperado)
    }

    @Test("Una fila con comas y comillas dentro se lee entera")
    func lecturaConTrampa() throws {
        let texto = CSVCodec.encode(
            header: ["id", "note"],
            rows: [["1", "Cena, restaurante \"El Rincon\""]]
        )
        let tabla = try CSVCodec.decode(texto)
        #expect(tabla.rows.count == 1)
        #expect(tabla.rows[0]["note"] == "Cena, restaurante \"El Rincon\"")
    }

    @Test("Un salto de linea dentro de un campo no parte la fila")
    func saltoDeLineaInterno() throws {
        let texto = CSVCodec.encode(header: ["a", "b"], rows: [["uno\ndos", "tres"]])
        let tabla = try CSVCodec.decode(texto)
        #expect(tabla.rows.count == 1)
        #expect(tabla.rows[0]["a"] == "uno\ndos")
        #expect(tabla.rows[0]["b"] == "tres")
    }

    /// La cabecera se lee por NOMBRE, no por posicion: es lo que permite que
    /// una copia de hoy siga restaurando cuando el modelo tenga un campo mas.
    @Test("Las columnas se leen por nombre, no por posicion")
    func columnasPorNombre() throws {
        let tabla = try CSVCodec.decode("b,a\n2,1\n")
        #expect(tabla.rows[0]["a"] == "1")
        #expect(tabla.rows[0]["b"] == "2")
    }

    @Test("Una columna que falta en la fila se lee vacia, no rompe")
    func filaCorta() throws {
        let tabla = try CSVCodec.decode("a,b,c\n1,2\n")
        #expect(tabla.rows[0]["c"] == "")
    }

    @Test("Fechas ISO 8601, ida y vuelta")
    func fechas() {
        let original = Date(timeIntervalSince1970: 1_756_000_000.123)
        let vuelta = CSVCodec.date(from: CSVCodec.string(from: original))
        #expect(vuelta != nil)
        #expect(abs(vuelta!.timeIntervalSince(original)) < 0.01)
    }
}
