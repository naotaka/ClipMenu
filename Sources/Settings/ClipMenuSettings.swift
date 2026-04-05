import Foundation
import Observation

@Observable
final class ClipMenuSettings {

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        registerLegacyDefaultsIfNeeded()
        loadFromDefaults()
        sanitizeAndPersist()
    }

    // MARK: - General

    var launchAtLogin: Bool = false { didSet { defaults.set(launchAtLogin, forKey: "loginItem") } }
    var suppressLoginItemAlert: Bool = false { didSet { defaults.set(suppressLoginItemAlert, forKey: "suppressAlertForLoginItem") } }
    var autoPasteAfterSelection: Bool = true { didSet { defaults.set(autoPasteAfterSelection, forKey: "inputPasteCommand") } }
    var reorderClipsAfterPasting: Bool = true { didSet { defaults.set(reorderClipsAfterPasting, forKey: "reorderClipsAfterPasting") } }
    var maxHistorySize: Int = 20 { didSet { defaults.set(maxHistorySize, forKey: "maxHistorySize") } }
    var saveHistoryOnQuit: Bool = true { didSet { defaults.set(saveHistoryOnQuit, forKey: "saveHistoryOnQuit") } }
    var exportHistoryAsSingleFile: Bool = true { didSet { defaults.set(exportHistoryAsSingleFile, forKey: "exportHistoryAsSingleFile") } }
    var exportSeparatorTag: Int = 1 { didSet { defaults.set(exportSeparatorTag, forKey: "tagOfSeparatorForExportHistoryToFile") } }
    var showStatusItem: Bool = true { didSet { defaults.set(showStatusItem, forKey: "showStatusItem") } }
    var storeTypes: [String: Bool] = [
        "String": true,
        "RTF": true,
        "RTFD": true,
        "PDF": true,
        "Filenames": true,
        "URL": true,
        "TIFF": true,
        "PICT": true,
    ] { didSet { defaults.set(storeTypes, forKey: "storeTypes") } }
    var excludeApps: [[String: String]] = [[
        "bundleIdentifier": "org.openoffice.script",
        "name": "OpenOffice.org",
    ]] { didSet { defaults.set(excludeApps, forKey: "excludeApps") } }

    // MARK: - Menu

    var maxMenuItemTitleLength: Int = 20 { didSet { defaults.set(maxMenuItemTitleLength, forKey: "maxMenuItemTitleLength") } }
    var numberOfItemsInline: Int = 0 { didSet { defaults.set(numberOfItemsInline, forKey: "numberOfItemsPlaceInline") } }
    var numberOfItemsInsideFolder: Int = 10 { didSet { defaults.set(numberOfItemsInsideFolder, forKey: "numberOfItemsPlaceInsideFolder") } }
    var numberedMenuItems: Bool = true { didSet { defaults.set(numberedMenuItems, forKey: "menuItemsAreMarkedWithNumbers") } }
    var numberingStartsAtZero: Bool = false { didSet { defaults.set(numberingStartsAtZero, forKey: "menuItemsTitleStartWithZero") } }
    var numericKeyEquivalents: Bool = false { didSet { defaults.set(numericKeyEquivalents, forKey: "addNumericKeyEquivalents") } }
    var showClearHistoryItem: Bool = true { didSet { defaults.set(showClearHistoryItem, forKey: "addClearHistoryMenuItem") } }
    var showAlertBeforeClearHistory: Bool = true { didSet { defaults.set(showAlertBeforeClearHistory, forKey: "showAlertBeforeClearHistory") } }
    var showLabelsInMenu: Bool = true { didSet { defaults.set(showLabelsInMenu, forKey: "showLabelsInMenu") } }
    var showTooltipsInMenu: Bool = true { didSet { defaults.set(showTooltipsInMenu, forKey: "showToolTipOnMenuItem") } }
    var maxTooltipLength: Int = 200 { didSet { defaults.set(maxTooltipLength, forKey: "maxLengthOfToolTipKey") } }
    var changeFontSize: Bool = false { didSet { defaults.set(changeFontSize, forKey: "changeFontSize") } }
    var fontSizeMode: Int = 0 { didSet { defaults.set(fontSizeMode, forKey: "howToChangeFontSize") } }
    var selectedFontSize: Int = 14 { didSet { defaults.set(selectedFontSize, forKey: "selectedFontSize") } }
    var showImageInMenu: Bool = true { didSet { defaults.set(showImageInMenu, forKey: "showImageInTheMenu") } }
    var thumbnailWidth: Int = 100 { didSet { defaults.set(thumbnailWidth, forKey: "thumbnailWidth") } }
    var thumbnailHeight: Int = 32 { didSet { defaults.set(thumbnailHeight, forKey: "thumbnailHeight") } }
    var showIconInMenu: Bool = true { didSet { defaults.set(showIconInMenu, forKey: "showIconInTheMenu") } }
    var menuIconSize: Int = 16 { didSet { defaults.set(menuIconSize, forKey: "menuIconSize") } }
    var menuIconOfFileTypeTagForString: Int = 1 { didSet { defaults.set(menuIconOfFileTypeTagForString, forKey: "menuIconOfFileTypeTagForString") } }
    var menuIconOfFileTypeForString: String = "TEXT" { didSet { defaults.set(menuIconOfFileTypeForString, forKey: "menuIconOfFileTypeForString") } }
    var menuIconOfFileTypeTagForRTF: Int = 0 { didSet { defaults.set(menuIconOfFileTypeTagForRTF, forKey: "menuIconOfFileTypeTagForRTF") } }
    var menuIconOfFileTypeForRTF: String = "rtf" { didSet { defaults.set(menuIconOfFileTypeForRTF, forKey: "menuIconOfFileTypeForRTF") } }
    var menuIconOfFileTypeTagForRTFD: Int = 0 { didSet { defaults.set(menuIconOfFileTypeTagForRTFD, forKey: "menuIconOfFileTypeTagForRTFD") } }
    var menuIconOfFileTypeForRTFD: String = "rtfd" { didSet { defaults.set(menuIconOfFileTypeForRTFD, forKey: "menuIconOfFileTypeForRTFD") } }
    var menuIconOfFileTypeTagForPDF: Int = 0 { didSet { defaults.set(menuIconOfFileTypeTagForPDF, forKey: "menuIconOfFileTypeTagForPDF") } }
    var menuIconOfFileTypeForPDF: String = "pdf" { didSet { defaults.set(menuIconOfFileTypeForPDF, forKey: "menuIconOfFileTypeForPDF") } }
    var menuIconOfFileTypeTagForFilenames: Int = 1 { didSet { defaults.set(menuIconOfFileTypeTagForFilenames, forKey: "menuIconOfFileTypeTagForFilenames") } }
    var menuIconOfFileTypeForFilenames: String = "clpu" { didSet { defaults.set(menuIconOfFileTypeForFilenames, forKey: "menuIconOfFileTypeForFilenames") } }
    var menuIconOfFileTypeTagForURL: Int = 1 { didSet { defaults.set(menuIconOfFileTypeTagForURL, forKey: "menuIconOfFileTypeTagForURL") } }
    var menuIconOfFileTypeForURL: String = "gurl" { didSet { defaults.set(menuIconOfFileTypeForURL, forKey: "menuIconOfFileTypeForURL") } }
    var menuIconOfFileTypeTagForTIFF: Int = 0 { didSet { defaults.set(menuIconOfFileTypeTagForTIFF, forKey: "menuIconOfFileTypeTagForTIFF") } }
    var menuIconOfFileTypeForTIFF: String = "tiff" { didSet { defaults.set(menuIconOfFileTypeForTIFF, forKey: "menuIconOfFileTypeForTIFF") } }
    var menuIconOfFileTypeTagForPICT: Int = 0 { didSet { defaults.set(menuIconOfFileTypeTagForPICT, forKey: "menuIconOfFileTypeTagForPICT") } }
    var menuIconOfFileTypeForPICT: String = "pict" { didSet { defaults.set(menuIconOfFileTypeForPICT, forKey: "menuIconOfFileTypeForPICT") } }

    // MARK: - Hot Keys

    var hotKeys: [String: Any] = [
        "ClipMenu": ["keyCode": 9, "modifiers": 768],
        "HistoryMenu": ["keyCode": 9, "modifiers": 4352],
        "SnippetsMenu": ["keyCode": 11, "modifiers": 768],
    ] { didSet { defaults.set(hotKeys, forKey: "hotKeys") } }

    // MARK: - Actions

    var enableAction: Bool = true { didSet { defaults.set(enableAction, forKey: "enableAction") } }
    var invokeActionImmediately: Bool = false { didSet { defaults.set(invokeActionImmediately, forKey: "invokeActionImmediately") } }
    var controlClickBehavior: String = "popUpActionMenu" { didSet { defaults.set(controlClickBehavior, forKey: "controlClickBehavior") } }
    var shiftClickBehavior: String = "" { didSet { defaults.set(shiftClickBehavior, forKey: "shiftClickBehavior") } }
    var optionClickBehavior: String = "" { didSet { defaults.set(optionClickBehavior, forKey: "optionClickBehavior") } }
    var commandClickBehavior: String = "" { didSet { defaults.set(commandClickBehavior, forKey: "commandClickBehavior") } }

    // MARK: - Snippets

    var positionOfSnippets: Int = 1 { didSet { defaults.set(positionOfSnippets, forKey: "positionOfSnippets") } }

    // MARK: - Updates

    var enableAutomaticCheck: Bool = true { didSet { defaults.set(enableAutomaticCheck, forKey: "enableAutomaticCheck") } }
    var enableAutomaticCheckPreRelease: Bool = false { didSet { defaults.set(enableAutomaticCheckPreRelease, forKey: "enableAutomaticCheckPreReleaseKey") } }
    var updateCheckInterval: Int = 86_400 { didSet { defaults.set(updateCheckInterval, forKey: "updateCheckInterval") } }

    /// Re-reads all persisted keys from UserDefaults.
    /// Useful on startup and after external defaults changes.
    func reload() {
        loadFromDefaults()
        sanitizeAndPersist()
    }

    private func boolValue(_ key: String, default fallback: Bool) -> Bool {
        (defaults.object(forKey: key) as? Bool) ?? fallback
    }

    private func intValue(_ key: String, default fallback: Int) -> Int {
        (defaults.object(forKey: key) as? Int) ?? fallback
    }

    private func stringValue(_ key: String, default fallback: String) -> String {
        (defaults.object(forKey: key) as? String) ?? fallback
    }

    private func loadFromDefaults() {
        launchAtLogin = boolValue("loginItem", default: false)
        suppressLoginItemAlert = boolValue("suppressAlertForLoginItem", default: false)
        autoPasteAfterSelection = boolValue("inputPasteCommand", default: true)
        reorderClipsAfterPasting = boolValue("reorderClipsAfterPasting", default: true)
        maxHistorySize = intValue("maxHistorySize", default: 20)
        saveHistoryOnQuit = boolValue("saveHistoryOnQuit", default: true)
        exportHistoryAsSingleFile = boolValue("exportHistoryAsSingleFile", default: true)
        exportSeparatorTag = intValue("tagOfSeparatorForExportHistoryToFile", default: 1)
        showStatusItem = boolValue("showStatusItem", default: true)
        storeTypes = (defaults.dictionary(forKey: "storeTypes") as? [String: Bool]) ?? Self.defaultStoreTypes
        excludeApps = (defaults.array(forKey: "excludeApps") as? [[String: String]]) ?? Self.defaultExcludeApps

        maxMenuItemTitleLength = intValue("maxMenuItemTitleLength", default: 20)
        numberOfItemsInline = intValue("numberOfItemsPlaceInline", default: 0)
        numberOfItemsInsideFolder = intValue("numberOfItemsPlaceInsideFolder", default: 10)
        numberedMenuItems = boolValue("menuItemsAreMarkedWithNumbers", default: true)
        numberingStartsAtZero = boolValue("menuItemsTitleStartWithZero", default: false)
        numericKeyEquivalents = boolValue("addNumericKeyEquivalents", default: false)
        showClearHistoryItem = boolValue("addClearHistoryMenuItem", default: true)
        showAlertBeforeClearHistory = boolValue("showAlertBeforeClearHistory", default: true)
        showLabelsInMenu = boolValue("showLabelsInMenu", default: true)
        showTooltipsInMenu = boolValue("showToolTipOnMenuItem", default: true)
        maxTooltipLength = intValue("maxLengthOfToolTipKey", default: 200)
        changeFontSize = boolValue("changeFontSize", default: false)
        fontSizeMode = intValue("howToChangeFontSize", default: 0)
        selectedFontSize = intValue("selectedFontSize", default: 14)
        showImageInMenu = boolValue("showImageInTheMenu", default: true)
        thumbnailWidth = intValue("thumbnailWidth", default: 100)
        thumbnailHeight = intValue("thumbnailHeight", default: 32)
        showIconInMenu = boolValue("showIconInTheMenu", default: true)
        menuIconSize = intValue("menuIconSize", default: 16)
        menuIconOfFileTypeTagForString = intValue("menuIconOfFileTypeTagForString", default: 1)
        menuIconOfFileTypeForString = stringValue("menuIconOfFileTypeForString", default: "TEXT")
        menuIconOfFileTypeTagForRTF = intValue("menuIconOfFileTypeTagForRTF", default: 0)
        menuIconOfFileTypeForRTF = stringValue("menuIconOfFileTypeForRTF", default: "rtf")
        menuIconOfFileTypeTagForRTFD = intValue("menuIconOfFileTypeTagForRTFD", default: 0)
        menuIconOfFileTypeForRTFD = stringValue("menuIconOfFileTypeForRTFD", default: "rtfd")
        menuIconOfFileTypeTagForPDF = intValue("menuIconOfFileTypeTagForPDF", default: 0)
        menuIconOfFileTypeForPDF = stringValue("menuIconOfFileTypeForPDF", default: "pdf")
        menuIconOfFileTypeTagForFilenames = intValue("menuIconOfFileTypeTagForFilenames", default: 1)
        menuIconOfFileTypeForFilenames = stringValue("menuIconOfFileTypeForFilenames", default: "clpu")
        menuIconOfFileTypeTagForURL = intValue("menuIconOfFileTypeTagForURL", default: 1)
        menuIconOfFileTypeForURL = stringValue("menuIconOfFileTypeForURL", default: "gurl")
        menuIconOfFileTypeTagForTIFF = intValue("menuIconOfFileTypeTagForTIFF", default: 0)
        menuIconOfFileTypeForTIFF = stringValue("menuIconOfFileTypeForTIFF", default: "tiff")
        menuIconOfFileTypeTagForPICT = intValue("menuIconOfFileTypeTagForPICT", default: 0)
        menuIconOfFileTypeForPICT = stringValue("menuIconOfFileTypeForPICT", default: "pict")

        hotKeys = defaults.dictionary(forKey: "hotKeys") ?? Self.defaultHotKeys

        enableAction = boolValue("enableAction", default: true)
        invokeActionImmediately = boolValue("invokeActionImmediately", default: false)
        controlClickBehavior = stringValue("controlClickBehavior", default: "popUpActionMenu")
        shiftClickBehavior = stringValue("shiftClickBehavior", default: "")
        optionClickBehavior = stringValue("optionClickBehavior", default: "")
        commandClickBehavior = stringValue("commandClickBehavior", default: "")

        positionOfSnippets = intValue("positionOfSnippets", default: 1)

        enableAutomaticCheck = boolValue("enableAutomaticCheck", default: true)
        enableAutomaticCheckPreRelease = boolValue("enableAutomaticCheckPreReleaseKey", default: false)
        updateCheckInterval = intValue("updateCheckInterval", default: 86_400)
    }

    private func sanitizeAndPersist() {
        maxHistorySize = max(maxHistorySize, 1)

        maxMenuItemTitleLength = max(maxMenuItemTitleLength, 1)
        numberOfItemsInline = max(numberOfItemsInline, 0)
        numberOfItemsInsideFolder = max(numberOfItemsInsideFolder, 1)
        maxTooltipLength = max(maxTooltipLength, 1)
        selectedFontSize = max(selectedFontSize, 8)
        thumbnailWidth = max(thumbnailWidth, 1)
        thumbnailHeight = max(thumbnailHeight, 1)
        menuIconSize = [16, 32, 48].contains(menuIconSize) ? menuIconSize : 16
        fontSizeMode = [0, 1].contains(fontSizeMode) ? fontSizeMode : 0
        positionOfSnippets = [0, 1, 2].contains(positionOfSnippets) ? positionOfSnippets : 1

        if controlClickBehavior.isEmpty { controlClickBehavior = "popUpActionMenu" }
    }

    private func registerLegacyDefaultsIfNeeded() {
        defaults.register(defaults: [
            "hotKeys": Self.defaultHotKeys,
            "loginItem": false,
            "suppressAlertForLoginItem": false,
            "inputPasteCommand": true,
            "reorderClipsAfterPasting": true,
            "maxHistorySize": 20,
            "saveHistoryOnQuit": true,
            "exportHistoryAsSingleFile": true,
            "tagOfSeparatorForExportHistoryToFile": 1,
            "showStatusItem": true,
            "storeTypes": Self.defaultStoreTypes,
            "excludeApps": Self.defaultExcludeApps,
            "maxMenuItemTitleLength": 20,
            "numberOfItemsPlaceInline": 0,
            "numberOfItemsPlaceInsideFolder": 10,
            "menuItemsAreMarkedWithNumbers": true,
            "menuItemsTitleStartWithZero": false,
            "addNumericKeyEquivalents": false,
            "addClearHistoryMenuItem": true,
            "showAlertBeforeClearHistory": true,
            "showLabelsInMenu": true,
            "showToolTipOnMenuItem": true,
            "maxLengthOfToolTipKey": 200,
            "changeFontSize": false,
            "howToChangeFontSize": 0,
            "selectedFontSize": 14,
            "showImageInTheMenu": true,
            "thumbnailWidth": 100,
            "thumbnailHeight": 32,
            "showIconInTheMenu": true,
            "menuIconSize": 16,
            "menuIconOfFileTypeTagForString": 1,
            "menuIconOfFileTypeForString": "TEXT",
            "menuIconOfFileTypeTagForRTF": 0,
            "menuIconOfFileTypeForRTF": "rtf",
            "menuIconOfFileTypeTagForRTFD": 0,
            "menuIconOfFileTypeForRTFD": "rtfd",
            "menuIconOfFileTypeTagForPDF": 0,
            "menuIconOfFileTypeForPDF": "pdf",
            "menuIconOfFileTypeTagForFilenames": 1,
            "menuIconOfFileTypeForFilenames": "clpu",
            "menuIconOfFileTypeTagForURL": 1,
            "menuIconOfFileTypeForURL": "gurl",
            "menuIconOfFileTypeTagForTIFF": 0,
            "menuIconOfFileTypeForTIFF": "tiff",
            "menuIconOfFileTypeTagForPICT": 0,
            "menuIconOfFileTypeForPICT": "pict",
            "enableAction": true,
            "invokeActionImmediately": false,
            "controlClickBehavior": "popUpActionMenu",
            "shiftClickBehavior": "",
            "optionClickBehavior": "",
            "commandClickBehavior": "",
            "positionOfSnippets": 1,
            "enableAutomaticCheck": true,
            "enableAutomaticCheckPreReleaseKey": false,
            "updateCheckInterval": 86_400,
        ])
    }

    private static let defaultStoreTypes: [String: Bool] = [
        "String": true,
        "RTF": true,
        "RTFD": true,
        "PDF": true,
        "Filenames": true,
        "URL": true,
        "TIFF": true,
        "PICT": true,
    ]

    private static let defaultExcludeApps: [[String: String]] = [[
        "bundleIdentifier": "org.openoffice.script",
        "name": "OpenOffice.org",
    ]]

    private static let defaultHotKeys: [String: [String: Int]] = [
        "ClipMenu": ["keyCode": 9, "modifiers": 768],
        "HistoryMenu": ["keyCode": 9, "modifiers": 4352],
        "SnippetsMenu": ["keyCode": 11, "modifiers": 768],
    ]
}
