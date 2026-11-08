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
    static var statusStandby: String { tr("Standby: nothing is playing. Relief wakes up as soon as a sound plays.", "En veille : aucun son en cours. Relief se réveille dès qu'un son est joué.", "En reposo: no suena nada. Relief se activa en cuanto suena algo.", "Standby: Nichts wird abgespielt. Relief wacht auf, sobald Ton erklingt.", "スタンバイ中: 音が再生されるとすぐに再開します。") }
    static var autoStandby: String { tr("Standby When Nothing Plays", "Veille quand rien ne joue", "Reposo cuando no suena nada", "Standby, wenn nichts spielt", "再生がないときはスタンバイ") }
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

    static var headphoneModel: String { tr("Headphone model", "Modèle de casque", "Modelo de auriculares", "Kopfhörermodell", "ヘッドホンの機種") }
    static var noCorrection: String { tr("None", "Aucun", "Ninguno", "Keines", "なし") }
    static var searchHeadphones: String { tr("Search 6,000 models…", "Rechercher parmi 6 000 modèles…", "Buscar entre 6000 modelos…", "6000 Modelle durchsuchen …", "6,000 機種から検索…") }
    static var noHeadphoneFound: String { tr("No model matches.", "Aucun modèle ne correspond.", "Ningún modelo coincide.", "Kein Modell gefunden.", "該当する機種はありません。") }
    static var headphoneHelp: String { tr("Corrects your headphones' own colouration toward a neutral, balanced sound. Remembered for this output.", "Corrige la coloration propre à ton casque pour un son neutre et équilibré. Mémorisé pour cette sortie.", "Corrige la coloración propia de tus auriculares hacia un sonido neutro. Se recuerda para esta salida.", "Gleicht die Klangfärbung deines Kopfhörers zu einem neutralen Klang aus. Wird für diese Ausgabe gemerkt.", "ヘッドホン固有の音の癖をニュートラルに補正します。この出力ごとに記憶されます。") }
    static var headphoneCredit: String { tr("Corrections from the AutoEq project (MIT licence), toward the Harman target.", "Corrections issues du projet AutoEq (licence MIT), vers la cible Harman.", "Correcciones del proyecto AutoEq (licencia MIT), hacia la curva Harman.", "Korrekturen aus dem Projekt AutoEq (MIT-Lizenz), zur Harman-Zielkurve.", "AutoEq プロジェクト（MIT ライセンス）の補正、Harman ターゲット準拠。") }

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
        case "macbook": return tr("MacBook Speakers", "Haut-parleurs MacBook", "Altavoces MacBook", "MacBook-Lautsprecher", "MacBook スピーカー")
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

    // MARK: Settings window
    static var settingsMenu: String { tr("Settings…", "Réglages…", "Ajustes…", "Einstellungen …", "設定…") }
    static var general: String { tr("General", "Général", "General", "Allgemein", "一般") }
    static var shortcuts: String { tr("Shortcuts", "Raccourcis", "Atajos", "Kurzbefehle", "ショートカット") }
    static var updates: String { tr("Updates", "Mises à jour", "Actualizaciones", "Updates", "アップデート") }
    static var aboutTab: String { tr("About", "À propos", "Acerca de", "Über", "情報") }
    static var autoStandbyHelp: String { tr("After 20 seconds of silence, Relief releases the output to save battery.", "Après 20 secondes de silence, Relief libère la sortie audio pour économiser la batterie.", "Tras 20 segundos de silencio, Relief libera la salida para ahorrar batería.", "Nach 20 Sekunden Stille gibt Relief die Ausgabe frei, um Akku zu sparen.", "20秒間無音が続くと、バッテリー節約のため出力を解放します。") }
    static var autoOutputMode: String { tr("Choose Speakers or Headphones automatically", "Choisir Haut-parleurs ou Casque automatiquement", "Elegir altavoces o auriculares automáticamente", "Lautsprecher oder Kopfhörer automatisch wählen", "スピーカー/ヘッドフォンを自動選択") }
    static var autoOutputModeHelp: String { tr("Bluetooth and the headphones jack use the headphones mode. Your choice is remembered for each output.", "Le Bluetooth et la prise casque passent en mode casque. Ton choix est mémorisé pour chaque sortie.", "El Bluetooth y la toma de auriculares usan el modo auriculares. Tu elección se recuerda para cada salida.", "Bluetooth und Kopfhörerbuchse nutzen den Kopfhörermodus. Deine Wahl wird pro Ausgabe gemerkt.", "Bluetooth とヘッドフォン端子ではヘッドフォンモードを使用します。選択は出力ごとに記憶されます。") }
    static var permissions: String { tr("Permissions", "Autorisations", "Permisos", "Berechtigungen", "アクセス許可") }
    static var systemAudioRecording: String { tr("System Audio Recording", "Enregistrement audio du système", "Grabación de audio del sistema", "Systemaudioaufnahme", "システムオーディオ録音") }
    static var reset: String { tr("Reset", "Réinitialisation", "Restablecer", "Zurücksetzen", "リセット") }
    static var resetButton: String { tr("Reset", "Réinitialiser", "Restablecer", "Zurücksetzen", "リセット") }
    static var resetAppVolumes: String { tr("Reset all app volumes", "Réinitialiser le volume de toutes les apps", "Restablecer el volumen de todas las apps", "Alle App-Lautstärken zurücksetzen", "すべてのアプリの音量をリセット") }
    static var resetSoundConfirm: String { tr("Reset the equalizer, effects and booster to their defaults?", "Remettre l'égaliseur, les effets et l'amplificateur par défaut ?", "¿Restablecer el ecualizador, los efectos y el amplificador?", "Equalizer, Effekte und Booster zurücksetzen?", "イコライザ、エフェクト、ブースターを初期設定に戻しますか？") }
    static var shortcutsHelp: String { tr("Shortcuts work in every app. Click a field, then type the keys.", "Les raccourcis fonctionnent dans toutes les apps. Clique sur un champ puis tape les touches.", "Los atajos funcionan en todas las apps. Haz clic en un campo y pulsa las teclas.", "Kurzbefehle funktionieren in allen Apps. Feld anklicken, dann Tasten drücken.", "ショートカットはすべてのアプリで使えます。欄をクリックしてキーを押してください。") }
    static var restoreDefaults: String { tr("Restore Defaults", "Valeurs par défaut", "Restaurar valores", "Standard wiederherstellen", "デフォルトに戻す") }
    static var typeShortcut: String { tr("Type shortcut…", "Tape le raccourci…", "Pulsa el atajo…", "Kurzbefehl drücken …", "キーを入力…") }
    static var none: String { tr("None", "Aucun", "Ninguno", "Keiner", "なし") }
    static var clearShortcut: String { tr("Remove shortcut", "Supprimer le raccourci", "Quitar atajo", "Kurzbefehl entfernen", "ショートカットを削除") }
    static var currentVersion: String { tr("Current version", "Version actuelle", "Versión actual", "Aktuelle Version", "現在のバージョン") }
    static var checkNow: String { tr("New version", "Nouvelle version", "Nueva versión", "Neue Version", "新しいバージョン") }
    static var releaseNotes: String { tr("What's new in each version", "Nouveautés de chaque version", "Novedades de cada versión", "Neuerungen jeder Version", "各バージョンの新機能") }
    static func versionLabel(_ v: String) -> String { tr("Version \(v)", "Version \(v)", "Versión \(v)", "Version \(v)", "バージョン \(v)") }
    static var reportIssue: String { tr("Report a Problem", "Signaler un problème", "Informar de un problema", "Problem melden", "問題を報告") }

    // MARK: Shortcuts
    static var shortcutToggleRelief: String { tr("Turn Relief on or off", "Activer ou désactiver Relief", "Activar o desactivar Relief", "Relief ein- oder ausschalten", "Relief のオン/オフ") }
    static var shortcutShowPanel: String { tr("Show the panel", "Afficher le panneau", "Mostrar el panel", "Bedienfeld zeigen", "パネルを表示") }
    static var shortcutToggleEqualizer: String { tr("Turn the equalizer on or off", "Activer ou désactiver l'égaliseur", "Activar o desactivar el ecualizador", "Equalizer ein- oder ausschalten", "イコライザのオン/オフ") }
    static var shortcutNextPreset: String { tr("Next equalizer preset", "Préréglage d'égaliseur suivant", "Siguiente preajuste", "Nächstes Equalizer-Preset", "次のプリセット") }
    static var shortcutToggleOutputMode: String { tr("Switch Speakers / Headphones", "Basculer Haut-parleurs / Casque", "Cambiar altavoces / auriculares", "Lautsprecher / Kopfhörer wechseln", "スピーカー/ヘッドフォン切替") }
    static var shortcutToggleNightMode: String { tr("Turn night mode on or off", "Activer ou désactiver le mode nuit", "Activar o desactivar el modo nocturno", "Nachtmodus ein- oder ausschalten", "ナイトモードのオン/オフ") }
    static var shortcutBoostUp: String { tr("Booster up (+2 dB)", "Amplificateur plus fort (+2 dB)", "Subir amplificador (+2 dB)", "Booster lauter (+2 dB)", "ブースターを上げる (+2 dB)") }
    static var shortcutBoostDown: String { tr("Booster down (−2 dB)", "Amplificateur moins fort (−2 dB)", "Bajar amplificador (−2 dB)", "Booster leiser (−2 dB)", "ブースターを下げる (−2 dB)") }
    static var reliefOn: String { tr("Relief On", "Relief activé", "Relief activado", "Relief an", "Relief オン") }
    static var reliefOff: String { tr("Relief Off", "Relief désactivé", "Relief desactivado", "Relief aus", "Relief オフ") }
    static var on: String { tr("On", "Activé", "Activado", "An", "オン") }

    // MARK: Output and menus
    static var output: String { tr("Output", "Sortie", "Salida", "Ausgabe", "出力") }
    static var noOutput: String { tr("No output", "Aucune sortie", "Sin salida", "Keine Ausgabe", "出力なし") }
    static var soundSettings: String { tr("Sound Settings…", "Réglages Son…", "Ajustes de sonido…", "Ton-Einstellungen …", "サウンド設定…") }
    static var systemVolume: String { tr("System volume", "Volume du système", "Volumen del sistema", "Systemlautstärke", "システム音量") }
    static var equalizerEnabled: String { tr("Equalizer On", "Égaliseur activé", "Ecualizador activado", "Equalizer an", "イコライザ オン") }
    static var quitRelief: String { tr("Quit Relief", "Quitter Relief", "Salir de Relief", "Relief beenden", "Relief を終了") }
}
