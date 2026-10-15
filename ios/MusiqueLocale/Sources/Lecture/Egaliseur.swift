import Accelerate
import AVFoundation
import MediaToolbox
import Observation

// Égaliseur 5 bandes branché dans la lecture (AVPlayer n'en a pas) : un « tap » de traitement audio applique des
// filtres biquad (formules RBJ) — basses en plateau à 60 Hz, crêtes à 230 Hz, 910 Hz, 3,6 kHz, aigus en plateau à 14 kHz.
// Un pré-gain négatif compense les hausses fortes pour éviter la saturation. Réglages gardés sur le téléphone.
@Observable
@MainActor
final class Egaliseur {
    static let partage = Egaliseur()

    struct Preset: Identifiable, Hashable { let nom: String; let gains: [Float]; var id: String { nom } }
    static let frequences: [Float] = [60, 230, 910, 3600, 14000]
    static let libelles = ["60 Hz", "230 Hz", "910 Hz", "3,6 kHz", "14 kHz"]
    static let presets: [Preset] = [
        Preset(nom: "Plat", gains: [0, 0, 0, 0, 0]),
        Preset(nom: "Basses +", gains: [6, 3, 0, 0, 0]),
        Preset(nom: "Basses ++", gains: [12, 7, 0, -1, 0]),
        Preset(nom: "Hip-hop", gains: [8, 4, -1, 2, 3]),
        Preset(nom: "Électro", gains: [7, 2, 0, 3, 5]),
        Preset(nom: "Pop", gains: [-1, 2, 4, 2, -1]),
        Preset(nom: "Voix", gains: [-3, -1, 4, 4, 1]),
        Preset(nom: "Aigus +", gains: [0, 0, 0, 4, 7]),
    ]

    var actif: Bool { didSet { sauver(); appliquer() } }
    var gains: [Float] { didSet { sauver(); appliquer() } }   // en dB, de −12 à +12

    var presetCourant: Preset? { Self.presets.first { $0.gains == gains } }

    @ObservationIgnored private let etat = EtatTraitement()

    private init() {
        let d = UserDefaults.standard
        actif = d.object(forKey: "egaliseurActif") as? Bool ?? false
        gains = (d.array(forKey: "egaliseurGains") as? [Double])?.map(Float.init) ?? [0, 0, 0, 0, 0]
        appliquer()
    }

    func choisir(_ p: Preset) { gains = p.gains; if !actif { actif = true } }

    /// Branche l'égaliseur sur un élément de lecture (fichier ou flux).
    func brancher(_ item: AVPlayerItem) async {
        guard let piste = try? await item.asset.loadTracks(withMediaType: .audio).first else { return }
        let parametres = AVMutableAudioMixInputParameters(track: piste)
        parametres.audioTapProcessor = TapEgaliseur.creer(etat: etat)
        let mix = AVMutableAudioMix()
        mix.inputParameters = [parametres]
        item.audioMix = mix
    }

    private func appliquer() { etat.mettreAJour(gains: actif ? gains : [0, 0, 0, 0, 0]) }

    private func sauver() {
        UserDefaults.standard.set(actif, forKey: "egaliseurActif")
        UserDefaults.standard.set(gains.map(Double.init), forKey: "egaliseurGains")
    }
}

/// Réglages partagés avec le fil audio (lus à chaque bloc de son).
final class EtatTraitement: @unchecked Sendable {
    private var verrou = os_unfair_lock()
    private var _gains: [Float] = [0, 0, 0, 0, 0]
    private var _version = 0

    func mettreAJour(gains: [Float]) {
        os_unfair_lock_lock(&verrou); _gains = gains; _version += 1; os_unfair_lock_unlock(&verrou)
    }
    func lire() -> ([Float], Int) {
        os_unfair_lock_lock(&verrou); defer { os_unfair_lock_unlock(&verrou) }
        return (_gains, _version)
    }
}

/// Traitement du son : filtres biquad en cascade, par canal (Accelerate / vDSP).
final class TraitementEgaliseur {
    let etat: EtatTraitement
    var frequenceEchantillonnage: Double = 44100
    var version = -1
    var reglage: vDSP_biquad_Setup?
    var retards: [[Float]] = []
    var preGain: Float = 1
    var neutre = true

    init(etat: EtatTraitement) { self.etat = etat }
    deinit { if let r = reglage { vDSP_biquad_DestroySetup(r) } }

    func reconstruireSiBesoin(canaux: Int) {
        let (gains, v) = etat.lire()
        guard v != version || retards.count != canaux else { return }
        version = v
        neutre = gains.allSatisfy { $0 == 0 }
        if let r = reglage { vDSP_biquad_DestroySetup(r); reglage = nil }
        var coefficients: [Double] = []
        for (i, g) in gains.enumerated() {
            let f = Double(Egaliseur.frequences[i]), gain = Double(g)
            let a = pow(10, gain / 40), w0 = 2 * Double.pi * min(f, frequenceEchantillonnage * 0.45) / frequenceEchantillonnage
            let cosw = cos(w0), alpha = sin(w0) / (2 * (i == 0 || i == 4 ? 0.707 : 1.0))
            var b0, b1, b2, a0, a1, a2: Double
            if i == 0 {        // plateau grave
                let r = 2 * sqrt(a) * alpha
                b0 = a * ((a + 1) - (a - 1) * cosw + r); b1 = 2 * a * ((a - 1) - (a + 1) * cosw); b2 = a * ((a + 1) - (a - 1) * cosw - r)
                a0 = (a + 1) + (a - 1) * cosw + r; a1 = -2 * ((a - 1) + (a + 1) * cosw); a2 = (a + 1) + (a - 1) * cosw - r
            } else if i == 4 { // plateau aigu
                let r = 2 * sqrt(a) * alpha
                b0 = a * ((a + 1) + (a - 1) * cosw + r); b1 = -2 * a * ((a - 1) + (a + 1) * cosw); b2 = a * ((a + 1) + (a - 1) * cosw - r)
                a0 = (a + 1) - (a - 1) * cosw + r; a1 = 2 * ((a - 1) - (a + 1) * cosw); a2 = (a + 1) - (a - 1) * cosw - r
            } else {           // crête
                b0 = 1 + alpha * a; b1 = -2 * cosw; b2 = 1 - alpha * a
                a0 = 1 + alpha / a; a1 = -2 * cosw; a2 = 1 - alpha / a
            }
            coefficients += [b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0]
        }
        reglage = vDSP_biquad_CreateSetup(coefficients, vDSP_Length(gains.count))
        retards = Array(repeating: Array(repeating: 0, count: 2 * gains.count + 2), count: canaux)
        // Pré-gain : baisse le volume d'environ 60 % de la plus forte hausse (pas de saturation sur « Basses ++ »).
        preGain = pow(10, -max(0, gains.max() ?? 0) * 0.6 / 20)
    }

    func traiter(_ liste: UnsafeMutableAudioBufferListPointer, images: Int) {
        reconstruireSiBesoin(canaux: liste.count)
        guard !neutre, let reglage else { return }
        for (c, tampon) in liste.enumerated() {
            guard let donnees = tampon.mData?.assumingMemoryBound(to: Float.self) else { continue }
            let n = min(images, Int(tampon.mDataByteSize) / MemoryLayout<Float>.size)
            var pre = preGain
            vDSP_vsmul(donnees, 1, &pre, donnees, 1, vDSP_Length(n))
            retards[c].withUnsafeMutableBufferPointer { r in
                vDSP_biquad(reglage, r.baseAddress!, donnees, 1, donnees, 1, vDSP_Length(n))
            }
        }
    }
}

/// Fonctions C du tap MediaToolbox (le traitement vit dans `clientInfo`).
enum TapEgaliseur {
    static func creer(etat: EtatTraitement) -> MTAudioProcessingTap? {
        var rappels = MTAudioProcessingTapCallbacks(
            version: kMTAudioProcessingTapCallbacksVersion_0,
            clientInfo: UnsafeMutableRawPointer(Unmanaged.passRetained(TraitementEgaliseur(etat: etat)).toOpaque()),
            init: { _, clientInfo, stockage in stockage.pointee = clientInfo },
            finalize: { tap in
                Unmanaged<TraitementEgaliseur>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).release()
            },
            prepare: { tap, _, format in
                let t = Unmanaged<TraitementEgaliseur>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
                t.frequenceEchantillonnage = format.pointee.mSampleRate
                t.version = -1
            },
            unprepare: nil,
            process: { tap, images, _, liste, imagesSortie, drapeaux in
                guard MTAudioProcessingTapGetSourceAudio(tap, images, liste, drapeaux, nil, imagesSortie) == noErr else { return }
                let t = Unmanaged<TraitementEgaliseur>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
                t.traiter(UnsafeMutableAudioBufferListPointer(liste), images: Int(imagesSortie.pointee))
            })
        var tap: MTAudioProcessingTap?
        let statut = MTAudioProcessingTapCreate(kCFAllocatorDefault, &rappels, kMTAudioProcessingTapCreationFlag_PostEffects, &tap)
        return statut == noErr ? tap : nil
    }
}
