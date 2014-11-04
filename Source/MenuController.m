//
//  MenuController.m
//  ClipMenu
//
//  Created by Naotaka Morimoto on 07/12/06.
//  Copyright 2007 Naotaka Morimoto. All rights reserved.
//

#import "MenuController.h"
#import "constants.h"
#import "ActionController.h"
#import "ActionNode.h"
#import "ClipsController.h"
#import "Clip.h"
#import "SnippetsController.h"
#import "SnippetEditorController.h"
#import "PrefsWindowController.h"
#import "NSString+NaoAdditions.h"


//#define INLINE_CLIPS_DISPLAY_NUMBER 10
//#define NUMBER_OF_ITEMS_IN_A_FOLDER 10
#define kMaxKeyEquivalents 10

#define DEFAULT_MENU_FONT_SIZE 14.0
#define LARGE_MENU_FONT_SIZE 28.0
#define HUGE_MENU_FONT_SIZE 42.0
#define SMALL_ICON_SIZE 16
#define LARGE_ICON_SIZE 32
#define HUGE_ICON_SIZE 48
#define THUMBNAIL_ICON_SIZE 128
#define MENU_TITLE_FORMAT @"%d. %@"
#define SHORTEN_SYMBOL @"..."

#define STATUS_MENU_ICON @"StatusMenuIcon"
#define STATUS_MENU_ICON_POSTFIX @"_pressed"
#define STATUS_MENU_ICON_FILE_EXTENSION @".png"

#pragma mark Static variables

static MenuController *sharedInstance = nil;

#pragma mark Functions

BOOL CMIsPerformableAction(NSDictionary *action)
{	
	//	NSLog(@"action: %@", action);
	
	NSString *name = [action objectForKey:@"name"];
	NSString *type = [action objectForKey:@"type"]; 	
	NSArray *selectedItemTypes;
	
	ActionController *actionController = [ActionController sharedInstance];
	NSInteger tag = [actionController selectedClipTag];
	
	if (tag < 0) {
		/* it's a snippet */
		selectedItemTypes = [NSArray arrayWithObject:NSStringPboardType];
	}
	else {
		/* its a clip */
		Clip *clip = [[[ClipsController sharedInstance] sortedClips] objectAtIndex:tag];
		selectedItemTypes = [clip types];
	}
		
	//	if ([selectedClipTypes containsObject:NSStringPboardType]) {
	//		return YES;
	//	}
	
	if ([type isEqualToString:CMBuiltinActionTypeKey]) {
		NSDictionary *builtInActions = [[actionController builtInActionController] valueForKey:@"actions"];
		NSDictionary *builtInAction = [builtInActions objectForKey:name];
		//		NSLog(@"builtInAction: %@", builtInAction);
		
		for (NSString *key in [builtInAction objectForKey:@"types"]) {
			//			NSLog(@"key: %@", key);
			if ([selectedItemTypes containsObject:key]) {
				return YES;
			}
		}
	}
	else if ([type isEqualToString:CMJavaScriptActionTypeKey]) {
		if ([selectedItemTypes containsObject:NSStringPboardType]) {
			return YES;
		}
	}
	
	return NO;
}

NSUInteger firstIndexOfMenuItems()
{
	if ([[NSUserDefaults standardUserDefaults] boolForKey:CMPrefMenuItemsTitleStartWithZeroKey]) {
		return 0;
	}
	return 1;
}

NSUInteger incrementListNumber(NSUInteger listNumber, NSUInteger max, NSUInteger start)
{
	listNumber++;
	
	if (listNumber == max 
		&& max == 10
		&& start == 1) {
		listNumber = 0;
	}
	
	return listNumber;
}

NSString *trimTitle(NSString *clipString)
{
	if (clipString == nil) {
		return kEmptyString;
	}
	
	NSString *theString = [clipString strip];
	
	NSRange aRange = NSMakeRange(0,0);
	NSUInteger lineStart = 0, lineEnd	= 0, contentsEnd = 0;
	[theString getLineStart:&lineStart end:&lineEnd contentsEnd:&contentsEnd forRange:aRange];
	
	//	NSLog(@"start:%d, lineEnd:%d, contentsEnd:%d", lineStart, lineEnd, contentsEnd);
	
	NSString *titleString = (lineEnd == [theString length])
	? theString
	: [theString substringToIndex:contentsEnd];
	
	NSUInteger maxMenuItemTitleLength = [[NSUserDefaults standardUserDefaults] integerForKey:CMPrefMaxMenuItemTitleLengthKey];
	if (maxMenuItemTitleLength < [SHORTEN_SYMBOL length]) {
		maxMenuItemTitleLength = [SHORTEN_SYMBOL length];
	}
	
	if ([titleString length] > maxMenuItemTitleLength) {
		titleString = [NSString stringWithFormat:@"%@%@",
					   [titleString substringToIndex:(maxMenuItemTitleLength - [SHORTEN_SYMBOL length])],
					   SHORTEN_SYMBOL];
	}
	
	return titleString;
}

NSAttributedString *makeAttributedTitle(NSString *title)
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	BOOL isChangeFontSize = [defaults boolForKey:CMPrefChangeFontSizeKey];
	NSInteger howToChangeFontSize = [defaults integerForKey:CMPrefHowToChangeFontSizeKey];
	BOOL isShowIcon = [defaults boolForKey:CMPrefShowIconInTheMenuKey];
	
	if (!isChangeFontSize) {
		return nil;
	}
	
	CGFloat fontSize = DEFAULT_MENU_FONT_SIZE;
	
	if (howToChangeFontSize == 0 && isShowIcon) {
		NSUInteger iconSize = [defaults integerForKey:CMPrefMenuIconSizeKey];
		switch (iconSize) {
			case LARGE_ICON_SIZE:
				fontSize = LARGE_MENU_FONT_SIZE;
				break;
			case HUGE_ICON_SIZE:
				fontSize = HUGE_MENU_FONT_SIZE;
				break;
		}
	}
	else if (howToChangeFontSize == 1) {
		fontSize = [defaults floatForKey:CMPrefSelectedFontSizeKey];
	}
	
	NSFont *font = [NSFont systemFontOfSize:fontSize];
	NSDictionary *attrsDict = [NSDictionary dictionaryWithObject:font
														  forKey:NSFontAttributeName];
	NSAttributedString *attrString = [[[NSAttributedString alloc] initWithString:title
																	  attributes:attrsDict] autorelease];
	return attrString;
}

#pragma mark -

@interface MenuController ()
- (void)_buildClipMenu;
- (void)_addClipsToMenu:(NSMenu *)aMenu;
- (void)_addSnippetsToMenu:(NSMenu *)aMenu atPosition:(CMPositionOfSnippets)positionOfSnippets;

- (NSString *)_menuItemTitleWithString:(NSString *)titileWithMark listNumber:(NSUInteger)listNumber boolean:(BOOL)isMarkWithNumber;
- (NSMenuItem *)_makeMenuItemForClip:(Clip *)clip withCount:(NSUInteger)count andListNumber:(NSUInteger)listNumber;
- (NSMenuItem *)_makeMenuItemForSnippet:(NSManagedObject *)snippet withListNumber:(NSUInteger)listNumber;
- (NSMenuItem *)_makeSubmenuItemWithCount:(NSUInteger)count start:(NSUInteger)start end:(NSUInteger)end numberOfItems:(NSUInteger)numberOfItems;
- (NSMenuItem *)_makeSubmenuItemWithTitle:(NSString *)title;
- (NSMenuItem *)_makeMenuItemWithTitle:(NSString *)itemName action:(SEL)anAction;
//- (NSMenuItem *)_makeSortMenuItem;

- (NSEvent *)_makeEventFromCurrentEvent:(NSEvent *)currentEvent mousePoint:(NSPoint)mousePoint windowNumber:(NSInteger)windowNumber;
- (NSEvent *)_makeEventForActionFromCurrentEvent:(NSEvent *)currentEvent mousePoint:(NSPoint)mousePoint windowNumber:(NSInteger)windowNumber;
- (NSMenu *)_makeHistoryMenu;
- (NSMenu *)_makeSnippetsMenu;
- (NSMenu *)_makeActionMenu;
- (NSMenuItem *)_makeActionMenuItemFromNode:(ActionNode *)node;
//- (BOOL)_isAppropriateAction:(NSDictionary *)action;

- (void)_changeStatusItem:(NSUInteger)tag;
- (void)_removeStatusItem;
- (void)_refreshStatusItem;

- (NSImage *)_iconForPboardType:(NSString *)type;
- (NSString *)_iconCacheKeyForType:(NSString *)type;
- (NSImage *)_iconForSnippet;
- (void)_cacheIconForTypes;
- (void)_cacheFolderIcon;
- (void)_cacheOpenFolderIcon;
- (void)_cacheActionIcon;
- (void)_cacheJavaScriptIcon;
- (void)_cacheSnippetIcon;
- (void)_resetMenuIconSize;
- (void)_resetIconCaches;
- (void)_unhighlightMenuItem;

- (void)_handlePreferencePanelWillClose:(NSNotification *)aNotification;
- (void)_handleSnippetEditorWillClose:(NSNotification *)aNotification;
- (void)_handleStatusMenuWillUpdate:(NSNotification *)aNotification;

- (id)_init;
@end

#pragma mark -
@implementation MenuController

@synthesize clipMenu;
@synthesize dummyWindow;
@synthesize statusItem;
@synthesize shortVersion;
@synthesize iconForStringPboardType;
@synthesize iconForRTFPboardType;
@synthesize iconForRTFDPboardType;
@synthesize iconForPDFPboardType;
@synthesize iconForFilenamesPboardType;
@synthesize iconForURLPboardType;
@synthesize iconForTIFFPboardType;
@synthesize folderIcon;
@synthesize openFolderIcon;
@synthesize actionIcon;
@synthesize javaScriptIcon;
@synthesize snippetIcon;
@synthesize menuIconSize;
@synthesize highlightedMenuItem;

#pragma mark -
#pragma mark Initialize

+ (void)initialize
{
	if (sharedInstance == nil) {
		sharedInstance = [[self alloc] _init];
	}
}

+ (MenuController *)sharedInstance
{
	return [[sharedInstance retain] autorelease];
}

- (id)init
{
	NSAssert(self != sharedInstance, @"Should never send init to the singleton instance");
	
	[self release];
	[sharedInstance retain];
	return sharedInstance;
}

- (id)_init
{
	self = [super init];
	if (self) {
		[self setShortVersion:[[[NSBundle mainBundle] infoDictionary]							   objectForKey:@"CFBundleShortVersionString"]];
		
		[self _buildClipMenu];		// need to edit snippet. should be improved.
		
		dummyWindow = [[NSWindow alloc] initWithContentRect:NSZeroRect
												  styleMask:NSBorderlessWindowMask
													backing:NSBackingStoreBuffered
													  defer:YES];
		[dummyWindow setCollectionBehavior:NSWindowCollectionBehaviorCanJoinAllSpaces];
		
		NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
		
//		if ([defaults integerForKey:CMPrefShowStatusItemKey]) {
//			[self _createStatusItem];
//		}
		
		[self _resetIconCaches];
		
		/* KVO */
		[defaults addObserver:self
				   forKeyPath:CMPrefShowStatusItemKey
					  options:(NSKeyValueObservingOptionNew | NSKeyValueObservingOptionOld)
					  context:nil];
		[defaults addObserver:self
				   forKeyPath:CMPrefMenuIconSizeKey
					  options:NSKeyValueObservingOptionNew
					  context:nil];
		
		/* Notification */
		NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
		[nc addObserver:self
			   selector:@selector( _handlePreferencePanelWillClose: )
				   name:CMPreferencePanelWillCloseNotification
				 object:nil];
		[nc addObserver:self
			   selector:@selector( _handleSnippetEditorWillClose: )
				   name:CMSnippetEditorWillCloseNotification
				 object:nil];
	}
	return self;
}

- (void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	
	/* KVO */
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	[defaults removeObserver:self
				  forKeyPath:CMPrefShowStatusItemKey];
	[defaults removeObserver:self
				  forKeyPath:CMPrefMenuIconSizeKey];
	
	
	[clipMenu release], clipMenu = nil;
	[dummyWindow release], dummyWindow = nil;

	if (statusItem) {
		[[NSStatusBar systemStatusBar] removeStatusItem:statusItem];
		[statusItem release], statusItem = nil;		
	}
	
	[shortVersion release], shortVersion = nil;
	[iconForStringPboardType release], iconForStringPboardType = nil;
	[iconForRTFPboardType release], iconForRTFPboardType = nil;
	[iconForRTFDPboardType release], iconForRTFDPboardType = nil;
	[iconForPDFPboardType release], iconForPDFPboardType = nil;
	[iconForFilenamesPboardType release], iconForFilenamesPboardType = nil;
	[iconForURLPboardType release], iconForURLPboardType = nil;
	[iconForTIFFPboardType release], iconForTIFFPboardType = nil;
	
	[folderIcon release], folderIcon = nil;
	[openFolderIcon release], openFolderIcon = nil;
	[actionIcon release], actionIcon = nil;
	[javaScriptIcon release], javaScriptIcon = nil;
	[snippetIcon release], snippetIcon = nil;
	
	[highlightedMenuItem release], highlightedMenuItem = nil;
	
	[super dealloc];
}

#pragma mark -
#pragma mark KVO

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
//	NSLog(@"observeValueForKeyPath: %@ - change: %@", keyPath, change);
	
	if ([keyPath isEqualToString:CMPrefShowStatusItemKey]) {
//		[self _toggleStatusItem];
		
		NSInteger old = [[change objectForKey:kOldKey] integerValue];
		NSInteger new = [[change objectForKey:kNewKey] integerValue];
		
		if (new == 0) {
			[self _removeStatusItem];
		}
		else if (new != old) {
			[self _changeStatusItem:new];
		}
	}
	else if ([keyPath isEqualToString:CMPrefMenuIconSizeKey]) {
		[self _resetMenuIconSize];
	}
}

#pragma mark -
#pragma mark Delegate
#pragma mark - NSMenu -

//- (void)menuNeedsUpdate:(NSMenu *)menu
//{
////	NSLog(@"menuNeedsUpdate");
//	
//	[[NSNotificationCenter defaultCenter] postNotificationName:CMClipMenuWillPopUpNotification object:nil];
//}

- (void)menu:(NSMenu *)menu willHighlightItem:(NSMenuItem *)item
{
	if (highlightedMenuItem && ![item isEqualTo:highlightedMenuItem]) {
		[self _unhighlightMenuItem];
	}
	
	if (![item hasSubmenu]) {
		return;
	}
	
	if ([item image] && openFolderIcon) {
		[self setHighlightedMenuItem:item];
		[item setImage:openFolderIcon];
	}
}

- (void)menuDidClose:(NSMenu *)menu
{
	if (highlightedMenuItem) {
		[self _unhighlightMenuItem];
	}
}

#pragma mark -
#pragma mark Public

- (void)createStatusItem
{
	if (statusItem == nil) {
		NSUInteger statusMenuIconTag = [[NSUserDefaults standardUserDefaults]
										integerForKey:CMPrefShowStatusItemKey];
		
		[self _changeStatusItem:statusMenuIconTag];
	}
}

- (void)updateStatusMenu
{
//	NSLog(@"updateStatusMenu: %@", statusItem);
	
	if (statusItem) {		
//		[self _resetMenuIconSize];		// XXX Need to modify?
		
		[self _buildClipMenu];
		[statusItem setMenu:clipMenu];
	}
}

- (void)popUpMenuForType:(CMPopUpMenuType)type
{
	NSEvent *currentEvent = [NSApp currentEvent];
	NSPoint locationInWindow = [currentEvent locationInWindow];
	NSPoint mouseLocation;		// for Actions
	NSPoint mousePoint;
	NSEvent *newEvent;
	
//	NSLog(@"currentEvent: %@", currentEvent);
//	NSLog(@"origin: %@", NSStringFromPoint([currentEvent locationInWindow]));
	
	[dummyWindow makeKeyAndOrderFront:self];
	[dummyWindow setFrameOrigin:locationInWindow];
	NSInteger windowNumber = [dummyWindow windowNumber];
		
//	NSLog(@"popUpClipMenu: %@", NSStringFromPoint(mousePoint));
	
	NSMenu *menu;
	
	switch (type) {
		case CMPopUpMenuTypeMain:
			mousePoint = [dummyWindow convertScreenToBase:locationInWindow];	
			newEvent = [self _makeEventFromCurrentEvent:currentEvent
											 mousePoint:mousePoint
										   windowNumber:windowNumber];
			[self _buildClipMenu];
			menu = clipMenu;
			break;
		case CMPopUpMenuTypeHistory:
			mousePoint = [dummyWindow convertScreenToBase:locationInWindow];	
			newEvent = [self _makeEventFromCurrentEvent:currentEvent
											 mousePoint:mousePoint
										   windowNumber:windowNumber];
			menu = [self _makeHistoryMenu];
			break;			
		case CMPopUpMenuTypeSnippets:
			mousePoint = [dummyWindow convertScreenToBase:locationInWindow];	
			newEvent = [self _makeEventFromCurrentEvent:currentEvent
											 mousePoint:mousePoint
										   windowNumber:windowNumber];
			menu = [self _makeSnippetsMenu];
			break;
		case CMPopUpMenuTypeActions:
			mouseLocation = [NSEvent mouseLocation];
			mousePoint = [dummyWindow convertScreenToBase:mouseLocation];
			newEvent = [self _makeEventForActionFromCurrentEvent:currentEvent
													  mousePoint:mousePoint
													windowNumber:windowNumber];
			menu = [self _makeActionMenu];
			break;
		default:
			NSAssert(NO, @"Unknown pop up menu type");
			break;
	}
	
//	/* Highlight the first menu item */
//	NSMenuItem *firstItem = [menu itemAtIndex:1];
//	if (firstItem) {
//		NSLog(@"item: %@", firstItem);
//		[menu _setHighlightedItem:firstItem informingDelegate:YES];
//		NSLog(@"hilighted: %@", [menu highlightedItem]);
//	}
	
	[NSMenu popUpContextMenu:menu withEvent:newEvent forView:nil];
	[dummyWindow orderOut:self];
}

#pragma mark -
#pragma mark Private

#pragma mark - Menu -

- (void)_buildClipMenu
{
	NSMenu *newMenu = [[NSMenu allocWithZone:[NSMenu menuZone]] initWithTitle:kClipMenuIdentifier];
	[newMenu setDelegate:self];
	
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	CMPositionOfSnippets positionOfSnippets = [defaults integerForKey:CMPrefPositionOfSnippetsKey];
	BOOL addClearHistory = [defaults boolForKey:CMPrefAddClearHistoryMenuItemKey];
	
	if (CMPositionOfSnippetsAboveClips == positionOfSnippets) {
		[self _addSnippetsToMenu:newMenu atPosition:positionOfSnippets];
	}
	
	[self _addClipsToMenu:newMenu];
	
	if (CMPositionOfSnippetsBelowClips == positionOfSnippets) {
		[self _addSnippetsToMenu:newMenu atPosition:positionOfSnippets];
	}
	
	[newMenu addItem:[NSMenuItem separatorItem]];	
	
	if (addClearHistory) {
		[newMenu addItem:[self _makeMenuItemWithTitle:NSLocalizedString(@"Clear History", nil)
											   action:@selector( clearHistory: )]];
	}
	
	[newMenu addItem:[self _makeMenuItemWithTitle:NSLocalizedString(@"Edit Snippets...", nil)
										   action:@selector( showSnippetEditor: )]];
	
	[newMenu addItem:[self _makeMenuItemWithTitle:NSLocalizedString(@"Preferences...", nil)
										   action:@selector( showPreferencePanel: )]];
	
	//	[newMenu addItemWithTitle:NSLocalizedString(@"About ClipMenu", nil)
	//					   action:@selector( orderFrontStandardAboutPanel: )
	//				keyEquivalent:kEmptyString];
	[newMenu addItem:[NSMenuItem separatorItem]];
	[newMenu addItem:[self _makeMenuItemWithTitle:NSLocalizedString(@"Quit ClipMenu", nil)
										   action:@selector( terminate: )]];
	
	[self setValue:newMenu forKey:@"clipMenu"];
	[newMenu release], newMenu = nil;
}

- (void)_addClipsToMenu:(NSMenu *)aMenu
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	NSUInteger numberOfItemsPlaceInline = [defaults integerForKey:CMPrefNumberOfItemsPlaceInlineKey];
	NSUInteger numberOfItemsPlaceInsideFolder = [defaults integerForKey:CMPrefNumberOfItemsPlaceInsideFolderKey];
	NSUInteger maxHistory = [defaults integerForKey:CMPrefMaxHistorySizeKey];
	BOOL showLabelsInMenu = [defaults boolForKey:CMPrefShowLabelsInMenuKey];
	
	ClipsController *clipsController = [ClipsController sharedInstance];
	NSArray *clips = [clipsController sortedClips];
	NSUInteger currentSize = [clips count];
	
	//	if (currentSize < maxHistory) {
	//		maxHistory = currentSize;
	//	}
	
	if (showLabelsInMenu) {
		NSMenuItem *labelItem = [[NSMenuItem allocWithZone:[NSMenu menuZone]]
								 initWithTitle:NSLocalizedString(@"History", nil)
								 action:NULL 
								 keyEquivalent:kEmptyString]; 
		[labelItem setEnabled:NO];
		[aMenu addItem:labelItem];
		[labelItem release], labelItem = nil;
	}
	
	NSUInteger firstIndex = firstIndexOfMenuItems();
	NSUInteger listNumber = firstIndex;
	NSUInteger submenuCount = numberOfItemsPlaceInline;
	NSUInteger submenuIndex = (0 < [aMenu numberOfItems]) ? [aMenu numberOfItems] : 0;
	submenuIndex += numberOfItemsPlaceInline;
	
	NSUInteger i = 0;
	
	for (Clip *clip in clips) {		
		//		NSLog(@"CHECK i: %d", i);
		
		if ((numberOfItemsPlaceInline < 1) ||
			(numberOfItemsPlaceInline - 1) < i) {		
			/* inside a folder */
			if (i == submenuCount) {
				NSMenuItem *submenuItem = [self _makeSubmenuItemWithCount:submenuCount
																	start:firstIndex
																	  end:currentSize
															numberOfItems:numberOfItemsPlaceInsideFolder];
				[aMenu addItem:submenuItem];
				listNumber = firstIndex;
			}
			
			//			NSLog(@"CHECK submenuCount: %d", submenuCount);
			//			NSLog(@"CHECK submenuIndex: %d", submenuIndex);
			
			//			NSUInteger indexOfSubmenu = (enableAction) 
			//			? submenuIndex + numberOfItemsPlaceInline 
			//			: submenuIndex;
			
			NSUInteger indexOfSubmenu = submenuIndex;
			
			//			if (showLabelsInMenu) {
			//				indexOfSubmenu++;
			//			}
			
			//			NSLog(@"CHECK indexOfSubmenu: %d", indexOfSubmenu);
			
			NSMenu *submenu = [[aMenu itemAtIndex:indexOfSubmenu] submenu];		
			NSMenuItem *menuItem = [self _makeMenuItemForClip:clip
													withCount:i
												andListNumber:listNumber];
			[submenu addItem:menuItem];
			
			listNumber = incrementListNumber(listNumber, numberOfItemsPlaceInsideFolder, firstIndex);
		}
		else {												
			/* display clips inline */
			NSMenuItem *menuItem = [self _makeMenuItemForClip:clip 
													withCount:i
												andListNumber:listNumber];
			[aMenu addItem:menuItem];
			
			listNumber = incrementListNumber(listNumber, numberOfItemsPlaceInline, firstIndex);
		}
		
		i++;
		//		listNumber = incrementListNumber(listNumber, numberOfItemsPlaceInsideFolder);
		if (i == (submenuCount + numberOfItemsPlaceInsideFolder)) {
			submenuCount += numberOfItemsPlaceInsideFolder;
			submenuIndex++;
		}
		
		if (maxHistory <= i) {
			break;
		}
	}
}

- (void)_addSnippetsToMenu:(NSMenu *)aMenu atPosition:(CMPositionOfSnippets)positionOfSnippets
{	
	SnippetsController *snippetsController = [SnippetsController sharedInstance];
	NSArray *snippetFolders = [snippetsController folders];
	if (!snippetFolders || [snippetFolders count] < 1) {
		return;
	}
	
	if (CMPositionOfSnippetsBelowClips == positionOfSnippets) {
		[aMenu addItem:[NSMenuItem separatorItem]];
	}
	
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	BOOL showLabelsInMenu = [defaults boolForKey:CMPrefShowLabelsInMenuKey];
	
	if (showLabelsInMenu) {
		NSMenuItem *snippetsLabelItem = [[NSMenuItem allocWithZone:[NSMenu menuZone]]
										 initWithTitle:NSLocalizedString(@"Snippets", nil)
										 action:NULL 
										 keyEquivalent:kEmptyString]; 
		[snippetsLabelItem setEnabled:NO];
		[aMenu addItem:snippetsLabelItem];
		[snippetsLabelItem release], snippetsLabelItem = nil;
	}
	
	NSArray *sortDescriptors = [SnippetsController sortDescriptors];
	
	BOOL enabled;
	NSUInteger submenuIndex = [aMenu numberOfItems] - 1;
	NSUInteger firstIndex = firstIndexOfMenuItems();
	
	//	NSLog(@"numberOfItems: %d", [aMenu numberOfItems]);
	//	NSLog(@"submenuIndex: %@", [aMenu itemAtIndex:submenuIndex]);
	
	for (NSManagedObject *folder in snippetFolders) {		
		/* Add folder to menu */
		enabled = [[folder valueForKey:kEnabled] boolValue];
		if (!enabled) {
			continue;
		}
		
		NSString *folderTitle = [folder valueForKey:kTitle];		
		NSMenuItem *subMenuItem = [self _makeSubmenuItemWithTitle:folderTitle];
		[aMenu addItem:subMenuItem];
		submenuIndex++;
		
		/* Get snippets */
		NSManagedObjectContext *managedObjectContext = [folder managedObjectContext];
		NSEntityDescription *entity = [NSEntityDescription entityForName:kSnippetEntity
												  inManagedObjectContext:managedObjectContext];
		NSFetchRequest *request = [[[NSFetchRequest alloc] init] autorelease];
		[request setEntity:entity];
		[request setSortDescriptors:sortDescriptors];
		
		NSPredicate *predicate = [NSPredicate predicateWithFormat:@"%K == %@", kFolder, folder];
		[request setPredicate:predicate];
		
		NSError *error = nil;
		NSArray *fetchResluts = [managedObjectContext executeFetchRequest:request
																	error:&error];
		if (!fetchResluts || [fetchResluts count] < 1) {
			continue;
		}
		
		/* Add snippets into submenu */
		NSUInteger i = firstIndex;
		
		for (NSManagedObject *snippet in fetchResluts) {
			enabled = [[snippet valueForKey:kEnabled] boolValue];
			if (!enabled) {
				continue;
			}
			
//			NSLog(@"snippet: %@", snippet);
			
			NSMenuItem *menuItem = [self _makeMenuItemForSnippet:snippet withListNumber:i];
			
			NSMenu *subMenu = [[aMenu itemAtIndex:submenuIndex] submenu];
			[subMenu addItem:menuItem];
			i++;
		}
	}
	
	if (CMPositionOfSnippetsAboveClips == positionOfSnippets) {
		[aMenu addItem:[NSMenuItem separatorItem]];
	}
}

- (NSString *)_menuItemTitleWithString:(NSString *)titleString listNumber:(NSUInteger)listNumber boolean:(BOOL)isMarkWithNumber
{	
	if (isMarkWithNumber) {
		return [NSString stringWithFormat:MENU_TITLE_FORMAT, listNumber, titleString];
	}
	
	return titleString;
}

- (NSMenuItem *)_makeMenuItemForClip:(Clip *)clip withCount:(NSUInteger)count andListNumber:(NSUInteger)listNumber
{	
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	BOOL isMarkWithNumber = [defaults boolForKey:CMPrefMenuItemsAreMarkedWithNumbersKey];
	BOOL isShowToolTip = [defaults boolForKey:CMPrefShowToolTipOnMenuItemKey];
	BOOL isShowIcon = [defaults boolForKey:CMPrefShowIconInTheMenuKey];
	BOOL isShowImage = [defaults boolForKey:CMPrefShowImageInTheMenuKey];
	BOOL addNumericKeyEquivalents = [defaults boolForKey:CMPrefAddNumericKeyEquivalentsKey];
	
	NSString *keyEquivalent = kEmptyString;
	
	if (addNumericKeyEquivalents && (count <= kMaxKeyEquivalents)) {
		BOOL isStartFromZero = [defaults boolForKey:CMPrefMenuItemsTitleStartWithZeroKey];
		
		NSUInteger shortCutNumber = (isStartFromZero) ? count : count + 1;
		if (shortCutNumber == kMaxKeyEquivalents) {
			shortCutNumber = 0;
		}
		
		keyEquivalent = [NSString stringWithFormat:@"%d", shortCutNumber];
	}
	
	NSArray *pbTypes = [clip types];
	NSString *primaryPboardType = [clip primaryPboardType];
	NSImage *icon = nil;
	
	if (pbTypes && [pbTypes count] > 0) {
		if (isShowIcon) {
			icon = [self _iconForPboardType:primaryPboardType];
		}
	}
	
	/* stringValue */
	NSString *clipString = [clip stringValue];
	NSString *title = trimTitle(clipString);
	NSString *titleWithMark = [self _menuItemTitleWithString:title
												  listNumber:listNumber 
													 boolean:isMarkWithNumber];
	
	NSMenuItem *menuItem = [[[NSMenuItem allocWithZone:[NSMenu menuZone]]
							 initWithTitle:titleWithMark
							 action:@selector( selectMenuItem: )
							 keyEquivalent:keyEquivalent] autorelease];
	[menuItem setTag:count];
	
	/* Tool Tip */
	if (isShowToolTip) {
		NSUInteger maxLengthOfToolTip = [defaults integerForKey:CMPrefMaxLengthOfToolTipKey];
		NSUInteger toIndex = ([clipString length] < maxLengthOfToolTip) 
		? [clipString length]
		: maxLengthOfToolTip;
		[menuItem setToolTip:[clipString substringToIndex:toIndex]];
	}
	
	/* Change Menu Font Size */
	NSAttributedString *attrString = makeAttributedTitle(titleWithMark);
	if (attrString) {
		[menuItem setAttributedTitle:attrString];
	}
	
	if ([primaryPboardType isEqualToString:NSTIFFPboardType]
		|| [primaryPboardType isEqualToString:NSPICTPboardType]) {
		[menuItem setTitle:[self _menuItemTitleWithString:@"(Image)" 
											   listNumber:listNumber
												  boolean:isMarkWithNumber]];
	}
	else if ([primaryPboardType isEqualToString:NSPDFPboardType]) {
		[menuItem setTitle:[self _menuItemTitleWithString:@"(PDF)"
											   listNumber:listNumber 
												  boolean:isMarkWithNumber]];
	}
	else if ([primaryPboardType isEqualToString:NSFilenamesPboardType]
			 && [title isEqualToString:kEmptyString]) {
		[menuItem setTitle:[self _menuItemTitleWithString:@"(Filenames)" 
											   listNumber:listNumber
												  boolean:isMarkWithNumber]];
	}
	
	/* image */
	NSImage *image = clip.image;
	if (isShowImage &&
		image &&
		![primaryPboardType isEqualToString:NSFilenamesPboardType]) {		
		NSInteger thumbnailWidth = [defaults integerForKey:CMPrefThumbnailWidthKey];
		NSInteger thumbnailHeight = [defaults integerForKey:CMPrefThumbnailHeightKey];
		
		image = [clip thumbnailOfSize:NSMakeSize(thumbnailWidth, thumbnailHeight)];
		if (image) {
			[menuItem setImage:image];
		}
	}
	
	/* icon for menuItem */
	if (icon && !image) {
		[icon setSize:NSMakeSize(menuIconSize,menuIconSize)];
		[menuItem setImage:icon];
	}
	
	return menuItem;
}

- (NSMenuItem *)_makeMenuItemForSnippet:(NSManagedObject *)snippet withListNumber:(NSUInteger)listNumber
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	BOOL isMarkWithNumber = [defaults boolForKey:CMPrefMenuItemsAreMarkedWithNumbersKey];
	BOOL isShowIcon = [defaults boolForKey:CMPrefShowIconInTheMenuKey];
	//	BOOL addNumericKeyEquivalents = [defaults boolForKey:CMPrefAddNumericKeyEquivalentsKey];
	
	NSString *keyEquivalent = kEmptyString;
	//	if (addNumericKeyEquivalents) {
	//		BOOL isStartFromZero = [defaults boolForKey:CMPrefMenuItemsTitleStartWithZeroKey];
	//		NSUInteger shortCutNumber = (isStartFromZero)
	//		? listNumber
	//		: ((listNumber == kMaxKeyEquivalents) ? 0 : listNumber);
	//		
	//		if (listNumber <= kMaxKeyEquivalents) {
	//			keyEquivalent = [NSString stringWithFormat:@"%d", shortCutNumber];
	//		}
	//	}
	
	NSImage *icon = nil;
	
	if (isShowIcon) {
		icon = [self _iconForSnippet];
	}
	
	/* stringValue */
	NSString *title = trimTitle([snippet valueForKey:kTitle]);
	NSString *titleWithMark = [self _menuItemTitleWithString:title
												  listNumber:listNumber 
													 boolean:isMarkWithNumber];
	
	NSMenuItem *menuItem = [[[NSMenuItem allocWithZone:[NSMenu menuZone]] 
							 initWithTitle:titleWithMark
							 action:@selector( selectSnippetMenuItem: )
							 keyEquivalent:keyEquivalent] autorelease];
	[menuItem setRepresentedObject:snippet];
	//	[menuItem setTag:count];
	[menuItem setToolTip:[snippet valueForKey:kContent]];
	
	/* Change Menu Font Size */
	NSAttributedString *attrString = makeAttributedTitle(titleWithMark);
	if (attrString) {
		[menuItem setAttributedTitle:attrString];
	}
	
	/* icon for menuItem */
	if (icon) {
		[icon setSize:NSMakeSize(menuIconSize,menuIconSize)];
		[menuItem setImage:icon];
	}
	
	return menuItem;
}

- (NSMenuItem *)_makeSubmenuItemWithCount:(NSUInteger)count start:(NSUInteger)start end:(NSUInteger)end numberOfItems:(NSUInteger)numberOfItems
{
	if (start == 0) {
		count--;
	}
	
	NSUInteger lastNumber = count + numberOfItems;
	//	NSLog(@"count: %d, start:%d, end:%d, lastNumber: %d", count, start, end, lastNumber);
	
	if (end < lastNumber) {
		lastNumber = end;
	}
	
	NSString *menuItemTitle = [NSString stringWithFormat:@"%d - %d",
							   count + 1,
							   lastNumber];
	return [self _makeSubmenuItemWithTitle:menuItemTitle];
}

- (NSMenuItem *)_makeSubmenuItemWithTitle:(NSString *)title
{
	//	NSLog(@"_makeSubmenu");
	
	NSMenu *submenu = [[NSMenu allocWithZone:[NSMenu menuZone]] init];
	NSMenuItem *submenuItem = [[[NSMenuItem allocWithZone:[NSMenu menuZone]] 
								initWithTitle:title
								action:NULL
								keyEquivalent:kEmptyString] autorelease];
	[submenuItem setSubmenu:submenu];
	[submenu release], submenu = nil;
	
	NSAttributedString *attrString = makeAttributedTitle(title);
	if (attrString) {
		[submenuItem setAttributedTitle:attrString];
	}
	
	/* icon */	
	if ([[NSUserDefaults standardUserDefaults] boolForKey:CMPrefShowIconInTheMenuKey]
		&& folderIcon) {
		//		[folderIcon setSize:NSMakeSize(menuIconSize,menuIconSize)];
		[submenuItem setImage:folderIcon];
	}
	
	return submenuItem;
}

- (NSMenuItem *)_makeMenuItemWithTitle:(NSString *)itemName action:(SEL)anAction
{
	NSMenuItem *menuItem = [[[NSMenuItem allocWithZone:[NSMenu menuZone]]
							 initWithTitle:itemName
							 action:anAction
							 keyEquivalent:kEmptyString] autorelease];
	
	NSAttributedString *attrString = makeAttributedTitle(itemName);
	if (attrString) {
		[menuItem setAttributedTitle:attrString];
	}
	
	return menuItem;
}

//- (NSMenuItem *)_makeSortMenuItem
//{
//	NSString *title = @"Sort";
//	BOOL isAscending = NO;
//	
//	NSCellStateValue ascMenuItemState;
//	NSCellStateValue descMenuItemState;
//	
//	if (isAscending) {
//		ascMenuItemState = NSOnState;
//		descMenuItemState = NSOffState;
//	}
//	else {
//		ascMenuItemState = NSOffState;
//		descMenuItemState = NSOnState;
//	}
//	
//	NSMenu *submenu = [[NSMenu allocWithZone:[NSMenu menuZone]] init];
//	
//	NSMenuItem *ascMenuItem = [self _makeMenuItemWithTitle:@"Ascending" action:NULL];
//	[ascMenuItem setState:ascMenuItemState];
//	[submenu addItem:ascMenuItem];
//	
//	NSMenuItem *descMenuItem = [self _makeMenuItemWithTitle:@"Descending" action:NULL];
//	[descMenuItem setState:descMenuItemState];
//	[submenu addItem:descMenuItem];
//	
//	NSMenuItem *submenuItem = [[[NSMenuItem allocWithZone:[NSMenu menuZone]] 
//								initWithTitle:title
//								action:NULL
//								keyEquivalent:kEmptyString] autorelease];
//	[submenuItem setSubmenu:submenu];
//	[submenu release], submenu = nil;
//	
//	NSAttributedString *attrString = makeAttributedTitle(title);
//	if (attrString) {
//		[submenuItem setAttributedTitle:attrString];
//	}
//	
//	return submenuItem;
//}

#pragma mark - Menu Pop Up -

- (NSEvent *)_makeEventFromCurrentEvent:(NSEvent *)currentEvent mousePoint:(NSPoint)mousePoint windowNumber:(NSInteger)windowNumber
{
	return [NSEvent otherEventWithType:[currentEvent type]
							  location:mousePoint
						 modifierFlags:[currentEvent modifierFlags]
							 timestamp:[currentEvent timestamp]
						  windowNumber:windowNumber
							   context:[currentEvent context]
							   subtype:[currentEvent subtype]
								 data1:[currentEvent data1]
								 data2:[currentEvent data2]];
}

- (NSEvent *)_makeEventForActionFromCurrentEvent:(NSEvent *)currentEvent mousePoint:(NSPoint)mousePoint windowNumber:(NSInteger)windowNumber
{
	NSEvent *newEvent;
	
	switch ([currentEvent type]) {
		case NSLeftMouseDown:
		case NSLeftMouseUp:
		case NSRightMouseDown:
		case NSRightMouseUp:
		case NSKeyDown:
			/* default behavior */
			newEvent = [NSEvent otherEventWithType:NSApplicationDefined
										  location:mousePoint
									 modifierFlags:0
										 timestamp:0
									  windowNumber:windowNumber
										   context:nil
										   subtype:0
											 data1:0
											 data2:0];
			break;
		default:			
			/* not reach here? */			
			newEvent = [NSEvent otherEventWithType:[currentEvent type]
										  location:mousePoint
									 modifierFlags:[currentEvent modifierFlags]
										 timestamp:[currentEvent timestamp]
									  windowNumber:windowNumber
										   context:[currentEvent context]
										   subtype:[currentEvent subtype]
											 data1:[currentEvent data1]
											 data2:[currentEvent data2]];
			break;
	}
	
	return newEvent;
}

- (NSMenu *)_makeHistoryMenu
{
	NSMenu *newMenu = [[[NSMenu allocWithZone:[NSMenu menuZone]]
						initWithTitle:kHistoryMenuIdentifier] autorelease];
	[newMenu setDelegate:self];
	[self _addClipsToMenu:newMenu];
	
	return newMenu;
}

- (NSMenu *)_makeSnippetsMenu
{
	//	NSLog(@"_makeSnippetsMenu");
	
	NSMenu *newMenu = [[[NSMenu allocWithZone:[NSMenu menuZone]]
						initWithTitle:kSnippetsMenuIdentifier] autorelease];
	[newMenu setDelegate:self];
	[self _addSnippetsToMenu:newMenu atPosition:CMPositionOfSnippetsNone];
	
	return newMenu;
}

- (NSMenu *)_makeActionMenu
{
	//	NSLog(@"_makeActionMenu");
	
	NSMenu *newMenu = [[[NSMenu allocWithZone:[NSMenu menuZone]]
						initWithTitle:kActionMenuIdentifier] autorelease];
	[newMenu setDelegate:self];
	
	NSArray *actionNodes = [[ActionController sharedInstance] actionNodes];
	for (ActionNode *node in actionNodes) {
		//		NSLog(@"node: %@", [node nodeTitle]);
		
		NSMenuItem *newActionMenuItem = nil;
		if (newActionMenuItem = [self _makeActionMenuItemFromNode:node]) {
			[newMenu addItem:newActionMenuItem];
		}
	}
	
	//	[newMenu addItem:[NSMenuItem separatorItem]];
	//	
	//	NSMenuItem *menuItem = [[NSMenuItem allocWithZone:[NSMenu menuZone]] initWithTitle:NSLocalizedString(@"Remove", nil)
	//													  action:@selector(selectAction:)
	//											   keyEquivalent:kEmptyString];
	//	[menuItem setRepresentedObject:[NSString stringWithString:@"Remove"]];
	//	[newMenu addItem:menuItem];
	//	[menuItem release], menuItem = nil;
	
	return newMenu;
}

- (NSMenuItem *)_makeActionMenuItemFromNode:(ActionNode *)node
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	BOOL isShowIcon = [defaults boolForKey:CMPrefShowIconInTheMenuKey];
	
	if ([node isLeaf]) {			
		NSMenuItem *actionMenuItem = [[[NSMenuItem allocWithZone:[NSMenu menuZone]] 
									   initWithTitle:[node nodeTitle]
									   action:@selector( selectActionMenuItem: )
									   keyEquivalent:kEmptyString] autorelease];
		
		NSDictionary *action = [node action];
		
		if (action) {
			//			if (![self _isAppropriateAction:action]) {
			//				return nil;
			//			}
			
			if (!CMIsPerformableAction(action)) {
				return nil;
			}
			
			[actionMenuItem setRepresentedObject:action];
			
			/* Tool Tip */
			BOOL isShowToolTip = [defaults boolForKey:CMPrefShowToolTipOnMenuItemKey];
			if (isShowToolTip) {
				NSDictionary *toolTips = [[[ActionController sharedInstance] builtInActionController] valueForKey:@"toolTips"];
				NSString *actionName = [action objectForKey:@"name"];
				NSString *toolTipOfAction = nil;
				if (toolTipOfAction = [toolTips objectForKey:actionName]) {
					[actionMenuItem setToolTip:toolTipOfAction];
				}
			}
		}
		
		/* icon for menuItem */
		if (isShowIcon) {
			NSString *type = [action objectForKey:@"type"];
			if ([type isEqualToString:CMBuiltinActionTypeKey] && actionIcon) {
				[actionMenuItem setImage:actionIcon];
			}
			else if ([type isEqualToString:CMJavaScriptActionTypeKey] && javaScriptIcon) {
				[actionMenuItem setImage:javaScriptIcon];
			}
		}
		
		return actionMenuItem;
	}
	else {
		NSMenu *subMenu = [[[NSMenu allocWithZone:[NSMenu menuZone]] init] autorelease];
		
		for (ActionNode *childNode in [node children]) {
			NSMenuItem *newActionMenuItem = nil;
			if (newActionMenuItem = [self _makeActionMenuItemFromNode:childNode]) {
				[subMenu addItem:newActionMenuItem];
			}
		}
		
		if ([subMenu numberOfItems] == 0) {
			return nil;
		}
		
		NSMenuItem *folderMenuItem = [[[NSMenuItem allocWithZone:[NSMenu menuZone]] 
									   initWithTitle:[node nodeTitle]
									   action:NULL
									   keyEquivalent:kEmptyString] autorelease];
		[folderMenuItem setSubmenu:subMenu];
		
		/* icon for menuItem */
		if (isShowIcon && folderIcon) {
			//			[icon setSize:NSMakeSize(menuIconSize,menuIconSize)];
			[folderMenuItem setImage:folderIcon];
		}
		
		return folderMenuItem;
	}
}

//- (BOOL)_isAppropriateAction:(NSDictionary *)action
//{	
////	NSLog(@"action: %@", action);
//	
//	NSString *name = [action objectForKey:@"name"];
//	NSString *type = [action objectForKey:@"type"]; 
////	if ([type isEqualToString:CMBuiltinActionTypeKey]) {
////		return YES;
////	}
//	
//	ActionController *actionController = [ActionController sharedInstance];
//	NSInteger tag = [actionController selectedClipTag];
//	Clip *clip = [[[ClipsController sharedInstance] clips] objectAtIndex:tag];
//	NSArray *selectedClipTypes = [clip types];
//	
////	NSLog(@"selectedClipTypes: %@", selectedClipTypes);
//	
////	if ([selectedClipTypes containsObject:NSStringPboardType]) {
////		return YES;
////	}
//	
//	if ([type isEqualToString:CMBuiltinActionTypeKey]) {
//		NSDictionary *builtInActions = [[actionController builtInActionController] valueForKey:@"actions"];
//		NSDictionary *builtInAction = [builtInActions objectForKey:name];
////		NSLog(@"builtInAction: %@", builtInAction);
//		
//		for (NSString *key in [builtInAction objectForKey:@"types"]) {
////			NSLog(@"key: %@", key);
//			if ([selectedClipTypes containsObject:key]) {
//				return YES;
//			}
//		}
//	}
//	else if ([type isEqualToString:CMJavaScriptActionTypeKey]) {
//		if ([selectedClipTypes containsObject:NSStringPboardType]) {
//			return YES;
//		}
//	}
//	
//	return NO;
//}

#pragma mark - StatusItem -

- (void)_changeStatusItem:(NSUInteger)tag
{
	[self _removeStatusItem];
	
	NSString *statusMenuIconName;
	
	switch (tag) {
		case 1:
			statusMenuIconName = STATUS_MENU_ICON;
			break;
		case 2:
			statusMenuIconName = @"StatusMenuIconFirst";
			break;
		case 3:
			statusMenuIconName = @"StatusMenuIconByDaveUlrich-scissors1-bw-left";
			break;
		case 4:
			statusMenuIconName = @"StatusMenuIconByDaveUlrich-scissors1-bw-right";
			break;
		case 5:
			statusMenuIconName = @"StatusMenuIconByDaveUlrich-scissors1-color-left";
			break;
		case 6:
			statusMenuIconName = @"StatusMenuIconByDaveUlrich-scissors1-color-right";
			break;
		case 7:
			statusMenuIconName = @"StatusMenuIconByDaveUlrich-diagonal-bw";
			break;
		case 8:
			statusMenuIconName = @"StatusMenuIconByDaveUlrich-diagonal-color";
			break;
		case 9:
			statusMenuIconName = @"StatusMenuIconByDaveUlrich-scissors2-bw-left";
			break;
		case 10:
			statusMenuIconName = @"StatusMenuIconByDaveUlrich-scissors2-bw-right";
			break;
		case 11:
			statusMenuIconName = @"StatusMenuIconByDaveUlrich-scissors2-color-left";
			break;
		case 12:
			statusMenuIconName = @"StatusMenuIconByDaveUlrich-scissors2-color-right";
			break;
		case 13:
			statusMenuIconName = @"StatusMenuIconBySuphiAksoy";
			break;
		default:
			/* default filename */
			statusMenuIconName = STATUS_MENU_ICON;
			break;
	}
	
	NSImage *statusIcon = [NSImage imageNamed:
						   [statusMenuIconName stringByAppendingString:STATUS_MENU_ICON_FILE_EXTENSION]];
	if (statusIcon == nil) {
		statusIcon = [NSImage imageNamed:STATUS_MENU_ICON];
	}
	if (floor(NSAppKitVersionNumber) > NSAppKitVersionNumber10_9) {
		[statusIcon setTemplate:YES];
	}
	
	NSString *toolTipLabel = [NSString stringWithFormat:@"%@ %@", kApplicationName, self.shortVersion];
	
	NSStatusBar *statusBar = [NSStatusBar systemStatusBar];
	
	statusItem = [[statusBar statusItemWithLength:NSVariableStatusItemLength] retain];
	[statusItem setImage:statusIcon];
	[statusItem setHighlightMode:YES];
	[statusItem setToolTip:toolTipLabel];
	
	if (clipMenu) {
		
		[statusItem setMenu:clipMenu];
	}
}

- (void)_removeStatusItem
{
	if (statusItem) {
		[[NSStatusBar systemStatusBar] removeStatusItem:statusItem];
		[statusItem release], statusItem = nil;		
	}
}

- (void)_refreshStatusItem
{
	if (statusItem) {
		[statusItem setMenu:clipMenu];
	}
}

#pragma mark - Icon -

- (NSImage *)_iconForPboardType:(NSString *)type
{			
	if (!type) {
		return nil;
	}
	
	NSString *key = [self _iconCacheKeyForType:type];
	if (!key) {
		return nil;
	}
	
	NSImage *icon = [self valueForKey:key];
	
	return icon;
}

- (NSString *)_iconCacheKeyForType:(NSString *)type
{
	if (!type) {
		return nil;
	}
	
	//	NSRange range = [type rangeOfString:@"NS"];
	//	NSMutableString *key = [NSMutableString stringWithString:type];
	//	[key replaceCharactersInRange:range withString:@"iconFor"];
	//		
	//	return key;
	
	if ([type isEqualToString:NSStringPboardType]) {
		return @"iconForStringPboardType";
	}
	else if ([type isEqualToString:NSRTFPboardType]) {
		return @"iconForRTFPboardType";
	}
	else if ([type isEqualToString:NSRTFDPboardType]) {
		return @"iconForRTFDPboardType";
	}
	else if ([type isEqualToString:NSPDFPboardType]) {
		return @"iconForPDFPboardType";
	} 
	else if ([type isEqualToString:NSFilenamesPboardType]) {
		return @"iconForFilenamesPboardType";
	}
	else if ([type isEqualToString:NSURLPboardType]) {
		return @"iconForURLPboardType";
	}
	else if ([type isEqualToString:NSTIFFPboardType] || [type isEqualToString:NSPICTPboardType]) {
		return @"iconForTIFFPboardType";
	}
	
	return nil;
}

- (NSImage *)_iconForSnippet
{
	return [self valueForKey:@"snippetIcon"];
}

- (void)_cacheIconForTypes
{
	NSArray *types = [Clip availableTypes];
	for (NSString *type in types) {
		NSImage *icon = [Clip fileTypeIconForPboardType:type];
		if (icon) {
			//			NSRange range = [type rangeOfString:@"NS"];
			//			NSMutableString *key = [NSMutableString stringWithString:type];
			//			[key replaceCharactersInRange:range withString:@"iconFor"];
			
			NSString *key = [self _iconCacheKeyForType:type];
			if (key) {
				[self setValue:icon forKey:key];
			}
		}
	}
}

- (void)_cacheFolderIcon
{
	//	[self _resetMenuIconSize];
	
	NSImage *icon = [[NSWorkspace sharedWorkspace] 
					 iconForFileType:NSFileTypeForHFSTypeCode(kGenericFolderIcon)];
	[icon setSize:NSMakeSize(menuIconSize,menuIconSize)];
	[self setFolderIcon:icon];
}

- (void)_cacheOpenFolderIcon
{
	NSImage *icon = [[NSWorkspace sharedWorkspace] 
					 iconForFileType:NSFileTypeForHFSTypeCode(kOpenFolderIcon)];
	[icon setSize:NSMakeSize(menuIconSize,menuIconSize)];
	[self setOpenFolderIcon:icon];
}

- (void)_cacheActionIcon
{
	NSString *imageResource = nil;
	switch (menuIconSize) {
		case SMALL_ICON_SIZE:
			imageResource = @"ActionIcon";
			break;
		case LARGE_ICON_SIZE:
			imageResource = @"ActionIconLarge";
			break;
		default:
			imageResource = @"ActionIconLarge";
			break;
	}
	
	NSString *fileName = [[NSBundle mainBundle] pathForImageResource:imageResource];
	if (fileName) {
		[self setActionIcon:[[[NSImage alloc] initWithContentsOfFile:fileName] autorelease]];
	}
}

- (void)_cacheJavaScriptIcon
{
	NSImage *icon = [[NSWorkspace sharedWorkspace] iconForFileType:@"js"];
	[icon setSize:NSMakeSize(menuIconSize,menuIconSize)];
	[self setJavaScriptIcon:icon];
}

- (void)_cacheSnippetIcon
{
	NSImage *icon = [[NSWorkspace sharedWorkspace]
					 iconForFileType:NSFileTypeForHFSTypeCode(kClippingTextTypeIcon)];
	[icon setSize:NSMakeSize(menuIconSize, menuIconSize)];
	[self setSnippetIcon:icon];
}

- (void)_resetMenuIconSize
{
	NSUInteger iconSize = [[NSUserDefaults standardUserDefaults] integerForKey:CMPrefMenuIconSizeKey];	
	[self setMenuIconSize:iconSize];
}

- (void)_resetIconCaches
{
	if ([[NSUserDefaults standardUserDefaults] boolForKey:CMPrefShowIconInTheMenuKey]) {
		[self _cacheIconForTypes];
		[self _resetMenuIconSize];
		
		[self _cacheFolderIcon];
		[self _cacheOpenFolderIcon];
		[self _cacheActionIcon];
		[self _cacheJavaScriptIcon];
		[self _cacheSnippetIcon];
	}
}

- (void)_unhighlightMenuItem
{
	[highlightedMenuItem setImage:folderIcon];
	[self setHighlightedMenuItem:nil];
}

#pragma mark - Notification -

- (void)_handlePreferencePanelWillClose:(NSNotification *)aNotification
{
	[self _resetIconCaches];
	
	NSUInteger showStatusItem = [[NSUserDefaults standardUserDefaults]
								 integerForKey:CMPrefShowStatusItemKey];
	if (showStatusItem) {
		[self updateStatusMenu];
	}
}

- (void)_handleSnippetEditorWillClose:(NSNotification *)aNotification
{	
	[self updateStatusMenu];
}

- (void)_handleStatusMenuWillUpdate:(NSNotification *)aNotification
{	
	[self updateStatusMenu];
}

@end

