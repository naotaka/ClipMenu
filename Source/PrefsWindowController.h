//
//  PrefsWindowController.h
//  ClipMenu
//
//  Created by Naotaka Morimoto on 08/03/04.
//  Copyright 2008 Naotaka Morimoto. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "DBPrefsWindowController.h"


#pragma mark Preference Keys
/* General */
extern NSString *const CMPrefLoginItemKey;
extern NSString *const CMPrefSuppressAlertForLoginItemKey;
extern NSString *const CMPrefInputPasteCommandKey;
extern NSString *const CMPrefReorderClipsAfterPasting;
extern NSString *const CMPrefMaxHistorySizeKey;
extern NSString *const CMPrefAutosaveDelayKey;
extern NSString *const CMPrefSaveHistoryOnQuitKey;
extern NSString *const CMPrefExportHistoryAsSingleFileKey;
extern NSString *const CMPrefTagOfSeparatorForExportHistoryToFileKey;
extern NSString *const CMPrefShowStatusItemKey;
extern NSString *const CMPrefTimeIntervalKey;
extern NSString *const CMPrefStoreTypesKey;
extern NSString *const CMPrefExcludeAppsKey;
/* Menu */
extern NSString *const CMPrefMaxMenuItemTitleLengthKey;
extern NSString *const CMPrefNumberOfItemsPlaceInlineKey;
extern NSString *const CMPrefNumberOfItemsPlaceInsideFolderKey;
extern NSString *const CMPrefMenuItemsAreMarkedWithNumbersKey;
extern NSString *const CMPrefMenuItemsTitleStartWithZeroKey;
extern NSString *const CMPrefAddNumericKeyEquivalentsKey;
extern NSString *const CMPrefAddClearHistoryMenuItemKey;
extern NSString *const CMPrefShowAlertBeforeClearHistoryKey;
extern NSString *const CMPrefShowLabelsInMenuKey;
extern NSString *const CMPrefShowToolTipOnMenuItemKey;
extern NSString *const CMPrefMaxLengthOfToolTipKey;
extern NSString *const CMPrefChangeFontSizeKey;
extern NSString *const CMPrefHowToChangeFontSizeKey;
extern NSString *const CMPrefSelectedFontSizeKey;
extern NSString *const CMPrefShowImageInTheMenuKey;
extern NSString *const CMPrefThumbnailWidthKey;
extern NSString *const CMPrefThumbnailHeightKey;
extern NSString *const CMPrefShowIconInTheMenuKey;
/* - Menu Icon - */
extern NSString *const CMPrefMenuIconSizeKey;
extern NSString *const CMPrefMenuIconOfFileTypeTagForStringKey;
extern NSString *const CMPrefMenuIconOfFileTypeForStringKey;
extern NSString *const CMPrefMenuIconOfFileTypeTagForRTFKey;
extern NSString *const CMPrefMenuIconOfFileTypeForRTFKey;
extern NSString *const CMPrefMenuIconOfFileTypeTagForRTFDKey;
extern NSString *const CMPrefMenuIconOfFileTypeForRTFDKey;
extern NSString *const CMPrefMenuIconOfFileTypeTagForPDFKey;
extern NSString *const CMPrefMenuIconOfFileTypeForPDFKey;
extern NSString *const CMPrefMenuIconOfFileTypeTagForFilenamesKey;
extern NSString *const CMPrefMenuIconOfFileTypeForFilenamesKey;
extern NSString *const CMPrefMenuIconOfFileTypeTagForURLKey;
extern NSString *const CMPrefMenuIconOfFileTypeForURLKey;
extern NSString *const CMPrefMenuIconOfFileTypeTagForTIFFKey;
extern NSString *const CMPrefMenuIconOfFileTypeForTIFFKey;
extern NSString *const CMPrefMenuIconOfFileTypeTagForPICTKey;
extern NSString *const CMPrefMenuIconOfFileTypeForPICTKey;
/* Hot Keys */
extern NSString *const CMPrefHotKeysKey;

/* Action */
extern NSString *const CMPrefEnableActionKey;
extern NSString *const CMPrefInvokeActionImmediatelyKey;
extern NSString *const CMPrefContorlClickBehaviorKey;
extern NSString *const CMPrefShiftClickBehaviorKey;
extern NSString *const CMPrefOptionClickBehaviorKey;
extern NSString *const CMPrefCommandClickBehaviorKey;
/* Snippet */
extern NSString *const CMPrefPositionOfSnippetsKey;
/* Updates */
extern NSString *const CMEnableAutomaticCheckKey;
extern NSString *const CMEnableAutomaticCheckPreReleaseKey;
extern NSString *const CMUpdateCheckIntervalKey;


#pragma mark Notifications
extern NSString *const CMPreferencePanelWillCloseNotification;


@class SRRecorderControl, ActionNodeController, ActionPopUpButton;

@interface PrefsWindowController : DBPrefsWindowController <NSWindowDelegate>
{
	IBOutlet NSView *generalPrefsView;
	IBOutlet NSView *menuPrefsView;
	IBOutlet NSView *iconPrefsView;
	IBOutlet NSView *actionPrefsView;
	IBOutlet NSView *shortcutPrefsView;
	IBOutlet NSView *updatesPrefsView;
	
	IBOutlet ActionNodeController *actionNodeController;
	
	/* Hot Keys */
	IBOutlet SRRecorderControl *shortcutRecorder;
	IBOutlet SRRecorderControl *historyShortCutRecorder;
	IBOutlet SRRecorderControl *snippetsShortcutRecorder;
	NSMutableArray *shortcutRecorders;
	
	NSMutableDictionary *storeTypes;
	NSArray *fontSizePopUpMenuItems;
	
	/* Modifiers pop up bottons */
	NSArray *modifiersPopUpMenuItems;
	IBOutlet NSPopUpButton *controlPopUpButton;
	IBOutlet NSPopUpButton *shiftPopUpButton;
	IBOutlet NSPopUpButton *optionPopUpButton;
	IBOutlet NSPopUpButton *commandPopUpButton;
	
	/* Exclude List */
	IBOutlet NSArrayController *excludeListController;
	IBOutlet NSPanel *excludeListPanel;
	IBOutlet ActionPopUpButton *addExcludeListButtion;
	NSMutableArray *excludeList;
}
@property (nonatomic, copy) NSMutableArray *shortcutRecorders;
@property (nonatomic, copy) NSMutableDictionary *storeTypes;
@property (nonatomic, retain) NSArray *fontSizePopUpMenuItems;
@property (retain) NSArray *modifiersPopUpMenuItems;
@property (nonatomic, copy) NSMutableArray *excludeList;

- (IBAction)openExcludeOptions:(id)sender;
- (IBAction)doneExcludeListPanel:(id)sender;
- (IBAction)cancelExcludeListPanel:(id)sender;
- (void)addToExcludeList:(id)sender;

- (IBAction)exportHistory:(id)sender;

@end
