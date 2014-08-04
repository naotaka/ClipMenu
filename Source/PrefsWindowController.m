//
//  PrefsWindowController.m
//  ClipMenu
//
//  Created by Naotaka Morimoto on 08/03/04.
//  Copyright 2008 Naotaka Morimoto. All rights reserved.
//

#import "PrefsWindowController.h"
#import "constants.h"
#import "CMUtilities.h"
#import "ClipsController.h"
#import "MenuController.h"
#import "ActionNodeController.h"
#import "ActionNode.h"
#import "ActionController.h"
#import "ImageAndTextCell.h"
#import "NMLoginItems.h"

#import "PTHotKey.h"
#import "PTHotKeyCenter.h"
#import <ShortcutRecorder/SRRecorderControl.h>


#pragma mark Preference Keys
/* General */
NSString *const CMPrefLoginItemKey = @"loginItem";
NSString *const CMPrefSuppressAlertForLoginItemKey = @"suppressAlertForLoginItem";
NSString *const CMPrefInputPasteCommandKey = @"inputPasteCommand";
NSString *const CMPrefReorderClipsAfterPasting = @"reorderClipsAfterPasting";
NSString *const CMPrefMaxHistorySizeKey = @"maxHistorySize";
NSString *const CMPrefAutosaveDelayKey = @"autosaveDelay";
NSString *const CMPrefSaveHistoryOnQuitKey = @"saveHistoryOnQuit";
NSString *const CMPrefExportHistoryAsSingleFileKey = @"exportHistoryAsSingleFile";;
NSString *const CMPrefTagOfSeparatorForExportHistoryToFileKey = @"tagOfSeparatorForExportHistoryToFile";
NSString *const CMPrefShowStatusItemKey = @"showStatusItem";
NSString *const CMPrefTimeIntervalKey = @"timeInterval";
NSString *const CMPrefStoreTypesKey = @"storeTypes";
NSString *const CMPrefExcludeAppsKey = @"excludeApps";
/* Menu */
NSString *const CMPrefMaxMenuItemTitleLengthKey = @"maxMenuItemTitleLength";
NSString *const CMPrefNumberOfItemsPlaceInlineKey = @"numberOfItemsPlaceInline";
NSString *const CMPrefNumberOfItemsPlaceInsideFolderKey = @"numberOfItemsPlaceInsideFolder";
NSString *const CMPrefMenuItemsAreMarkedWithNumbersKey = @"menuItemsAreMarkedWithNumbers";
NSString *const CMPrefMenuItemsTitleStartWithZeroKey = @"menuItemsTitleStartWithZero";
NSString *const CMPrefAddNumericKeyEquivalentsKey = @"addNumericKeyEquivalents";
NSString *const CMPrefAddClearHistoryMenuItemKey = @"addClearHistoryMenuItem";
NSString *const CMPrefShowAlertBeforeClearHistoryKey = @"showAlertBeforeClearHistory";
NSString *const CMPrefShowLabelsInMenuKey = @"showLabelsInMenu";
NSString *const CMPrefShowToolTipOnMenuItemKey = @"showToolTipOnMenuItem";
NSString *const CMPrefMaxLengthOfToolTipKey = @"maxLengthOfToolTipKey";
NSString *const CMPrefChangeFontSizeKey = @"changeFontSize";
NSString *const CMPrefHowToChangeFontSizeKey = @"howToChangeFontSize";
NSString *const CMPrefSelectedFontSizeKey = @"selectedFontSize";
NSString *const CMPrefShowImageInTheMenuKey = @"showImageInTheMenu";
NSString *const CMPrefThumbnailWidthKey = @"thumbnailWidth";
NSString *const CMPrefThumbnailHeightKey = @"thumbnailHeight";
NSString *const CMPrefShowIconInTheMenuKey = @"showIconInTheMenu";
/* - Menu Icon - */
NSString *const CMPrefMenuIconSizeKey = @"menuIconSize";
NSString *const CMPrefMenuIconOfFileTypeTagForStringKey = @"menuIconOfFileTypeTagForString";
NSString *const CMPrefMenuIconOfFileTypeForStringKey = @"menuIconOfFileTypeForString";
NSString *const CMPrefMenuIconOfFileTypeTagForRTFKey = @"menuIconOfFileTypeTagForRTF";
NSString *const CMPrefMenuIconOfFileTypeForRTFKey = @"menuIconOfFileTypeForRTF";
NSString *const CMPrefMenuIconOfFileTypeTagForRTFDKey = @"menuIconOfFileTypeTagForRTFD";
NSString *const CMPrefMenuIconOfFileTypeForRTFDKey = @"menuIconOfFileTypeForRTFD";
NSString *const CMPrefMenuIconOfFileTypeTagForPDFKey = @"menuIconOfFileTypeTagForPDF";
NSString *const CMPrefMenuIconOfFileTypeForPDFKey = @"menuIconOfFileTypeForPDF";
NSString *const CMPrefMenuIconOfFileTypeTagForFilenamesKey = @"menuIconOfFileTypeTagForFilenames";
NSString *const CMPrefMenuIconOfFileTypeForFilenamesKey = @"menuIconOfFileTypeForFilenames";
NSString *const CMPrefMenuIconOfFileTypeTagForURLKey = @"menuIconOfFileTypeTagForURL";
NSString *const CMPrefMenuIconOfFileTypeForURLKey = @"menuIconOfFileTypeForURL";
NSString *const CMPrefMenuIconOfFileTypeTagForTIFFKey = @"menuIconOfFileTypeTagForTIFF";
NSString *const CMPrefMenuIconOfFileTypeForTIFFKey = @"menuIconOfFileTypeForTIFF";
NSString *const CMPrefMenuIconOfFileTypeTagForPICTKey = @"menuIconOfFileTypeTagForPICT";
NSString *const CMPrefMenuIconOfFileTypeForPICTKey = @"menuIconOfFileTypeForPICT";
/* Hot Keys */
NSString *const CMPrefHotKeysKey = @"hotKeys";
/* Action */
NSString *const CMPrefEnableActionKey = @"enableAction";
NSString *const CMPrefInvokeActionImmediatelyKey = @"invokeActionImmediately";
NSString *const CMPrefContorlClickBehaviorKey = @"controlClickBehavior";
NSString *const CMPrefShiftClickBehaviorKey = @"shiftClickBehavior";
NSString *const CMPrefOptionClickBehaviorKey = @"optionClickBehavior";
NSString *const CMPrefCommandClickBehaviorKey = @"commandClickBehavior";
/* Snippet */
NSString *const CMPrefPositionOfSnippetsKey = @"positionOfSnippets";
/* Updates */
NSString *const CMEnableAutomaticCheckKey = @"enableAutomaticCheck";
NSString *const CMEnableAutomaticCheckPreReleaseKey = @"enableAutomaticCheckPreReleaseKey";
NSString *const CMUpdateCheckIntervalKey = @"updateCheckInterval";


#pragma mark Notifications
NSString *const CMPreferencePanelWillCloseNotification = @"CMPreferencePanelWillCloseNotification";


@interface PrefsWindowController ()
- (void)_prepareHotKeys;
- (void)_changeHotKeyByShortcutRecorder:(SRRecorderControl *)aRecorder withKeyCombo:(PTKeyCombo *)keyCombo;
- (void)_prepareFontSizePopUpMenuItems;
- (NSArray *)_actionsFromNodes:(NSArray *)nodes;
- (void)_prepareModifiersPopUpMenuItems;
- (void)_buildModifiersPopUpMenuItems;

//- (void)_checkLoginItemState;
//- (void)_changeLoginItemWithNumber:(NSNumber *)number;

- (void)_prepareAddToExcludeListMenu;
- (void)_addAppInfoToExcludeList:(NSDictionary *)appInfo;
- (void)_addSelectedAppToExcludeList:(id)sender;

- (void)_exportHistoryAsSingleFile;
- (void)_exportHistoryAsMultipleFiles;
- (void)_exportHistoryAsSingleFile:(BOOL)singleFile sheet:(NSSavePanel *)sheet returnCode:(NSInteger)returnCode;
@end


@implementation PrefsWindowController

@synthesize shortcutRecorders;
@synthesize storeTypes;
@synthesize fontSizePopUpMenuItems;
@synthesize modifiersPopUpMenuItems;
@synthesize excludeList;


NSDictionary *separatorItemDict()
{
	return [NSDictionary dictionaryWithObjectsAndKeys:
			@"-", kTitle,
			[NSNull null], kBehavior,
			nil];
}

BOOL sameBehaviors(id a, id b)
{
	if ([a isEqualTo:b]
		|| ([a respondsToSelector:@selector( isEqualToString: )]
			&& [a isEqualToString:b])) {
		return YES;
	}
	return NO;
}

#pragma mark Initialize

/* -initWithWindow: is the designated initializer for NSWindowController. */
- (id)initWithWindow:(NSWindow *)window
{
	self = [super initWithWindow:nil];
	if (self) {		
		NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
		
		[self setStoreTypes:[defaults objectForKey:CMPrefStoreTypesKey]];
//		[self setExcludeList:[defaults objectForKey:CMPrefExcludeAppsKey]];
		[self _prepareFontSizePopUpMenuItems];
	}
	return self;
}

- (void)dealloc
{
	[[self window] setDelegate:nil];
	
	[shortcutRecorders release], shortcutRecorders = nil;
	[storeTypes release], storeTypes = nil;
	[fontSizePopUpMenuItems release], fontSizePopUpMenuItems = nil;
	[modifiersPopUpMenuItems release], modifiersPopUpMenuItems = nil;
	[excludeList release], excludeList = nil;
	
	[super dealloc];
}

- (void)awakeFromNib
{
//	NSLog(@"awakeFromNib");
		
	[actionNodeController handleAwakeFromNib];
	
	[self _prepareHotKeys];
	
	/* Pop up menus for modified click */
	[NSThread detachNewThreadSelector:@selector( _prepareModifiersPopUpMenuItems )
							 toTarget:self
						   withObject:nil];
}

- (void)windowDidLoad
{
	[super windowDidLoad];
	
	NSWindow *window = [self window];
	[window setDelegate:self];
	[window setCollectionBehavior:NSWindowCollectionBehaviorCanJoinAllSpaces];
    
    
}

#pragma mark -
#pragma mark Accessors

#pragma mark - Write -

- (void)setShortcutRecorders:(NSMutableArray *)newRecorders
{
	if (shortcutRecorders != newRecorders) {
		[shortcutRecorders release];
		shortcutRecorders = [newRecorders mutableCopy];
	}
}

- (void)setStoreTypes:(NSMutableDictionary *)newTypes
{
	if (storeTypes != newTypes) {
		[storeTypes release];
		storeTypes = [newTypes mutableCopy];
	}
}

- (void)setExcludeList:(NSMutableArray *)newList
{
	if (excludeList != newList) {
		[excludeList release];
		excludeList = [newList mutableCopy];
	}
}

#pragma mark -
#pragma mark Delegate
#pragma mark - NSWindow -

- (void)windowWillClose:(NSNotification *)aNotification
{
//	NSLog(@"windowWillClose");
	
	/* Save pref settings */
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	[defaults setObject:storeTypes forKey:CMPrefStoreTypesKey];
	
	/* Save actions */
	[[ActionController sharedInstance] setValue:[actionNodeController actionNodes]
										 forKey:@"actionNodes"];
	
	/* Pop up menus for modified click */	
	NSString *representedObject;
	representedObject = [[controlPopUpButton selectedItem] representedObject];
	[defaults setObject:representedObject forKey:CMPrefContorlClickBehaviorKey];
	
	representedObject = [[shiftPopUpButton selectedItem] representedObject];
	[defaults setObject:representedObject forKey:CMPrefShiftClickBehaviorKey];
	
	representedObject = [[optionPopUpButton selectedItem] representedObject];
	[defaults setObject:representedObject forKey:CMPrefOptionClickBehaviorKey];
	
	representedObject = [[commandPopUpButton selectedItem] representedObject];
	[defaults setObject:representedObject forKey:CMPrefCommandClickBehaviorKey];
		
	/* Window */
	NSWindow *window = [self window];
	if (![window makeFirstResponder:window]) {
		[window endEditingFor:nil];
	}
	[NSApp deactivate];
	
	/* Send Notification */
	[[NSNotificationCenter defaultCenter] postNotificationName:CMPreferencePanelWillCloseNotification
														object:nil];
}

//- (void)windowDidBecomeKey:(NSNotification *)aNotification
//{
//	NSLog(@"become");
//	[[NSApplication sharedApplication] activateIgnoringOtherApps:YES];
//
////	NSInteger newWindowLevel = [[self window] level] + 1;
////	[[self window] setLevel:newWindowLevel];
//}
	
//- (void)windowDidResignKey:(NSNotification *)aNotification
//{
//	NSLog(@"resign");
//	[[self window] setLevel:NSNormalWindowLevel];
//}

#pragma mark - SRRecorderControl -

//- (BOOL)shortcutRecorder:(SRRecorderControl *)aRecorder isKeyCode:(NSInteger)keyCode andFlagsTaken:(NSUInteger)flags reason:(NSString **)aReason
//{
//	if (aRecorder == shortcutRecorder || aRecorder == snippetsShortcutRecorder)
//	{
////		BOOL isTaken = NO;
//		
//		NSArray *allKeys = [[PTHotKeyCenter sharedCenter] allHotKeys];
//		for (PTHotKey *hotKey in allKeys) {
//			PTKeyCombo *keyCombo = [hotKey keyCombo];
//			NSInteger registerdkeyCode = [keyCombo keyCode];
//			NSInteger registerdFlags = [aRecorder carbonToCocoaFlags:[keyCombo modifiers]];
//			
//			NSLog(@"registerdkeyCode: %d, registerdFlags: %d - code: %d, flags: %d", registerdkeyCode, registerdFlags, keyCode, flags);
//			
//			if (registerdkeyCode == keyCode && registerdkeyCode == flags) {
//				*aReason = @"reason";	// need to change!!!
//				return YES;
//			}
//		}
//		
////		KeyCombo kc = [delegateDisallowRecorder keyCombo];
////		
////		if (kc.code == keyCode && kc.flags == flags) {
////			isTaken = YES;
////		}
////		
////		*aReason = @"reason";	// need to change!!!
////		
////		return isTaken;
//	}
//	
//	return NO;
//}

- (void)shortcutRecorder:(SRRecorderControl *)aRecorder keyComboDidChange:(PTKeyCombo *)newKeyCombo
{
//	NSLog(@"aRecorder: %@", aRecorder);
	
	if ([shortcutRecorders containsObject:aRecorder])
	{
//		NSLog(@"keyComboDidChange: flags: %d, code: %d", newKeyCombo.code, newKeyCombo.flags);
		[self _changeHotKeyByShortcutRecorder:aRecorder withKeyCombo:newKeyCombo];
	}
}

#pragma mark - NSTableView -

- (void)tableView:(NSTableView *)aTableView willDisplayCell:(id)aCell forTableColumn:(NSTableColumn *)aTableColumn row:(NSInteger)rowIndex
{	
//	NSLog(@"cell: %d, %@", rowIndex, [aCell image]);
	
	if ([[aTableColumn identifier] isEqualToString:kImageAndTextCellColumn]) {
		// we are displaying the single and only column
		if ([aCell isKindOfClass:[ImageAndTextCell class]]) {
			NSWorkspace *workSpace = [NSWorkspace sharedWorkspace];
			
			NSDictionary *appInfo = [excludeList objectAtIndex:rowIndex];			
			if (appInfo == nil) {
				return;
			}
			
			NSString *identifier = [appInfo objectForKey:kCMBundleIdentifierKey];
			if (identifier == nil) {
				return;
			}
			
			NSString *path = [workSpace absolutePathForAppBundleWithIdentifier:identifier];
			NSImage *icon = nil;
			
			if (path) {
				icon = [workSpace iconForFile:path];
			}
						
			if (icon == nil) {
				icon = [workSpace iconForFileType:NSFileTypeForHFSTypeCode(kGenericApplicationIcon)];
			}
						
			if (icon == nil) {
				return;
			}
			
			[icon setSize:NSMakeSize(16, 16)];
			[(ImageAndTextCell *)aCell setImage:icon];		// set the cell's image
		}
	}
}
	
#pragma mark -
#pragma mark Public

#pragma mark - Exclude List -

- (IBAction)openExcludeOptions:(id)sender
{	
	if (excludeList == nil) {
		[self setExcludeList:[[NSUserDefaults standardUserDefaults] objectForKey:CMPrefExcludeAppsKey]];
	}
	
	[self _prepareAddToExcludeListMenu];
		
	[NSApp beginSheet:excludeListPanel
	   modalForWindow:self.window
		modalDelegate:self
	   didEndSelector:@selector( excludeListPanelDidEnd:returnCode:contextInfo: )
		  contextInfo:nil];	
}

- (IBAction)doneExcludeListPanel:(id)sender
{
	[NSApp endSheet:excludeListPanel returnCode:NSOKButton];
	
	[[NSUserDefaults standardUserDefaults] setObject:self.excludeList
											  forKey:CMPrefExcludeAppsKey];
}

- (IBAction)cancelExcludeListPanel:(id)sender
{
	[NSApp endSheet:excludeListPanel returnCode:NSCancelButton];
	[self setExcludeList:[[NSUserDefaults standardUserDefaults] objectForKey:CMPrefExcludeAppsKey]];
}

- (void)excludeListPanelDidEnd:(NSPanel *)sheet returnCode:(NSInteger)returnCode contextInfo:(void *)contextInfo
{
	[sheet orderOut:self];
}

- (void)addToExcludeList:(id)sender
{
	NSOpenPanel *openPanel = [NSOpenPanel openPanel];
	[openPanel setAllowedFileTypes:[NSArray arrayWithObject:@"app"]];
	[openPanel setAllowsMultipleSelection:YES];
	[openPanel setResolvesAliases:YES];
	[openPanel setPrompt:NSLocalizedString(@"Add", nil)];

	NSArray *directories = NSSearchPathForDirectoriesInDomains(NSApplicationDirectory, NSLocalDomainMask, YES);
	NSString *basePath = (0 < [directories count]) ? [directories objectAtIndex:0] : NSHomeDirectory();
	
	[openPanel beginSheetForDirectory:basePath
								 file:nil
					   modalForWindow:excludeListPanel
						modalDelegate:self
					   didEndSelector:@selector( addToExcludeListPanelDidEnd:returnCode:contextInfo: )
						  contextInfo:NULL];
}

- (void)addToExcludeListPanelDidEnd:(NSOpenPanel *)sheet returnCode:(NSInteger)returnCode contextInfo:(void *)contextInfo
{
//	NSLog(@"addToExcludeListPanelDidEnd: %d", returnCode);
	
	if (returnCode == NSOKButton) {		
		NSDictionary *appInfo;
		
		NSBundle *bundle;
		NSDictionary *infoDict;
		BOOL isSnowLeopardOrLater = ([NSBundle respondsToSelector:@selector( bundleWithURL: )]) 
		? YES : NO;
		
		for (NSURL *url in [sheet URLs]) {			
			if (isSnowLeopardOrLater) {
				/* Mac OS X 10.6 or lator */
				bundle = [NSBundle bundleWithURL:url];
			}
			else {
				bundle = [NSBundle bundleWithPath:[url path]];
			}
			
			infoDict = [bundle infoDictionary];
			NSString *bundleIdentifier = [infoDict objectForKey:(NSString *)kCFBundleIdentifierKey];
//			NSLog(@"bundleIdentifier: %@", bundleIdentifier);
			if (bundleIdentifier == nil) {
				continue;
			}
			
			NSString *appName = [infoDict objectForKey:(NSString *)kCFBundleNameKey];
//			NSLog(@"appName: %@", appName);
			if (appName == nil) {
				appName = [infoDict objectForKey:(NSString *)kCFBundleExecutableKey];
				if (appName == nil) {
					continue;
				}
			}
			
			appInfo = [[NSDictionary alloc] initWithObjectsAndKeys:
					   bundleIdentifier, kCMBundleIdentifierKey,
					   appName, kCMNameKey,
					   nil];			
			[self _addAppInfoToExcludeList:appInfo];
			[appInfo release], appInfo = nil;
		}				
	}
	
	[sheet orderOut:self];
}

#pragma mark - NSSavePanel -

- (IBAction)exportHistory:(id)sender
{
	BOOL singleFile = [[NSUserDefaults standardUserDefaults]
					   boolForKey:CMPrefExportHistoryAsSingleFileKey];
	if (singleFile) {
		[self _exportHistoryAsSingleFile];
	}
	else {
		[self _exportHistoryAsMultipleFiles];
	}
}

- (void)savePanelDidEnd:(NSSavePanel *)sheet returnCode:(NSInteger)returnCode contextInfo:(void *)contextInfo
{
	BOOL singleFile = [[NSUserDefaults standardUserDefaults]
					   boolForKey:CMPrefExportHistoryAsSingleFileKey];
	
	[self _exportHistoryAsSingleFile:singleFile sheet:sheet returnCode:returnCode];
}

#pragma mark - DBPrefsWindowController -

/* Override */
- (IBAction)showWindow:(id)sender 
{
//	NSLog(@"showWindow");
	
	[super showWindow:sender];
	[NSApp activateIgnoringOtherApps:YES];
	[[self window] makeKeyAndOrderFront:self];
	
//	/* Check whether login item or not */	
//	[NSThread detachNewThreadSelector:@selector( _checkLoginItemState )
//							 toTarget:self
//						   withObject:nil];
}

- (void)setupToolbar
{	
	NSImage *image;
	
	if (image = [NSImage imageNamed:NSImageNamePreferencesGeneral]) {
		[self addView:generalPrefsView label:NSLocalizedString(@"General", nil) image:image];
	}
	
	if (image = [NSImage imageNamed:@"Menu"]) {
		[self addView:menuPrefsView label:NSLocalizedString(@"Menu", nil) image:image];		
	}
	
	image = [[NSWorkspace sharedWorkspace] iconForFileType:NSFileTypeForHFSTypeCode(kGenericApplicationIcon)];
	if (image) {
		[image setSize:NSMakeSize(32, 32)];	
		[self addView:iconPrefsView label:NSLocalizedString(@"Type", nil) image:image];		
	}
	
	if (image = [NSImage imageNamed:@"ActionIconLarge"]) {
		[self addView:actionPrefsView label:NSLocalizedString(@"Action", nil) image:image];
	}
	
	if (image = [NSImage imageNamed:@"PTKeyboardIcon"]) {
		[self addView:shortcutPrefsView label:NSLocalizedString(@"Shortcuts", nil) image:image];
	}
	
	if (image = [NSImage imageNamed:@"SparkleIcon"]) {
		[self addView:updatesPrefsView label:NSLocalizedString(@"Updates", nil) image:image];
	}
	
	[self setCrossFade:YES];
	[self setShiftSlowsAnimation:NO];
}

#pragma mark -
#pragma mark Private

- (void)_prepareHotKeys
{
    
    
	NSMutableArray *recorders = [NSMutableArray arrayWithObjects:
								 shortcutRecorder, historyShortCutRecorder, snippetsShortcutRecorder,
								 nil];
	[self setShortcutRecorders:recorders];
	
	NSDictionary *hotKeyMap = [CMUtilities hotKeyMap];
	NSDictionary *hotKeyCombos = [[NSUserDefaults standardUserDefaults] objectForKey:CMPrefHotKeysKey];
	for (NSString *identifier in hotKeyCombos) {
//		NSLog(@"identifier: %@", identifier);
		id keyComboPlist = [hotKeyCombos objectForKey:identifier];
//		NSLog(@"keyComboPlist: %@", keyComboPlist);
		

        // new
        //----------------------        
        // create a PTKeyCombo instance
        PTKeyCombo *combo = [[PTKeyCombo alloc] initWithKeyCode:[[keyComboPlist objectForKey:@"keyCode"] unsignedIntValue] modifiers:[[keyComboPlist objectForKey:@"modifiers"] unsignedIntValue]];

        // old
        //----------------------
        // KeyCombo keyCombo;
        // keyCombo.code = [[keyComboPlist objectForKey:@"keyCode"] unsignedIntValue];
        // keyCombo.flags = [shortcutRecorder carbonToCocoaFlags:[[keyComboPlist objectForKey:@"modifiers"] unsignedIntValue]];

		
		NSUInteger index = [[[hotKeyMap objectForKey:identifier] objectForKey:kIndex] 
							unsignedIntegerValue];		
		SRRecorderControl *recorder = [recorders objectAtIndex:index];

        
        
		//[recorder setKeyCombo: combo];		
		// [recorder setAnimates:YES];
	}
}

- (void)_changeHotKeyByShortcutRecorder:(SRRecorderControl *)aRecorder withKeyCombo:(PTKeyCombo *)keyCombo
{
//	NSLog(@"_changeHotKeyByShortcutRecorder: %@", aRecorder);

	PTKeyCombo *newKeyCombo = [PTKeyCombo keyComboWithKeyCode:keyCombo.keyCode
													modifiers:[aRecorder cocoaToCarbonFlags:keyCombo.modifiers]];
	
	NSString *identifier = nil;
	if (aRecorder == shortcutRecorder) {
		identifier = kClipMenuIdentifier;
	}
	else if (aRecorder == historyShortCutRecorder) {
		identifier = kHistoryMenuIdentifier;
	}
	else if (aRecorder == snippetsShortcutRecorder) {
		identifier = kSnippetsMenuIdentifier;
	}
	else {
		NSAssert(NO, @"Couldn't find the identifier of the recorder");
	}
//	NSLog(@"identifier: %@", identifier);
	
	PTHotKeyCenter *hotKeyCenter = [PTHotKeyCenter sharedCenter];
	PTHotKey *oldHotKey = [hotKeyCenter hotKeyWithIdentifier:identifier];
	[hotKeyCenter unregisterHotKey:oldHotKey];
	
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	NSMutableDictionary *hotKeyPrefs = [[[defaults objectForKey:CMPrefHotKeysKey] mutableCopy]
										autorelease];
	[hotKeyPrefs setObject:[newKeyCombo plistRepresentation] forKey:identifier];	
	[defaults setObject:hotKeyPrefs forKey:CMPrefHotKeysKey];
}

- (void)_prepareFontSizePopUpMenuItems
{
	NSMutableArray *items = [NSMutableArray array];
	for (NSInteger i = 9; i <= 24; i++) {
		[items addObject:[NSNumber numberWithInt:i]];
	}
	[items addObjectsFromArray:[NSArray arrayWithObjects:@"36", @"48", @"64", @"72", @"96", nil]];
	
	[self setValue:items forKey:@"fontSizePopUpMenuItems"];
}

- (NSArray *)_actionsFromNodes:(NSArray *)nodes
{
	NSMutableArray *results = [NSMutableArray array];
	
	for (ActionNode *node in nodes) {
		if ([node isLeaf]) {
			NSString *title = [node nodeTitle];
			NSDictionary *action = [node action];
			if (action && title) {
				NSDictionary *dict = [NSDictionary dictionaryWithObjectsAndKeys:
									  title, kTitle,
									  action, kBehavior,
									  nil];
				[results addObject:dict];
			}
		}
		else {
			NSArray *children = [self _actionsFromNodes:[node children]];			
			[results addObjectsFromArray:children];
		}
	}
	
	if ([results count] < 1) {
		return nil;
	}
	
	return results;
}

- (void)_prepareModifiersPopUpMenuItems
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	
	NSMutableArray *items = [NSMutableArray arrayWithObjects:
							 [NSDictionary dictionaryWithObjectsAndKeys:
							  NSLocalizedString(@"None", nil), kTitle,
							  kEmptyString, kBehavior,
							  nil],
							 [NSDictionary dictionaryWithObjectsAndKeys:
							  NSLocalizedString(@"Pop up Action Menu", nil), kTitle,
							  kPopUpActionMenu, kBehavior,
							  nil],
							 nil];
	
	[items addObject:separatorItemDict()];

	NSArray *builtinNodes = [actionNodeController builtinNodes];
	if ([self _actionsFromNodes:builtinNodes]) {
		[items addObjectsFromArray:[self _actionsFromNodes:builtinNodes]];
	}
	
	[items addObject:separatorItemDict()];
	
	NSArray *bundledNodes = [actionNodeController bundledNodes];
	if ([self _actionsFromNodes:bundledNodes]) {
		[items addObjectsFromArray:[self _actionsFromNodes:bundledNodes]];
	}
	
	[items addObject:separatorItemDict()];

	NSArray *usersNodes = [actionNodeController usersNodes];
	if ([self _actionsFromNodes:usersNodes]) {
		[items addObjectsFromArray:[self _actionsFromNodes:usersNodes]];
	}
	
	[self setModifiersPopUpMenuItems:items];
	
	[self _buildModifiersPopUpMenuItems];
	
	[pool drain];
}

- (void)_buildModifiersPopUpMenuItems
{
	NSMenu *menu = [[NSMenu allocWithZone:[NSMenu menuZone]] initWithTitle:@"modifiersPopUpMenu"];
	
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	NSString *controlClickBehavior = [defaults objectForKey:CMPrefContorlClickBehaviorKey];
	NSString *shiftClickBehavior = [defaults objectForKey:CMPrefShiftClickBehaviorKey];
	NSString *optionClickBehavior = [defaults objectForKey:CMPrefOptionClickBehaviorKey];
	NSString *commandClickBehavior = [defaults objectForKey:CMPrefCommandClickBehaviorKey];
	
//	NSLog(@"controlKeyBehavior: %@", controlClickBehavior);
	
	NSInteger indexOfTargetForControlKey = 0;
	NSInteger indexOfTargetForShiftKey = 0;
	NSInteger indexOfTargetForOptionKey = 0;
	NSInteger indexOfTargetForCommandKey = 0;
	
	NSUInteger i = 0;
	for (NSDictionary *item in modifiersPopUpMenuItems) {
		NSMenuItem *menuItem;
		NSString *title = [item objectForKey:kTitle];
		if ([title isEqualToString:@"-"]) {
			menuItem = [NSMenuItem separatorItem];
		}
		else {
			menuItem = [[[NSMenuItem allocWithZone:[NSMenu menuZone]] 
						 initWithTitle:title action:NULL keyEquivalent:kEmptyString] autorelease];
		}

		id behavior = [item objectForKey:kBehavior];
		
		if (![behavior isEqualTo:[NSNull null]]) {
			if (sameBehaviors(behavior, controlClickBehavior)) {
				indexOfTargetForControlKey = i;
			}
			if (sameBehaviors(behavior, shiftClickBehavior)) {
				indexOfTargetForShiftKey = i;
			}
			if (sameBehaviors(behavior, optionClickBehavior)) {
				indexOfTargetForOptionKey = i;
			}
			if (sameBehaviors(behavior, commandClickBehavior)) {
				indexOfTargetForCommandKey = i;
			}
			
			[menuItem setRepresentedObject:behavior];
		}

		[menu addItem:menuItem];
		i++;
	}
			
	[controlPopUpButton setMenu:menu];
	[controlPopUpButton selectItemAtIndex:indexOfTargetForControlKey];
	
	[shiftPopUpButton setMenu:[[menu copy] autorelease]];
	[shiftPopUpButton selectItemAtIndex:indexOfTargetForShiftKey];
	[optionPopUpButton setMenu:[[menu copy] autorelease]];
	[optionPopUpButton selectItemAtIndex:indexOfTargetForOptionKey];
	[commandPopUpButton setMenu:[[menu copy] autorelease]];
	[commandPopUpButton selectItemAtIndex:indexOfTargetForCommandKey];

	[menu release], menu = nil;
}

//- (void)_checkLoginItemState
//{
//	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
//	
//	NSString *appPath = [[NSBundle mainBundle] bundlePath];
//	BOOL isInLoginItems = [NMLoginItems pathInLoginItems:appPath];
//	[self performSelectorOnMainThread:@selector( _changeLoginItemWithNumber: )
//						   withObject:[NSNumber numberWithBool:isInLoginItems]
//						waitUntilDone:NO];
//	
//	[pool drain];
//}
//
//- (void)_changeLoginItemWithNumber:(NSNumber *)number
//{
//	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
//	BOOL currentState = [defaults boolForKey:CMPrefLoginItemKey];
//	BOOL state = [number boolValue];
//	
//	if (currentState != state) {
//		[defaults setBool:state forKey:CMPrefLoginItemKey];
//	}
//}

#pragma mark - Exclude List -

- (void)_prepareAddToExcludeListMenu
{		
	NSWorkspace *workSpace = [NSWorkspace sharedWorkspace];
	NSArray *launchedApps = [workSpace launchedApplications];
	
	NSMenu *popUpMenu = [[[NSMenu allocWithZone:[NSMenu menuZone]] init] autorelease];
	NSMenuItem *menuItem;
	NSDictionary *appInfo;
	
	for (NSDictionary *app in launchedApps) {
		NSString *appName = [app objectForKey:@"NSApplicationName"];
		if (appName == nil) {
			continue;
		}
		
		NSString *bundleIdentifier = [app objectForKey:@"NSApplicationBundleIdentifier"];
		if (bundleIdentifier == nil) {
			continue;
		}
		
		NSString *appPath = [app objectForKey:@"NSApplicationPath"];
		if (appPath == nil) {
			return;
		}
		
		appInfo = [[NSDictionary alloc] initWithObjectsAndKeys:
				   bundleIdentifier, kCMBundleIdentifierKey,
				   appName, kCMNameKey,
				   nil];
		
		/* Make menuItem */
		menuItem = [[NSMenuItem allocWithZone:[NSMenu menuZone]] 
					initWithTitle:appName
					action:@selector( _addSelectedAppToExcludeList: )
					keyEquivalent:kEmptyString];
		[menuItem setTarget:self];
		[menuItem setRepresentedObject:appInfo];
		[appInfo release], appInfo = nil;
		
		/* Icon */
		NSImage *icon = [workSpace iconForFile:appPath];
		
		if (icon == nil) {
			icon = [workSpace iconForFileType:NSFileTypeForHFSTypeCode(kGenericApplicationIcon)];
		}
		
		if (icon) {
			[icon setSize:NSMakeSize(16, 16)];
			[menuItem setImage:icon];
		}
		
		[popUpMenu addItem:menuItem];
		[menuItem release], menuItem = nil;
	}
	
	[popUpMenu addItem:[NSMenuItem separatorItem]];
	
	menuItem = [[NSMenuItem allocWithZone:[NSMenu menuZone]] 
				initWithTitle:NSLocalizedString(@"Other...", nil)
				action:@selector( addToExcludeList: )
				keyEquivalent:kEmptyString];
	[menuItem setTarget:self];
	[popUpMenu addItem:menuItem];
	[menuItem release], menuItem = nil;
	
	[addExcludeListButtion setMenu:popUpMenu];
}

- (void)_addAppInfoToExcludeList:(NSDictionary *)appInfo
{
	NSArray *excludedAppIDs = [[excludeListController arrangedObjects] 
							   valueForKey:kCMBundleIdentifierKey];
	NSString *newID = [appInfo objectForKey:kCMBundleIdentifierKey];
	if (newID == nil) {
		return;
	}
	
	if ([excludedAppIDs containsObject:newID]) {
		return;
	}
	
	[excludeListController addObject:appInfo];
}

- (void)_addSelectedAppToExcludeList:(id)sender
{
	NSDictionary *appInfo = [sender representedObject];		
	[self _addAppInfoToExcludeList:appInfo];
}

#pragma mark - Export History -

- (void)_exportHistoryAsSingleFile
{
	NSString *filename = @"clipboard_history.txt";
	
	NSSavePanel *savePanel = [NSSavePanel savePanel];
	[savePanel setCanCreateDirectories:YES];
	[savePanel setAllowedFileTypes:[NSArray arrayWithObject:@"txt"]];
	
	/* Blocks causes crash in Leopard */
//	if ([savePanel respondsToSelector:@selector( beginSheetModalForWindow:completionHandler: )]) {
//		/* Mac OS X 10.6 and lator */
//		[savePanel setNameFieldStringValue:filename]; 
//		[savePanel beginSheetModalForWindow:[self window] completionHandler:^ (NSInteger returnCode) {
//			[self _exportHistoryAsSingleFile:YES sheet:savePanel returnCode:returnCode];
//		}];
//	}
//	else {
		/* Mac OS X 10.5 and earlier */
		[savePanel beginSheetForDirectory:nil
									 file:filename
						   modalForWindow:[self window]
							modalDelegate:self
						   didEndSelector:@selector( savePanelDidEnd:returnCode:contextInfo: )
							  contextInfo:NULL];
//	}
}

- (void)_exportHistoryAsMultipleFiles
{
	NSOpenPanel *openPanel = [NSOpenPanel openPanel];
	[openPanel setCanChooseDirectories:YES];
	[openPanel setCanChooseFiles:NO];
	[openPanel setCanCreateDirectories:YES];
	[openPanel setPrompt:NSLocalizedString(@"Select", nil)];
	
	/* Blocks causes crash in Leopard */
//	if ([openPanel respondsToSelector:@selector( beginSheetModalForWindow:completionHandler: )]) {
//		/* Mac OS X 10.6 and lator */
//		[openPanel beginSheetModalForWindow:[self window] completionHandler:^ (NSInteger returnCode) {
//			[self _exportHistoryAsSingleFile:NO sheet:openPanel returnCode:returnCode];
//		}];
//	}
//	else {
		/* Mac OS X 10.5 and earlier */
		[openPanel beginSheetForDirectory:nil
									 file:nil
						   modalForWindow:[self window]
							modalDelegate:self
						   didEndSelector:@selector( savePanelDidEnd:returnCode:contextInfo: )
							  contextInfo:NULL];
//	}
}

- (void)_exportHistoryAsSingleFile:(BOOL)singleFile sheet:(NSSavePanel *)sheet returnCode:(NSInteger)returnCode
{
	if (returnCode != NSOKButton) {
		return;
	}
	
	NSString *path = [[sheet URL] path];
	BOOL success;
	
	if (singleFile) {
		success = [[ClipsController sharedInstance] exportHistoryStringsAsSingleFile:path];
	}
	else {
		success = [[ClipsController sharedInstance] exportHistoryStringsAsMultipleFiles:path];
	}
	
	if (!success) {
		NSLog(@"Failed to export history");
		CMRunAlertPanel(NSLocalizedString(@"Error", nil), 
						NSLocalizedString(@"Failed to export history", nil), 
						NSLocalizedString(@"OK", nil), 
						nil, 
						nil);
		return;
	}
}

@end
