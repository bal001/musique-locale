import Foundation

// Petits outils pour fouiller les réponses InnerTube (JSON profond et changeant).
enum ArbreJSON {
    /// Suit un chemin de clés (String) et d'indices (Int) : valeur(json, "a", 0, "b").
    static func valeur(_ racine: Any?, _ chemin: Any...) -> Any? {
        var courant = racine
        for etape in chemin {
            switch etape {
            case let cle as String:
                courant = (courant as? [String: Any])?[cle]
            case let i as Int:
                guard let tableau = courant as? [Any], tableau.indices.contains(i) else { return nil }
                courant = tableau[i]
            default:
                return nil
            }
        }
        return courant
    }

    /// Tous les objets rangés sous `cle`, n'importe où dans l'arbre (ordre des tableaux conservé).
    static func tous(_ cle: String, dans racine: Any) -> [[String: Any]] {
        var trouves: [[String: Any]] = []
        func parcourir(_ noeud: Any) {
            if let objet = noeud as? [String: Any] {
                for (k, v) in objet {
                    if k == cle, let cible = v as? [String: Any] { trouves.append(cible) } else { parcourir(v) }
                }
            } else if let tableau = noeud as? [Any] {
                for v in tableau { parcourir(v) }
            }
        }
        parcourir(racine)
        return trouves
    }

    /// Première chaîne dont (clé, valeur) satisfait `test`.
    static func premiereChaine(dans racine: Any, ou test: (String, String) -> Bool) -> String? {
        if let objet = racine as? [String: Any] {
            for (k, v) in objet {
                if let s = v as? String, test(k, s) { return s }
                if let r = premiereChaine(dans: v, ou: test) { return r }
            }
        } else if let tableau = racine as? [Any] {
            for v in tableau {
                if let r = premiereChaine(dans: v, ou: test) { return r }
            }
        }
        return nil
    }

    /// Concatène les « runs » d'un texte InnerTube.
    static func texteRuns(_ runs: Any?) -> String? {
        guard let liste = runs as? [[String: Any]] else { return nil }
        let texte = liste.compactMap { $0["text"] as? String }.joined()
        return texte.isEmpty ? nil : texte
    }
}
