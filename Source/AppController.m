#import "AppController.h"
#import "constants.h"
#import "CMUtilities.h"
#import "PrefsWindowController.h"
#import "MenuController.h"
#import "ActionController.h"
#import "ActionNode.h"
#import "ClipsController.h"
#import "Clip.h"
#import "SnippetEditorController.h"
#import "NMLoginItems.h"

#import "PTHotKey.h"
#import "PTHotKeyCenter.h"
#import <Sparkle/Sparkle.h>


@interface AppController ()
//- (BOOL)_moveCurrentProcessToForeground;
//- (BOOL)_movePreviousFrontProcessToForeground;

- (void)_toggleCheckPreReleaseUpdates:(BOOL)flag;

- (void)_promptToAddLoginItems;
- (void)_toggleAddingToLoginItems:(BOOL)flag;
- (void)_toggleLoginItemState;

- (void)_registerHotKeys;
- (void)_unregisterHotKeys;

- (BOOL)_invokeModifiedClickWithBehavior:(id)behavior andSender:(id)sender;

- (BOOL)_applyActionToTarget:(id)sender;
- (void)_invokeAction:(NSDictionary *)action toIndex:(NSInteger)index;
- (void)_invokeAction:(NSDictionary *)action;
- (void)_invokeBuiltinAction:(NSDictionary *)action toTarget:(id)target;
- (void)_invokeJavaScriptAction:(NSDictionary *)action atIndex:(NSInteger)index;

- (void)_handlePreferencePanelWillClose:(NSNotification *)aNotification;
@end


#pragma mark -
@implementation AppController

//@synthesize queue;

NSDictionary *_storeTypesDictionary()
{
	NSMutableArray *storeTypeValues = [NSMutableArray array];
	NSArray *availableTypeNames = [Clip availableTypeNames];
	
	for (NSString *name in availableTypeNames) {
		[storeTypeValues addObject:[NSNumber numberWithBool:YES]];
	}
	
	return [NSDictionary dictionaryWithObjects:storeTypeValues forKeys:availableTypeNames];
}

#pragma mark -

+ (NSDictionary *)_defaultHotKeyCombos
{
	NSMutableDictionary *hotKeyCombos = [NSMutableDictionary dictionary];
	NSMutableArray *newCombos = [NSMutableArray array];
	
	/* 
	 [code]
	 9 = 'v', 
	 11 = 'b',
	 
	 [modifiers]
	 768 = 'command' + 'shift'
	 2304 = 'command' + 'option'
	 4352 = 'command' + 'control'
	 */
	
	PTKeyCombo *keyCombo;
	
	/* Main Menu key combo */
	keyCombo = [PTKeyCombo keyComboWithKeyCode:9 modifiers:768];
	[newCombos addObject:keyCombo];
	
	/* History Menu key combo */
	keyCombo = [PTKeyCombo keyComboWithKeyCode:9 modifiers:4352];
	[newCombos addObject:keyCombo];
	
	/* Snippets Menu key combo */
	keyCombo = [PTKeyCombo keyComboWithKeyCode:11 modifiers:768];
	[newCombos addObject:keyCombo];

	NSDictionary *hotKeyMap = [CMUtilities hotKeyMap];
	for (NSString *identifier in hotKeyMap) {
		NSUInteger index = [[[hotKeyMap objectForKey:identifier] objectForKey:kIndex]
							unsignedIntegerValue];
		PTKeyCombo *keyCombo = [newCombos objectAtIndex:index];
		[hotKeyCombos setObject:[keyCombo plistRepresentation] forKey:identifier];
	}
	
	return hotKeyCombos;
}

+ (NSMutableArray *)_defaultExcludeList
{
	NSMutableDictionary *anAppInfo = [NSMutableDictionary dictionaryWithObjectsAndKeys:
									  @"org.openoffice.script", kCMBundleIdentifierKey,
									  @"OpenOffice.org", kCMNameKey,
									  nil];
	
//	NSMutableDictionary *anAppInfo2 = [NSMutableDictionary dictionaryWithObjectsAndKeys:
//									   @"zzz.com.apple.Safari", kCMBundleIdentifierKey,
//									   @"zzzSafari", kCMNameKey,
//									   nil];
//	NSMutableArray *excludeList = [NSMutableArray arrayWithObjects:anAppInfo, anAppInfo2, nil];
	
	NSMutableArray *excludeList = [NSMutableArray arrayWithObjects:anAppInfo, nil];
	return excludeList;
}

#pragma mark Initialize

+ (void)initialize
{	
	/* Default Values */
	NSMutableDictionary *defaultValues = [NSMutableDictionary dictionary];

	/* Hot Keys */	
	[defaultValues setObject:[self _defaultHotKeyCombos] forKey:CMPrefHotKeysKey];
	
	/* General */
	[defaultValues setObject:[NSNumber numberWithBool:NO] forKey:CMPrefLoginItemKey];
	[defaultValues setObject:[NSNumber numberWithBool:NO] forKey:CMPrefSuppressAlertForLoginItemKey];
	[defaultValues setObject:[NSNumber numberWithBool:YES] forKey:CMPrefInputPasteCommandKey];
	[defaultValues setObject:[NSNumber numberWithBool:YES] forKey:CMPrefReorderClipsAfterPasting];
	[defaultValues setObject:[NSNumber numberWithUnsignedInteger:20] forKey:CMPrefMaxHistorySizeKey];
	[defaultValues setObject:[NSNumber numberWithUnsignedInteger:1800] forKey:CMPrefAutosaveDelayKey];
	[defaultValues setObject:[NSNumber numberWithBool:YES] forKey:CMPrefSaveHistoryOnQuitKey];
	[defaultValues setObject:[NSNumber numberWithBool:YES] forKey:CMPrefExportHistoryAsSingleFileKey];
	[defaultValues setObject:[NSNumber numberWithUnsignedInteger:1] forKey:CMPrefTagOfSeparatorForExportHistoryToFileKey];
	[defaultValues setObject:[NSNumber numberWithUnsignedInteger:1] forKey:CMPrefShowStatusItemKey];
	[defaultValues setObject:[NSNumber numberWithFloat:0.75] forKey:CMPrefTimeIntervalKey];
	[defaultValues setObject:_storeTypesDictionary() forKey:CMPrefStoreTypesKey];
	[defaultValues setObject:[self _defaultExcludeList] forKey:CMPrefExcludeAppsKey];
	/* Menu */
	[defaultValues setObject:[NSNumber numberWithUnsignedInteger:20] forKey:CMPrefMaxMenuItemTitleLengthKey];
	[defaultValues setObject:[NSNumber numberWithUnsignedInteger:0] forKey:CMPrefNumberOfItemsPlaceInlineKey];
	[defaultValues setObject:[NSNumber numberWithUnsignedInteger:10] forKey:CMPrefNumberOfItemsPlaceInsideFolderKey];
	[defaultValues setObject:[NSNumber numberWithBool:YES] forKey:CMPrefMenuItemsAreMarkedWithNumbersKey];
	[defaultValues setObject:[NSNumber numberWithBool:NO] forKey:CMPrefMenuItemsTitleStartWithZeroKey];
	[defaultValues setObject:[NSNumber numberWithBool:NO] forKey:CMPrefAddNumericKeyEquivalentsKey];
	[defaultValues setObject:[NSNumber numberWithBool:YES] forKey:CMPrefShowLabelsInMenuKey];
	[defaultValues setObject:[NSNumber numberWithBool:YES] forKey:CMPrefAddClearHistoryMenuItemKey];
	[defaultValues setObject:[NSNumber numberWithBool:YES] forKey:CMPrefShowAlertBeforeClearHistoryKey];
	[defaultValues setObject:[NSNumber numberWithBool:YES] forKey:CMPrefShowToolTipOnMenuItemKey];
	[defaultValues setObject:[NSNumber numberWithUnsignedInteger:200] forKey:CMPrefMaxLengthOfToolTipKey];
	[defaultValues setObject:[NSNumber numberWithBool:NO] forKey:CMPrefChangeFontSizeKey];
	[defaultValues setObject:[NSNumber numberWithInteger:0] forKey:CMPrefHowToChangeFontSizeKey];
	[defaultValues setObject:[NSNumber numberWithUnsignedInteger:14] forKey:CMPrefSelectedFontSizeKey];
	[defaultValues setObject:[NSNumber numberWithBool:YES] forKey:CMPrefShowImageInTheMenuKey];
	[defaultValues setObject:[NSNumber numberWithUnsignedInteger:100] forKey:CMPrefThumbnailWidthKey];
	[defaultValues setObject:[NSNumber numberWithUnsignedInteger:32] forKey:CMPrefThumbnailHeightKey];
	[defaultValues setObject:[NSNumber numberWithBool:YES] forKey:CMPrefShowIconInTheMenuKey];
	/* - Menu Icon - */
	[defaultValues setObject:[NSNumber numberWithUnsignedInteger:16] forKey:CMPrefMenuIconSizeKey];
	[defaultValues setObject:[NSNumber numberWithInteger:1] forKey:CMPrefMenuIconOfFileTypeTagForStringKey];
	[defaultValues setObject:@"TEXT" forKey:CMPrefMenuIconOfFileTypeForStringKey];	
	[defaultValues setObject:[NSNumber numberWithInteger:0] forKey:CMPrefMenuIconOfFileTypeTagForRTFKey];
	[defaultValues setObject:@"rtf" forKey:CMPrefMenuIconOfFileTypeForRTFKey];
	[defaultValues setObject:[NSNumber numberWithInteger:0] forKey:CMPrefMenuIconOfFileTypeTagForRTFDKey];
	[defaultValues setObject:@"rtfd" forKey:CMPrefMenuIconOfFileTypeForRTFDKey];
	[defaultValues setObject:[NSNumber numberWithInteger:0] forKey:CMPrefMenuIconOfFileTypeTagForPDFKey];
	[defaultValues setObject:@"pdf" forKey:CMPrefMenuIconOfFileTypeForPDFKey];
	[defaultValues setObject:[NSNumber numberWithInteger:1] forKey:CMPrefMenuIconOfFileTypeTagForFilenamesKey];
	[defaultValues setObject:@"clpu" forKey:CMPrefMenuIconOfFileTypeForFilenamesKey];	// need to change?
	[defaultValues setObject:[NSNumber numberWithInteger:1] forKey:CMPrefMenuIconOfFileTypeTagForURLKey];
	[defaultValues setObject:@"gurl" forKey:CMPrefMenuIconOfFileTypeForURLKey];	
	[defaultValues setObject:[NSNumber numberWithInteger:0] forKey:CMPrefMenuIconOfFileTypeTagForTIFFKey];
	[defaultValues setObject:@"tiff" forKey:CMPrefMenuIconOfFileTypeForTIFFKey];
	[defaultValues setObject:[NSNumber numberWithInteger:0] forKey:CMPrefMenuIconOfFileTypeTagForPICTKey];
	[defaultValues setObject:@"pict" forKey:CMPrefMenuIconOfFileTypeForPICTKey];
	/* Actions */
	NSMutableArray *defaultActions = [ActionController defaultActions];
	[defaultValues setObject:defaultActions forKey:@"actions"];
	[defaultValues setObject:[NSNumber numberWithBool:YES] forKey:CMPrefEnableActionKey];
	[defaultValues setObject:[NSNumber numberWithBool:NO] forKey:CMPrefInvokeActionImmediatelyKey];
	[defaultValues setObject:kPopUpActionMenu forKey:CMPrefContorlClickBehaviorKey];
	/* Snippet */
	[defaultValues setObject:[NSNumber numberWithInteger:CMPositionOfSnippetsBelowClips] forKey:CMPrefPositionOfSnippetsKey];
	/* Updates */
	[defaultValues setObject:[NSNumber numberWithBool:YES] forKey:CMEnableAutomaticCheckKey];
	[defaultValues setObject:[NSNumber numberWithBool:NO] forKey:CMEnableAutomaticCheckPreReleaseKey];
	[defaultValues setObject:[NSNumber numberWithInteger:86400] forKey:CMUpdateCheckIntervalKey]; // daily
	
	[[NSUserDefaults standardUserDefaults] registerDefaults:defaultValues];
}

//- (id)init
//{
//	self = [super init];
//	if (self) {		
//		queue = [[NSOperationQueue alloc] init];
//	}
//	return self;
//}

- (void)dealloc
{	
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	
	/* KVO */
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	[defaults removeObserver:self 
				  forKeyPath:CMPrefHotKeysKey];
//	[defaults removeObserver:self
//				  forKeyPath:CMPrefLoginItemKey];
	[defaults removeObserver:self
				  forKeyPath:CMEnableAutomaticCheckPreReleaseKey];
	
	[[ClipsController sharedInstance] removeObserver:self
										  forKeyPath:@"clips"];
	
//	[queue release], queue = nil;
	
	[super dealloc];
}

- (void)awakeFromNib
{	
//	NSLog(@"awakeFromNib");
	
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	
	if ([defaults boolForKey:CMPrefShowStatusItemKey]) {
		[[MenuController sharedInstance] createStatusItem];
	}
	
	/* KVO */
	[defaults addObserver:self
			   forKeyPath:CMPrefHotKeysKey
				  options:NSKeyValueObservingOptionNew
				  context:nil];
//	[defaults addObserver:self
//			   forKeyPath:CMPrefLoginItemKey
//				  options:(NSKeyValueObservingOptionNew | NSKeyValueObservingOptionOld)
//				  context:nil];
	
	[[ClipsController sharedInstance] addObserver:self
									   forKeyPath:@"clips"
										  options:NSKeyValueObservingOptionNew
										  context:nil];
	
	/* Notification */
	NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
	[nc addObserver:self
		   selector:@selector( _handlePreferencePanelWillClose: )
			   name:CMPreferencePanelWillCloseNotification
			 object:nil];
}


#pragma mark -
#pragma mark KVO

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
//	NSLog(@"observeValueForKeyPath: %@, change: %@", keyPath, change);
	
	if ([keyPath isEqualToString:@"clips"]) {
		[[MenuController sharedInstance] updateStatusMenu];
	}
	else if ([keyPath isEqualToString:CMPrefHotKeysKey]) {
		[self _registerHotKeys];
	}
//	else if ([keyPath isEqualToString:CMPrefLoginItemKey]) {
//		BOOL old = [[change objectForKey:kOldKey] boolValue];
//		BOOL new = [[change objectForKey:kNewKey] boolValue];
//		if (old == new) {
//			return;
//		}
//		[self _toggleAddingToLoginItems:new];	
//	}
	else if ([keyPath isEqualToString:CMEnableAutomaticCheckPreReleaseKey]) {
		BOOL checkPreReleases = [[object objectForKey:kNewKey] boolValue];
		[self _toggleCheckPreReleaseUpdates:checkPreReleases];
	}
}

#pragma mark -
#pragma mark Delegate
#pragma mark - NSApplication -

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{	
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	
//	NSTimeInterval start = [NSDate timeIntervalSinceReferenceDate];
	
	NSOperationQueue *queue = [[NSOperationQueue alloc] init];
	NSOperation *operation;
	
	/* load clips */
	operation = [[NSInvocationOperation alloc] initWithTarget:[ClipsController sharedInstance]
													 selector:@selector( loadClips )
													   object:nil];
	[queue addOperation:operation];
	[operation release], operation = nil;
	
	/* load actions */
	operation = [[NSInvocationOperation alloc] initWithTarget:[ActionController sharedInstance]
													 selector:@selector( loadActions )
													   object:nil];
	[queue addOperation:operation];
	[operation release], operation = nil;
	
	/* register hot-keys */
	operation = [[NSInvocationOperation alloc] initWithTarget:self
													 selector:@selector( _registerHotKeys )
													   object:nil];
	[queue addOperation:operation];
	[operation release], operation = nil;	
	
	/* ask to register as login item */
	if (([defaults boolForKey:CMPrefLoginItemKey] == NO) &&
		([defaults boolForKey:CMPrefSuppressAlertForLoginItemKey] == NO)) {
		[self _promptToAddLoginItems];
	}
		
	/* Sparkle updater */	
	SUUpdater *updater = [SUUpdater sharedUpdater];	
	
	[self _toggleCheckPreReleaseUpdates:[defaults boolForKey:CMEnableAutomaticCheckPreReleaseKey]];

	[updater setAutomaticallyChecksForUpdates:[defaults boolForKey:CMEnableAutomaticCheckKey]];
	[updater setUpdateCheckInterval:[defaults integerForKey:CMUpdateCheckIntervalKey]];
	
	[defaults addObserver:self
			   forKeyPath:CMEnableAutomaticCheckPreReleaseKey
				  options:NSKeyValueObservingOptionNew
				  context:nil];
	
	/* Finish all operations */
	[queue waitUntilAllOperationsAreFinished];
	[queue release], queue = nil;
	
//	NSTimeInterval end = [NSDate timeIntervalSinceReferenceDate];
//	NSLog(@"result: %f", (end - start));
	
//	[self showSnippetEditor:self];	// temp!!!
}

- (void)applicationWillTerminate:(NSNotification *)aNotification
{
	/* Save clips to file */
	BOOL saveHistoryOnQuit = [[NSUserDefaults standardUserDefaults] boolForKey:CMPrefSaveHistoryOnQuitKey];
	if (saveHistoryOnQuit) {
		BOOL result = [[ClipsController sharedInstance] saveClips];	
		if (result == NO) {
			[NSApp activateIgnoringOtherApps:YES];
			NSRunAlertPanel(NSLocalizedString(@"Error", nil),
							NSLocalizedString(@"Could not save your clipboard history to file.", nil),
							NSLocalizedString(@"OK", nil),
							nil,
							nil);
		}
	}
	else {
		[[ClipsController sharedInstance] removeClips];
	}
	
	[[ActionController sharedInstance] saveActions];
	
	[self _unregisterHotKeys];
}

#pragma mark -
#pragma mark Protocols
#pragma mark - NSMenuValidation -

- (BOOL)validateMenuItem:(NSMenuItem *)menuItem
{
//	NSLog(@"validateMenuItem");
	
	SEL action = [menuItem action];
	if (action == @selector( clearHistory: )) {
		NSUInteger numberOfClips = [[[ClipsController sharedInstance] clips] count];
		if (numberOfClips == 0) {
			return NO;
		}
	}

	return YES;
}

#pragma mark -
#pragma mark Public

- (IBAction)showPreferencePanel:(id)sender
{
	[[PrefsWindowController sharedPrefWindowController] showWindow:nil];
}

- (IBAction)showSnippetEditor:(id)sender
{
	if (!snippetEditorController) {
		snippetEditorController = [[SnippetEditorController alloc] init];
	}
	
	[snippetEditorController showWindow:self];
}

- (IBAction)clearHistory:(id)sender
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	BOOL showAlert = [defaults boolForKey:CMPrefShowAlertBeforeClearHistoryKey];
	
	if (showAlert) {
		NSAlert *alert = [[NSAlert alloc] init];
		[alert setMessageText:NSLocalizedString(@"Clear History", nil)];
		[alert setInformativeText:NSLocalizedString(@"Are you sure you want to clear your clipboard history?", nil)];
		[alert addButtonWithTitle:NSLocalizedString(@"Clear History", nil)];
		[alert addButtonWithTitle:NSLocalizedString(@"Cancel", nil)];
		[alert setShowsSuppressionButton:YES];
				
		[NSApp activateIgnoringOtherApps:YES];
		
		NSInteger result = [alert runModal];
		
		if ([[alert suppressionButton] state] == NSOnState) {
			[defaults setBool:NO forKey:CMPrefShowAlertBeforeClearHistoryKey];
		}
		
		[alert release], alert = nil;
		
		if (result != NSAlertFirstButtonReturn) {
			return;
		}
	}
	
	[[ClipsController sharedInstance] clearAll];
}

- (void)popUpClipMenu:(id)sender
{	
	[[MenuController sharedInstance] popUpMenuForType:CMPopUpMenuTypeMain];
}

- (void)popUpActionMenu:(id)sender
{
//	NSLog(@"selectAlternateMenuItem: %@", sender);
	
	NSArray *actionNodes = [[ActionController sharedInstance] actionNodes];
	if (!actionNodes || [actionNodes count] < 1) {
		return;
	}
	
	NSInteger tag = [sender tag];

	NSManagedObject *snippet = ([sender representedObject]) ? [sender representedObject] : nil;
	if (snippet) {
		tag = -1;
//		[[ActionController sharedInstance] setSelectedString:[snippet valueForKey:kContent]];
		[[ActionController sharedInstance] setSelectedSnippet:snippet];
	}
	
	[[ActionController sharedInstance] setSelectedClipTag:tag];
	
	BOOL isInvokeFirstActionImmediately = [[NSUserDefaults standardUserDefaults] boolForKey:CMPrefInvokeActionImmediatelyKey];
	
	if (isInvokeFirstActionImmediately && [actionNodes count] == 1) {
		ActionNode *actionNode = [actionNodes objectAtIndex:0];
		NSDictionary *action = [actionNode action];
		if (action) {
			[self _invokeAction:action];
		}
	}
	else {
		[[MenuController sharedInstance] popUpMenuForType:CMPopUpMenuTypeActions];
	}
	
	[[ActionController sharedInstance] clearSelection];
}

- (void)popUpHistoryMenu:(id)sender
{
	[[MenuController sharedInstance] popUpMenuForType:CMPopUpMenuTypeHistory];
}

- (void)popUpSnippetsMenu:(id)sender
{	
	[[MenuController sharedInstance] popUpMenuForType:CMPopUpMenuTypeSnippets];
}

- (void)selectMenuItem:(id)sender
{	
//	NSLog(@"selectMenuItem: %@", sender);
			
	BOOL actionApplied = [self _applyActionToTarget:sender];
	if (actionApplied) {
		return;		// no problem
	}
	
	NSInteger tag = [sender tag];
	[[ClipsController sharedInstance] copyClipToPasteboardAtIndex:tag];
	
	[CMUtilities paste];
}

- (void)selectSnippetMenuItem:(id)sender
{
//	NSLog(@"selectSnippetMenuItem: %@", sender);
	
	NSManagedObject *snippet = [sender representedObject];
	if (!snippet) {
		NSBeep();
		return;
	}
	
//	NSLog(@"snippet: %@", snippet);
		
	BOOL actionApplied = [self _applyActionToTarget:sender];
	if (actionApplied) {
		return;		// no problem
	}
	
	NSString *content = [snippet valueForKey:kContent];
	[[ClipsController sharedInstance] copyStringToPasteboard:content];
	[CMUtilities paste];
}

- (void)selectActionMenuItem:(id)sender
{	
	NSDictionary *action = [sender representedObject];
	if (!action) {
		return;
	}
		
	[self _invokeAction:(NSDictionary *)action];
}

#pragma mark -
#pragma mark Private

- (void)_toggleCheckPreReleaseUpdates:(BOOL)flag
{
	NSString *feed = (flag)
	? [CMUtilities infoValueForKey:@"SUPreReleaseFeedURL"]
	: [CMUtilities infoValueForKey:@"SUFeedURL"];
	
	NSURL *feedURL = [[NSURL alloc] initWithString:feed];
	[[SUUpdater sharedUpdater] setFeedURL:feedURL];
	[feedURL release], feedURL = nil;
}

#pragma mark - Login Item -

- (void)_promptToAddLoginItems
{
	NSAlert *alert = [[NSAlert alloc] init];
	[alert setMessageText:NSLocalizedString(@"Launch ClipMenu on system startup?", nil)];
	[alert setInformativeText:NSLocalizedString(@"You can change this setting in the Preferences if you want.", nil)];
	[alert addButtonWithTitle:NSLocalizedString(@"Launch on system startup", nil)];
	[alert addButtonWithTitle:NSLocalizedString(@"Don't Launch", nil)];
	[alert setShowsSuppressionButton:YES];
	
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	
	[NSApp activateIgnoringOtherApps:YES];

	if ([alert runModal] == NSAlertFirstButtonReturn) {
		[defaults setBool:YES forKey:CMPrefLoginItemKey];
		[self _toggleLoginItemState];
	}
	
	if ([[alert suppressionButton] state] == NSOnState) {
		[defaults setBool:YES forKey:CMPrefSuppressAlertForLoginItemKey];
	}
	
	[alert release], alert = nil;
}

- (void)_toggleAddingToLoginItems:(BOOL)flag
{	
	NSString *appPath = [[NSBundle mainBundle] bundlePath];
	
	if (flag) {
		[NMLoginItems addPathToLoginItems:appPath hide:NO];	
	}
	else {
		[NMLoginItems removePathFromLoginItems:appPath];
	}
}

- (void)_toggleLoginItemState
{
	BOOL isInLoginItems = [[NSUserDefaults standardUserDefaults] boolForKey:CMPrefLoginItemKey];
	[self _toggleAddingToLoginItems:isInLoginItems];
}

#pragma mark - HotKey -

- (void)_registerHotKeys
{
	PTHotKeyCenter *hotKeyCenter = [PTHotKeyCenter sharedCenter];
	
	//Read keyCombos from preferences
	NSDictionary *hotKeyCombos = [[NSUserDefaults standardUserDefaults] objectForKey:CMPrefHotKeysKey];
	
	NSDictionary *defaultHotKeyCombos = [AppController _defaultHotKeyCombos];
//	NSLog(@"hotKeyCombos: %@, defaultHotKeyCombos: %@", hotKeyCombos, defaultHotKeyCombos);
	
	for (NSString *identifier in defaultHotKeyCombos) {
		id keyComboPlist = [hotKeyCombos objectForKey:identifier];
		if (keyComboPlist == nil) {
			keyComboPlist = [defaultHotKeyCombos objectForKey:identifier];
		}
		
		PTKeyCombo *keyCombo = [[[PTKeyCombo alloc] initWithPlistRepresentation:keyComboPlist]
								autorelease];
		
		//Create our hot key
		PTHotKey *hotKey = [[PTHotKey alloc] initWithIdentifier:identifier
													   keyCombo:keyCombo];	
		
		NSString *selectorName = [[[CMUtilities hotKeyMap] objectForKey:identifier]
								  objectForKey:kSelector];
		[hotKey setTarget:self];
		[hotKey setAction:NSSelectorFromString( selectorName )];
		
		//Register it
		[hotKeyCenter registerHotKey:hotKey];
		[hotKey release], hotKey = nil;
	}
}

- (void)_unregisterHotKeys
{	
	//Unregister our hot key (not required?)	
	PTHotKeyCenter *hotKeyCenter = [PTHotKeyCenter sharedCenter];
	for (PTHotKey *hotKey in [hotKeyCenter allHotKeys]) {
		[hotKeyCenter unregisterHotKey:hotKey];
	}
}
				
- (BOOL)_invokeModifiedClickWithBehavior:(id)behavior andSender:(id)sender
{	
	if (!behavior) {
		return NO;
	}
	
	if ([behavior respondsToSelector:@selector( isEqualToString: )]) {
		if ([behavior isEqualToString:kEmptyString]) {
			return NO;
		}
		else if ([behavior isEqualToString:kPopUpActionMenu]) {
			[self popUpActionMenu:sender];
		}
	}
	else {
		/* behavior must be an NSDictionary */
//		NSLog(@"behavior: %@", behavior);
		[self _invokeAction:behavior toIndex:[sender tag]];
	}
	
	return YES;
}
				
#pragma mark - Action -

- (BOOL)_applyActionToTarget:(id)sender
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	BOOL enableAction = [defaults boolForKey:CMPrefEnableActionKey];
	
	if (!enableAction) {
		return NO;
	}
	
	NSEvent *currentEvent = [NSApp currentEvent];
	id behavior;			// NSString or NSDictionary
	BOOL success = NO;
	
//	NSLog(@"currentEvent: %@", currentEvent);
	
	if ([currentEvent type] == NSRightMouseUp 
		|| ([currentEvent modifierFlags] & NSControlKeyMask)) {
		behavior = [defaults objectForKey:CMPrefContorlClickBehaviorKey];
		success = [self _invokeModifiedClickWithBehavior:behavior andSender:sender];
	}
	else if ([currentEvent modifierFlags] & NSShiftKeyMask) {
		behavior = [defaults objectForKey:CMPrefShiftClickBehaviorKey];
		success = [self _invokeModifiedClickWithBehavior:behavior andSender:sender];
	}
	else if ([currentEvent modifierFlags] & NSAlternateKeyMask) {
		behavior = [defaults objectForKey:CMPrefOptionClickBehaviorKey];
		success = [self _invokeModifiedClickWithBehavior:behavior andSender:sender];
	}
	else if ([currentEvent modifierFlags] & NSCommandKeyMask) {
		behavior = [defaults objectForKey:CMPrefCommandClickBehaviorKey];
		success = [self _invokeModifiedClickWithBehavior:behavior andSender:sender];
	}
	
	return success;
}

- (void)_invokeAction:(NSDictionary *)action toIndex:(NSInteger)index
{
	NSString *type = [action objectForKey:@"type"];
	if (!type) {
		return;
	}
	
	id target;
	
	if (index < 0) {
		/* it's a snippet */
		target = [[ActionController sharedInstance] selectedSnippet];
	}
	else {
		/* it's a clip */
		target = [[ClipsController sharedInstance] clipAtIndex:index];
	}

	if ([type isEqualToString:CMBuiltinActionTypeKey]) {
//		Clip *clip = [[ClipsController sharedInstance] clipAtIndex:index];
//		[self _invokeBuiltinAction:action toClip:clip];
		
		[self _invokeBuiltinAction:action toTarget:target];
	}
	else if ([type isEqualToString:CMJavaScriptActionTypeKey]) {	
		[self _invokeJavaScriptAction:action atIndex:index];
	}
}

- (void)_invokeAction:(NSDictionary *)action
{
//	NSLog(@"_invokeAction: %@", action);
	
	NSInteger tag = [[ActionController sharedInstance] selectedClipTag];
	[self _invokeAction:action toIndex:tag];
}

- (void)_invokeBuiltinAction:(NSDictionary *)action toTarget:(id)target
{	
	NSString *actionName = [action objectForKey:@"name"];
	if (!actionName) {
		return;
	}
	
	[[ActionController sharedInstance] invokeCommandForKey:actionName toTarget:target];
}

- (void)_invokeJavaScriptAction:(NSDictionary *)action atIndex:(NSInteger)index
{	
//	GetFrontProcess(&frontPSN);					// Keep the most front of process
////	NSLog(@"frontPSN: %d, %d", frontPSN.highLongOfPSN, frontPSN.lowLongOfPSN);
//	
////	[self _moveCurrentProcessToForeground];
//
//	[NSApp activateIgnoringOtherApps:YES];		// for prompt called by JavaScript

	NSString *scriptPath = [action objectForKey:@"path"];
	if (!scriptPath || ![[NSFileManager defaultManager] fileExistsAtPath:scriptPath]) {
		CMRunAlertPanel(nil, 
						NSLocalizedString(@"The script you selected does not exist", nil), 
						NSLocalizedString(@"OK", nil), 
						nil, 
						nil);
		return;
	}
	
//	NSString *clipText;
//	
//	if (index < 0) {
//		/* it's a snippet */
//		clipText = [[[ActionController sharedInstance] selectedSnippet] valueForKey:kContent];
//	}
//	else {
//		/* it's a clip */
//		Clip *selectedClip = [[ClipsController sharedInstance] clipAtIndex:index];
//		clipText = [selectedClip stringValue];
//	}
//	
//	NSString *scriptResult = [[ActionController sharedInstance] invokeScript:scriptPath toText:clipText];
//	if (!scriptResult) {
//		return;
//	}
//			
//	Clip *newClip = [Clip clipWithString:scriptResult];	
//	if (!newClip) {
//		return;
//	}
//	
//	[[ClipsController sharedInstance] copyClipToPasteboard:newClip];

	ActionController *actionController = [ActionController sharedInstance];
	Clip *selectedClip;
	
	if (index < 0) {
		/* it's a snippet */
		NSString *snippetString = [[actionController selectedSnippet] valueForKey:kContent];
		selectedClip = [Clip clipWithString:snippetString];
	}
	else {
		/* it's a clip */
		selectedClip = [[ClipsController sharedInstance] clipAtIndex:index];
	}
	
	Clip *resultClip = [actionController invokeScript:scriptPath toClip:selectedClip];
	if (!resultClip) {
		return;
	}
	
	[[ClipsController sharedInstance] copyClipToPasteboard:resultClip];
	
	[CMUtilities paste];
}

#pragma mark - Process -

- (void)keepCurrentFrontProcessAndActivate
{
	GetFrontProcess(&frontPSN);						// Keep the most front of process
	[NSApp activateIgnoringOtherApps:YES];
}

- (BOOL)restorePreviousFrontProcess
{
	if (frontPSN.lowLongOfPSN == kNoProcess) {
		return YES;
	}
	
	//	TransformProcessType(&frontPSN, kProcessTransformToForegroundApplication);	// This doesn't work on Leopard
	OSErr osError = SetFrontProcess(&frontPSN);
	
	frontPSN.highLongOfPSN = 0;
	frontPSN.lowLongOfPSN  = kNoProcess;
	
	if (osError == noErr) {
		return YES;
	}
	return NO;
}

#pragma mark - Notification -

- (void)_handlePreferencePanelWillClose:(NSNotification *)aNotification
{
	[self _toggleLoginItemState];
}

@end
