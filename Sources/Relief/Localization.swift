import Foundation

/// Interface language, taken from the system language (Settings › General › Language & Region).
enum Lang: String {
    case en, fr, es, de, ja

    static let current: Lang = {
        for identifier in Locale.preferredLanguages {
            let code = Locale(identifier: identifier).language.languageCode?.identifier
                ?? String(identifier.prefix(2))
            if let lang = Lang(rawValue: code) { return lang }
        }
        return .en
    }()
}

func tr(_ en: String, _ fr: String, _ es: String, _ de: String, _ ja: String) -> String {
    switch Lang.current {
    case .en: return en
    case .fr: return fr
    case .es: return es
    case .de: return de
    case .ja: return ja
    }
}

/// Every interface string.
enum S {
    // MARK: Panel
    static var tagline: String { tr("Sound in relief", "Le son en relief", "Sonido en relieve", "Klang mit Tiefe", "立体的なサウンド") }
    static var turnOn: String { tr("Turn Relief on", "Activer Relief", "Activar Relief", "Relief einschalten", "Relief をオン") }
    static var turnOff: String { tr("Turn Relief off", "Désactiver Relief", "Desactivar Relief", "Relief ausschalten", "Relief をオフ") }
    static var tabSound: String { tr("Sound", "Son", "Sonido", "Klang", "サウンド") }
    static var tabEqualizer: String { tr("Equalizer", "Égaliseur", "Ecualizador", "Equalizer", "イコライザ") }
    static var tabApps: String { tr("Apps", "Apps", "Apps", "Apps", "アプリ") }
    static var statusOff: String { tr("Relief is off: your Mac plays its normal sound.", "Relief est désactivé : ton Mac joue son son normal.", "Relief está desactivado: tu Mac suena como siempre.", "Relief ist aus: Dein Mac klingt wie gewohnt.", "Relief はオフです。通常のサウンドで再生されます。") }
    static func playingOn(_ device: String) -> String {
        let d = device.isEmpty ? tr("the current output", "la sortie actuelle", "la salida actual", "der aktuellen Ausgabe", "現在の出力") : device
        return tr("Playing on \(d)", "Lecture sur \(d)", "Reproduciendo en \(d)", "Wiedergabe über \(d)", "\(d) で再生中")
    }
    static var permissionNeeded: String { tr("Relief needs the System Audio Recording permission to process your sound.", "Relief a besoin de l'autorisation « Enregistrement audio du système » pour traiter le son.", "Relief necesita el permiso de grabación de audio del sistema para procesar el sonido.", "Relief braucht die Berechtigung „Systemaudioaufnahme“, um den Klang zu bearbeiten.", "サウンドを処理するには「システムオーディオ録音」の許可が必要です。") }
    static var openPrivacySettings: String { tr("Open Privacy Settings…", "Ouvrir les réglages de confidentialité…", "Abrir ajustes de privacidad…", "Datenschutz-Einstellungen öffnen …", "プライバシー設定を開く…") }
    static var tryAgain: String { tr("Try Again", "Réessayer", "Reintentar", "Erneut versuchen", "再試行") }
    static var off: String { tr("Off", "Désactivé", "Desactivado", "Aus", "オフ") }

    // MARK: Sound
    static var booster: String { tr("Volume Booster", "Amplificateur de volume", "Amplificador de volumen", "Lautstärke-Booster", "音量ブースター") }
    static var surround: String { tr("3D Surround", "Son 3D", "Sonido 3D", "3D-Raumklang", "3D サラウンド") }
    static var speakers: String { tr("Speakers", "Haut-parleurs", "Altavoces", "Lautsprecher", "スピーカー") }
    static var headphones: String { tr("Headphones", "Casque", "Auriculares", "Kopfhörer", "ヘッドフォン") }
    static var ambience: String { tr("Ambience", "Ambiance", "Ambiente", "Raum", "アンビエンス") }
    static var clarity: String { tr("Clarity", "Clarté", "Claridad", "Klarheit", "クリアさ") }
    static var bass: String { tr("Bass Boost", "Renfort des basses", "Refuerzo de graves", "Bass-Boost", "低音強調") }
    static var nightMode: String { tr("Night Mode", "Mode nuit", "Modo nocturno", "Nachtmodus", "ナイトモード") }
    static var nightModeHelp: String { tr("Evens out loud and quiet passages, so you can listen at low volume.", "Équilibre les passages forts et faibles, pour écouter à bas volume.", "Iguala los pasajes fuertes y suaves para escuchar a bajo volumen.", "Gleicht laute und leise Stellen aus, ideal für geringe Lautstärke.", "大きな音と小さな音の差を抑え、小音量でも聞きやすくします。") }

    // MARK: Equalizer
    static var equalizer: String { tr("Equalizer", "Égaliseur", "Ecualizador", "Equalizer", "イコライザ") }
    static var customPreset: String { tr("Custom", "Personnalisé", "Personalizado", "Eigene", "カスタム") }
    static var savePreset: String { tr("Save as Preset…", "Enregistrer comme préréglage…", "Guardar como preajuste…", "Als Preset sichern …", "プリセットとして保存…") }
    static func deletePreset(_ name: String) -> String { tr("Delete “\(name)”", "Supprimer « \(name) »", "Eliminar «\(name)»", "„\(name)“ löschen", "「\(name)」を削除") }
    static var presetNamePlaceholder: String { tr("Preset name", "Nom du préréglage", "Nombre del preajuste", "Name des Presets", "プリセット名") }
    static var save: String { tr("Save", "Enregistrer", "Guardar", "Sichern", "保存") }
    static var cancel: String { tr("Cancel", "Annuler", "Cancelar", "Abbrechen", "キャンセル") }

    static func presetName(_ id: String, fallback: String) -> String {
        switch id {
        case "flat": return tr("Flat", "Neutre", "Plano", "Neutral", "フラット")
        case "bass": return tr("Bass Booster", "Basses renforcées", "Más graves", "Mehr Bass", "低音ブースト")
        case "treble": return tr("Treble Booster", "Aigus renforcés", "Más agudos", "Mehr Höhen", "高音ブースト")
        case "vocal": return tr("Vocal", "Voix", "Voz", "Gesang", "ボーカル")
        case "classical": return tr("Classical", "Classique", "Clásica", "Klassik", "クラシック")
        case "electronic": return tr("Electronic", "Électro", "Electrónica", "Elektronisch", "エレクトロニック")
        case "acoustic": return tr("Acoustic", "Acoustique", "Acústica", "Akustik", "アコースティック")
        case "podcast": return tr("Podcast", "Podcast", "Pódcast", "Podcast", "ポッドキャスト")
        case "movie": return tr("Movie", "Film", "Película", "Film", "映画")
        case "gaming": return tr("Gaming", "Jeux vidéo", "Videojuegos", "Gaming", "ゲーム")
        case "loudness": return tr("Loudness", "Loudness", "Sonoridad", "Loudness", "ラウドネス")
        case "laptop": return tr("Small Speakers", "Petits haut-parleurs", "Altavoces pequeños", "Kleine Lautsprecher", "小型スピーカー")
        default: return fallback
        }
    }

    // MARK: Apps
    static var noApps: String { tr("No app is playing sound right now.", "Aucune app ne joue de son pour le moment.", "Ninguna app está reproduciendo sonido.", "Gerade spielt keine App Ton ab.", "現在サウンドを再生しているアプリはありません。") }
    static var appsHint: String { tr("Apps appear here while they play sound. Their volume is kept for next time.", "Les apps apparaissent ici quand elles jouent du son. Leur volume est conservé.", "Las apps aparecen aquí mientras suenan. Su volumen se recuerda.", "Apps erscheinen hier, während sie Ton abspielen. Ihre Lautstärke wird gemerkt.", "サウンドを再生中のアプリが表示されます。音量は保存されます。") }
    static var mute: String { tr("Mute", "Couper le son", "Silenciar", "Stummschalten", "消音") }
    static var unmute: String { tr("Unmute", "Rétablir le son", "Activar sonido", "Ton an", "消音を解除") }
    static var resetVolume: String { tr("Reset to 100 %", "Revenir à 100 %", "Volver al 100 %", "Auf 100 % zurücksetzen", "100% に戻す") }

    // MARK: Settings menu
    static var settings: String { tr("Settings", "Réglages", "Ajustes", "Einstellungen", "設定") }
    static var launchAtLogin: String { tr("Open at Login", "Ouvrir à l'ouverture de session", "Abrir al iniciar sesión", "Bei Anmeldung öffnen", "ログイン時に開く") }
    static var autoCheckUpdates: String { tr("Check for Updates Automatically", "Rechercher les mises à jour automatiquement", "Buscar actualizaciones automáticamente", "Automatisch nach Updates suchen", "アップデートを自動確認") }
    static var checkForUpdates: String { tr("Check for Updates…", "Rechercher les mises à jour…", "Buscar actualizaciones…", "Nach Updates suchen …", "アップデートを確認…") }
    static var resetSound: String { tr("Reset All Sound Settings", "Réinitialiser tous les réglages du son", "Restablecer los ajustes de sonido", "Alle Klangeinstellungen zurücksetzen", "サウンド設定をすべてリセット") }
    static var privacySettings: String { tr("Privacy Settings…", "Réglages de confidentialité…", "Ajustes de privacidad…", "Datenschutz-Einstellungen …", "プライバシー設定…") }
    static var website: String { tr("Relief Website", "Site de Relief", "Sitio web de Relief", "Relief-Website", "Relief のウェブサイト") }
    static var about: String { tr("About Relief", "À propos de Relief", "Acerca de Relief", "Über Relief", "Relief について") }
    static var aboutCredits: String { tr("Free and open source (MIT).", "Gratuit et open source (MIT).", "Gratis y de código abierto (MIT).", "Kostenlos und Open Source (MIT).", "無料のオープンソース (MIT)。") }
    static var quit: String { tr("Quit", "Quitter", "Salir", "Beenden", "終了") }
    static var ok: String { "OK" }

    // MARK: Errors
    static var noOutputDevice: String { tr("No sound output is available.", "Aucune sortie audio n'est disponible.", "No hay ninguna salida de audio.", "Keine Audioausgabe verfügbar.", "使用できるサウンド出力がありません。") }
    static var cannotCaptureAudio: String { tr("Relief could not connect to the sound output.", "Relief n'a pas pu se connecter à la sortie audio.", "Relief no pudo conectarse a la salida de audio.", "Relief konnte keine Verbindung zur Audioausgabe herstellen.", "サウンド出力に接続できませんでした。") }
    static var unsupportedFormat: String { tr("This audio format is not supported.", "Ce format audio n'est pas pris en charge.", "Este formato de audio no es compatible.", "Dieses Audioformat wird nicht unterstützt.", "このオーディオ形式には対応していません。") }

    // MARK: Updates
    static var updateFailed: String { tr("Update failed", "La mise à jour a échoué", "Error al actualizar", "Aktualisierung fehlgeschlagen", "アップデートに失敗しました") }
    static var upToDate: String { tr("Relief is up to date", "Relief est à jour", "Relief está actualizado", "Relief ist aktuell", "Relief は最新です") }
    static func upToDateDetail(_ v: String) -> String { tr("You have the latest version (\(v)).", "Tu as la dernière version (\(v)).", "Tienes la última versión (\(v)).", "Du hast die neueste Version (\(v)).", "最新バージョン (\(v)) です。") }
    static func updateAvailable(_ v: String) -> String { tr("Relief \(v) is available", "Relief \(v) est disponible", "Relief \(v) está disponible", "Relief \(v) ist verfügbar", "Relief \(v) が利用可能です") }
    static func updateAvailableDetail(current: String) -> String { tr("You have version \(current). The update installs in a few seconds and Relief restarts.", "Tu as la version \(current). La mise à jour s'installe en quelques secondes, puis Relief redémarre.", "Tienes la versión \(current). La actualización se instala en unos segundos y Relief se reinicia.", "Du hast Version \(current). Das Update wird in Sekunden installiert, dann startet Relief neu.", "現在のバージョンは \(current) です。数秒でインストールされ、Relief が再起動します。") }
    static var installAndRestart: String { tr("Install and Restart", "Installer et redémarrer", "Instalar y reiniciar", "Installieren und neu starten", "インストールして再起動") }
    static var later: String { tr("Later", "Plus tard", "Más tarde", "Später", "後で") }
    static var skipVersion: String { tr("Skip This Version", "Ignorer cette version", "Omitir esta versión", "Diese Version überspringen", "このバージョンをスキップ") }
    static var downloadingUpdate: String { tr("Downloading the update…", "Téléchargement de la mise à jour…", "Descargando la actualización…", "Update wird geladen …", "アップデートをダウンロード中…") }
    static var installingUpdate: String { tr("Installing…", "Installation…", "Instalando…", "Installation …", "インストール中…") }
    static var restarting: String { tr("Restarting Relief…", "Redémarrage de Relief…", "Reiniciando Relief…", "Relief startet neu …", "Relief を再起動中…") }
    static var updateCheckFailed: String { tr("Could not check for updates", "Impossible de vérifier les mises à jour", "No se pudieron buscar actualizaciones", "Updates konnten nicht geprüft werden", "アップデートを確認できませんでした") }
    static var downloadManually: String { tr("Download Manually", "Télécharger manuellement", "Descargar manualmente", "Manuell laden", "手動でダウンロード") }
    static var updateNoAsset: String { tr("The release has no .zip file.", "La version publiée ne contient pas de fichier .zip.", "La versión no contiene un archivo .zip.", "Die Version enthält keine .zip-Datei.", "リリースに .zip ファイルがありません。") }
    static var updateBadArchive: String { tr("The downloaded archive is damaged.", "L'archive téléchargée est endommagée.", "El archivo descargado está dañado.", "Das geladene Archiv ist beschädigt.", "ダウンロードしたアーカイブが破損しています。") }
    static var updateBadSignature: String { tr("The downloaded app is not signed like this one: it was not installed.", "L'app téléchargée n'a pas la même signature que celle-ci : elle n'a pas été installée.", "La app descargada no tiene la misma firma: no se instaló.", "Die geladene App ist anders signiert und wurde nicht installiert.", "ダウンロードしたアプリの署名が一致しないため、インストールしませんでした。") }
    static func updateCannotReplace(_ folder: String) -> String { tr("Relief cannot write to \(folder).", "Relief ne peut pas écrire dans \(folder).", "Relief no puede escribir en \(folder).", "Relief kann nicht in \(folder) schreiben.", "Relief は \(folder) に書き込めません。") }
}
