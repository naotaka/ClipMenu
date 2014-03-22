//
//  MenuController.h
//  ClipMenu
//
//  Created by Naotaka Morimoto on 07/12/06.
//  Copyright 2007 Naotaka Morimoto. All rights reserved.
//

#import <Cocoa/Cocoa.h>

typedef enum {
	CMPopUpMenuTypeMain = 0,
	CMPopUpMenuTypeHistory,
	CMPopUpMenuTypeSnippets,
	CMPopUpMenuTypeActions,
} CMPopUpMenuType;

typedef enum {
	CMPositionOfSnippetsNone = 0,
	CMPositionOfSnippetsAboveClips,
	CMPositionOfSnippetsBelowClips
} CMPositionOfSnippets;

//extern NSString *const CMClipMenuWillPopUpNotification;
//extern NSString *const CMStatusMenuWillUpdateNotification;


@interface MenuController : NSObject <NSMenuDelegate>
{
	NSMenu *clipMenu;
	NSWindow *dummyWindow;
	NSStatusItem *statusItem;
	NSString *shortVersion;

	/* Menu Icons */
	NSImage *iconForStringPboardType;
	NSImage *iconForRTFPboardType;
	NSImage *iconForRTFDPboardType;
	NSImage *iconForPDFPboardType;
	NSImage *iconForFilenamesPboardType;
	NSImage *iconForURLPboardType;
	NSImage *iconForTIFFPboardType;
	
	
	/* - Action - */
	NSImage *folderIcon;
	NSImage *openFolderIcon;
	NSImage *actionIcon;
	NSImage *javaScriptIcon;
	NSImage *snippetIcon;
	
	NSUInteger menuIconSize;
	
	NSMenuItem *highlightedMenuItem;
}
@property (nonatomic, retain) NSMenu *clipMenu;
@property (nonatomic, retain) NSWindow *dummyWindow;
@property (nonatomic, retain) NSStatusItem *statusItem;
@property (nonatomic, copy) NSString *shortVersion;
@property (nonatomic, retain) NSImage *iconForStringPboardType;
@property (nonatomic, retain) NSImage *iconForRTFPboardType;
@property (nonatomic, retain) NSImage *iconForRTFDPboardType;
@property (nonatomic, retain) NSImage *iconForPDFPboardType;
@property (nonatomic, retain) NSImage *iconForFilenamesPboardType;
@property (nonatomic, retain) NSImage *iconForURLPboardType;
@property (nonatomic, retain) NSImage *iconForTIFFPboardType;
@property (nonatomic, retain) NSImage *folderIcon;
@property (nonatomic, retain) NSImage *openFolderIcon;
@property (nonatomic, retain) NSImage *actionIcon;
@property (nonatomic, retain) NSImage *javaScriptIcon;
@property (nonatomic, retain) NSImage *snippetIcon;
@property (nonatomic, assign) NSUInteger menuIconSize;
@property (nonatomic, retain) NSMenuItem *highlightedMenuItem;

+ (MenuController *)sharedInstance;

- (void)createStatusItem;
- (void)updateStatusMenu;
- (void)popUpMenuForType:(CMPopUpMenuType)type;

@end
