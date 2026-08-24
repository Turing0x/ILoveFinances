import Foundation

/// Magnitud en la que se mide un producto (Fase 5).
///
/// Existe para que la normalizacion sea cerrada: solo se convierte DENTRO de
/// una dimension. Un litro no se convierte a kilos aunque el agua pese lo que
/// pese, porque el aceite no, y adivinar la densidad seria inventarse un dato.
enum UnitDimension: String, Codable, CaseIterable {
    case count
    case mass
    case volume

    /// Unidad canonica de la dimension: a esta se lleva todo antes de comparar.
    var baseUnit: UnitOfMeasure {
        switch self {
        case .count:  return .unit
        case .mass:   return .kg
        case .volume: return .l
        }
    }

    var label: String {
        switch self {
        case .count:  return "Unidades"
        case .mass:   return "Peso"
        case .volume: return "Volumen"
        }
    }

    /// Sufijo del precio comparable: "1,05 EUR/kg".
    var rateLabel: String {
        switch self {
        case .count:  return "ud"
        case .mass:   return "kg"
        case .volume: return "l"
        }
    }
}

/// Unidad de medida de una linea de ticket.
///
/// Raw value `String` y no `Int`, por el mismo motivo que `TransactionKind`: un
/// entero se rompe al reordenar los casos y el texto es legible al depurar.
///
/// Anadir un caso mas adelante (`docena`, `m`) es seguro; quitarlo no, porque
/// las lineas ya guardadas seguirian apuntando a el.
enum UnitOfMeasure: String, Codable, CaseIterable {
    case unit
    case kg
    case g
    case l
    case ml

    var label: String {
        switch self {
        case .unit: return "Unidad"
        case .kg:   return "Kilo"
        case .g:    return "Gramo"
        case .l:    return "Litro"
        case .ml:   return "Mililitro"
        }
    }

    var shortLabel: String {
        switch self {
        case .unit: return "ud"
        case .kg:   return "kg"
        case .g:    return "g"
        case .l:    return "l"
        case .ml:   return "ml"
        }
    }

    var dimension: UnitDimension {
        switch self {
        case .unit:    return .count
        case .kg, .g:  return .mass
        case .l, .ml:  return .volume
        }
    }

    /// Factor para pasar a la unidad base de su dimension.
    ///
    /// `Decimal` y NUNCA `Double`: multiplica una cantidad que acaba dividiendo
    /// un importe en euros, y ahi la casa tiene prohibido el binario flotante.
    /// Se construye desde `String` porque `Decimal(0.001)` literal pasa por
    /// `Double` y ya no vale exactamente una milesima.
    var factorToBase: Decimal {
        switch self {
        case .unit: return 1
        case .kg:   return 1
        case .g:    return Decimal(string: "0.001")!
        case .l:    return 1
        case .ml:   return Decimal(string: "0.001")!
        }
    }
}
