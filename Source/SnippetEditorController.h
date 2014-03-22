//
//  SnippetEditorController.h
//  ClipMenu
//
//  Created by naotaka on 08/10/30.
//  Copyright 2008 Naotaka Morimoto. All rights reserved.
//

#import <Cocoa/Cocoa.h>

#pragma mark Notifications
extern NSString *const CMSnippetEditorWillCloseNotification;


@class SnippetsController;
@class IndexedArrayController;
@class SeparatorCell;

@interface SnippetEditorController : NSWindowController <NSXMLParserDelegate>
{
	SnippetsController *snippetsController;
	NSImage *folderImage;
	NSImage *snippetImage;

	IBOutlet NSTreeController *folderTreeController;
	IBOutlet NSOutlineView *folderOutlineView;
	SeparatorCell *separatorCell;	// the cell used to draw a separator line in the outline view
	NSMutableArray *sourceList;
	NSArray *draggedNodes;		// used to keep track of dragged nodes
	NSIndexPath *lastSelectionIndexPath;
	
	IBOutlet IndexedArrayController *folderArrayController;
	IBOutlet IndexedArrayController *snippetArrayController;
	IBOutlet NSTableView *snippetTableView;
	
	/* Read XML */
	NSMutableArray *foldersFromFile;
	NSMutableString *currentElementContent;
	NSMutableDictionary *currentFolder;
	NSMutableDictionary *currentSnippet;
}
@property(nonatomic, retain) SnippetsController *snippetsController;
@property(nonatomic, retain) NSMutableArray *sourceList;
@property(nonatomic, retain) NSArray *draggedNodes;
@property(nonatomic, retain) NSIndexPath *lastSelectionIndexPath;
@property(nonatomic, retain) NSImage *folderImage;
@property(nonatomic, retain) NSImage *snippetImage;
@property(nonatomic, assign, readonly) BOOL hasFolders;

- (IBAction)addFolder:(id)sender;
- (IBAction)removeFolder:(id)sender;
- (IBAction)toggleFolderEnabled:(id)sender;
- (IBAction)addSnippet:(id)sender;
//- (IBAction)removeSnippet:(id)sender;
- (IBAction)toggleSnippetEnabled:(id)sender;

- (IBAction)importSnippets:(id)sender;
- (IBAction)exportSnippets:(id)sender;

/* path through snippetsController */
- (BOOL)saveStoreFile;

@end
