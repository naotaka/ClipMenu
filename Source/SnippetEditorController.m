//
//  SnippetEditorController.m
//  ClipMenu
//
//  Created by naotaka on 08/10/30.
//  Copyright 2008 Naotaka Morimoto. All rights reserved.
//

#import "SnippetEditorController.h"
#import "SnippetsController.h"
#import "constants.h"
#import "IndexedArrayController.h"
#import "FolderNode.h"
#import "ImageAndTextCell.h"
#import "SeparatorCell.h"
#import "NSIndexPath_Extensions.h"

#define GROUP_NAME @"GROUPS"
#define ADD_SNIPPET_IDENTIFIER @"AddSnippet"
#define DELETE_SNIPPET_IDENTIFIER @"DeleteSnippet"
#define CHECK_SNIPPET_IDENTIFIER @"CheckSnippet"

#define DEFAULT_EXPORT_FILENAME @"snippets"

#define kArrangedObjectsTitleKeyPath @"arrangedObjects.title"

#pragma mark Notifications
NSString *const CMSnippetEditorWillCloseNotification = @"CMSnippetEditorWillCloseNotification";


NSInteger compare(NSUInteger a, NSUInteger b)
{
	return (a < b) ? -1 : (a > b) ? 1 : 0;
}

NSUInteger numberOfLowerIndexes(NSIndexSet *indexes, NSUInteger currentIndex, NSUInteger row)
{
	NSUInteger count = 0;
	NSUInteger index = [indexes firstIndex];
	
	while (index != NSNotFound) {
		if (-1 < compare(currentIndex, row)) {
			count++;
		}
		index = [indexes indexGreaterThanIndex:index];
	}
	
	return count;
}


@interface SnippetEditorController ()
- (void)_prepareSourceList;
//- (void)selectParentFromSelection;
- (BOOL)isSpecialGroup:(FolderNode *)groupNode;
- (void)_expandGroups;
- (void)_cacheIconImages;
- (void)_moveUpDraggedObjects:(NSArray *)draggedObjects withIndexes:(NSIndexSet *)rowIndexes;
- (BOOL)_endEditingForWindow;

- (id)_rootTreeNodeForSnippetFolder;
- (NSArray *)_treeNodesForSnippetFolder;
- (NSInteger)_lastIndexOfSnippetFolders;
- (FolderNode *)_makeFolderNodeForFolder:(NSManagedObject *)folder;
- (FolderNode *)_makeFolderNodeWithIndex:(NSInteger)index;
- (void)_removeFolderNodes:(NSArray *)folderNodes;
- (void)_renumberAllFolders;
- (void)_renumberFoldersFromIndex:(NSUInteger)index;
- (void)_renumberSnippetsOfFolder:(NSManagedObject *)folder fromIndex:(NSUInteger)index;
- (void)_inspectAllFolders;				// for debug
- (void)_inspectAllSnippetsAtSelection;	// for debug

- (void)_parseXMLFileAtURL:(NSURL *)url;
- (void)_addImportedFolders:(NSArray *)folders;
- (void)_handleNSManagedObjectContextObjectsDidChange:(NSNotification *)aNotification;
@end

#pragma mark -

@implementation SnippetEditorController

@synthesize snippetsController;
@synthesize sourceList;
@synthesize draggedNodes;
@synthesize lastSelectionIndexPath;
@synthesize folderImage;
@synthesize snippetImage;

- (id)init
{
	self = [super initWithWindowNibName:@"SnippetEditor"];
	if (self == nil) {
		return nil;
	}
	
	[self setSnippetsController:[SnippetsController sharedInstance]];
	[self _prepareSourceList];
	[self _cacheIconImages];
	
	return self;
}

- (void)dealloc
{
//	[[NSNotificationCenter defaultCenter] removeObserver:self];
	
	[sourceList release], sourceList = nil;
	[snippetsController release], snippetsController = nil;
	[folderImage release], folderImage = nil;
	[snippetImage release], snippetImage = nil;
	[separatorCell release], separatorCell = nil;
	[lastSelectionIndexPath release], lastSelectionIndexPath = nil;
	
	self.draggedNodes = nil;
	
	[super dealloc];
}

- (void)awakeFromNib
{	
	/* Cell */
	separatorCell = [[SeparatorCell alloc] init];
	[separatorCell setEnabled:NO];
	
	[self _expandGroups];
	
	/* Drag and Drop */
	NSArray *draggedDataTypes = [NSArray arrayWithObject:kDraggedDataType];
	[folderOutlineView registerForDraggedTypes:draggedDataTypes];
	[folderOutlineView setDraggingSourceOperationMask:(NSDragOperationMove)
											 forLocal:YES];
	[snippetTableView registerForDraggedTypes:draggedDataTypes];
	[snippetTableView setDraggingSourceOperationMask:(NSDragOperationMove)
											forLocal:YES];
	
//	/* Notification */
//	// Avoid a problem doesn't update tableView
//	[[NSNotificationCenter defaultCenter] addObserver:self
//											 selector:@selector( _handleNSManagedObjectContextObjectsDidChange: )
//												 name:NSManagedObjectContextObjectsDidChangeNotification
//											   object:nil];
	
	/* Snippet title was changed */
	[snippetArrayController addObserver:self
							 forKeyPath:kArrangedObjectsTitleKeyPath
								options:NSKeyValueObservingOptionNew
								context:nil];
}

#pragma mark -
#pragma mark Accessors

- (NSMutableArray *)sourceList
{
	return sourceList;
}

- (BOOL)hasFolders
{
	return [[folderArrayController arrangedObjects] count];
}

#pragma mark -
#pragma mark Override

- (void)windowDidLoad
{
	[super windowDidLoad];
	[self.window setCollectionBehavior:NSWindowCollectionBehaviorCanJoinAllSpaces];
}

- (IBAction)showWindow:(id)sender 
{
//	NSLog(@"showWindow");
	
	[super showWindow:sender];
	[self.window center];
	[NSApp activateIgnoringOtherApps:YES];
	[self.window makeKeyAndOrderFront:self];
	
	if (self.lastSelectionIndexPath) {
		[folderTreeController setSelectionIndexPath:self.lastSelectionIndexPath];
	}
	
	/* Notification */
	// Avoid a problem doesn't update tableView
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector( _handleNSManagedObjectContextObjectsDidChange: )
												 name:NSManagedObjectContextObjectsDidChangeNotification
											   object:snippetsController.managedObjectContext];
}

#pragma mark -
#pragma mark KVO

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
//	NSLog(@"observeValueForKeyPath: %@, object: %@", keyPath, object);
	
	if ([object isEqualTo:snippetArrayController] && 
		[keyPath isEqualToString:kArrangedObjectsTitleKeyPath]) {	// prevent empty snippet's content
//		NSLog(@"%@", [object valueForKeyPath:@"selection"]);
		
		id selected = [object valueForKeyPath:@"selection"];
		NSString *title = [selected valueForKeyPath:kTitle];
		if ((title == NSNoSelectionMarker) ||
			(title == NSNotApplicableMarker) ||
			(title == NSMultipleValuesMarker)) {
//			NSLog(@"NO");	// temp!!!
			return;
		}
		NSString *content = [selected valueForKeyPath:kContent];
		if ([content length] == 0 &&
			![title isEqualToString:NSLocalizedString(@"untitled snippet", nil)]) {
//			NSLog(@"Empty");	// temp!!!
			[selected setValue:title forKey:kContent];
		}
		
//		NSLog(@"title: %@", [selected valueForKeyPath:kTitle]);
//		NSLog(@"content: %@", [selected valueForKeyPath:kContent]);
	}
}

#pragma mark -
#pragma mark Delegate

#pragma mark - NSControl -

/* This method brings a glitch to the pref panel. */
//- (void)controlTextDidEndEditing:(NSNotification *)aNotification
//{
////	NSLog(@"controlTextDidEndEditing: %@", aNotification);
//	
//	if ([[aNotification object] isEqualTo:snippetTableView]) {	// prevent empty snippet's content
//		NSDictionary *userInfo = [aNotification userInfo];
////		NSLog(@"controlTextDidEndEditing: %@", userInfo);
//		
//		NSInteger textMovement = [[userInfo objectForKey:@"NSTextMovement"] integerValue];
//		if (textMovement == NSTabTextMovement) {
//			return;
//		}
//		
//		NSString *title = [[[[userInfo objectForKey:@"NSFieldEditor"] string] copy] autorelease];		
//		NSInteger index = [snippetTableView selectedRow];
//		NSManagedObject *snippet = [[snippetArrayController arrangedObjects] objectAtIndex:index];
//		
//		if ([[snippet valueForKey:kContent] length] == 0) {
//			[snippet setValue:title forKey:kContent];
//		}
//	}
//}

// -------------------------------------------------------------------------------
//	textShouldEndEditing:
// -------------------------------------------------------------------------------
- (BOOL)control:(NSControl *)control textShouldEndEditing:(NSText *)fieldEditor
{
	if ([[fieldEditor string] length] == 0)
	{
		// don't allow empty node names
		return NO;
	}
	else
	{
		return YES;
	}
}

#pragma mark - NSWindow -

- (void)windowWillClose:(NSNotification *)aNotification
{
	[[NSNotificationCenter defaultCenter] removeObserver:self
													name:NSManagedObjectContextObjectsDidChangeNotification
												  object:snippetsController.managedObjectContext];

	/* Window */
	NSWindow *window = [self window];
	if (![window makeFirstResponder:window]) {
		[window endEditingFor:nil];
	}
	[NSApp deactivate];
	
	/* Keep last selectionIndexPath 
	   (Avoid HIToolbox: ignoring exception 'CoreData could not fulfill a fault for XXX that raised inside Carbon event dispatch) */
	self.lastSelectionIndexPath = [folderTreeController selectionIndexPath];	
	[folderTreeController setSelectionIndexPath:nil];
	
	/* Save snippets */		
	[self saveStoreFile];
	
	/* Send Notification */
	[[NSNotificationCenter defaultCenter] postNotificationName:CMSnippetEditorWillCloseNotification
														object:nil];
}

- (NSUndoManager *)windowWillReturnUndoManager:(NSWindow *)window
{
//	NSLog(@"windowWillReturnUndoManager: %@", [snippetsController.managedObjectContext undoManager]);
	
    return [snippetsController.managedObjectContext undoManager];
}

#pragma mark - NSToolbarItemValidation Protocol -

- (BOOL)validateToolbarItem:(NSToolbarItem *)theItem
{
	NSString *itemIdentifier = [theItem itemIdentifier];
	
	if ([itemIdentifier isEqualToString:ADD_SNIPPET_IDENTIFIER]) {
		return (0 < [[folderTreeController selectedNodes] count]);
	}
	else if ([itemIdentifier isEqualToString:CHECK_SNIPPET_IDENTIFIER]) {
		return (0 < [[snippetArrayController selectedObjects] count]);
	}
	
	return YES;
}

#pragma mark - NSOutlineViewDelegate Protocol -

- (BOOL)outlineView:(NSOutlineView *)outlineView shouldSelectItem:(id)item;
{
	// don't allow special group nodes (Devices and Places) to be selected
	FolderNode* node = [item representedObject];
	return (![self isSpecialGroup:node]);
}

- (NSCell *)outlineView:(NSOutlineView *)outlineView dataCellForTableColumn:(NSTableColumn *)tableColumn item:(id)item
{
	NSCell* returnCell = [tableColumn dataCell];
	
	if ([[tableColumn identifier] isEqualToString:kImageAndTextCellColumn])
	{
		// we are being asked for the cell for the single and only column
		FolderNode* node = [item representedObject];
		if ([node nodeIcon] == nil && [[node nodeTitle] length] == 0)
			returnCell = separatorCell;
	}
	
	return returnCell;
}

// -------------------------------------------------------------------------------
//	shouldEditTableColumn:tableColumn:item
//
//	Decide to allow the edit of the given outline view "item".
// -------------------------------------------------------------------------------
- (BOOL)outlineView:(NSOutlineView *)outlineView shouldEditTableColumn:(NSTableColumn *)tableColumn item:(id)item
{
	BOOL result = YES;
	
	item = [item representedObject];
	if ([self isSpecialGroup:item])
	{
		result = NO; // don't allow special group nodes to be renamed
	}
	else
	{
		if ([[item urlString] isAbsolutePath]) {
			result = NO;	// don't allow file system objects to be renamed
		}
	}
	
	return result;
}

- (void)outlineView:(NSOutlineView *)outlineView willDisplayCell:(NSCell*)cell forTableColumn:(NSTableColumn *)tableColumn item:(id)item
{	 
	if ([[tableColumn identifier] isEqualToString:kImageAndTextCellColumn])
	{
		// we are displaying the single and only column
		if ([cell isKindOfClass:[ImageAndTextCell class]])
		{
			item = [item representedObject];
			if (item)
			{				
				if ([item isLeaf])
				{
					[item setNodeIcon:folderImage];
					
//					BOOL isEnabled = [item isEnabled];
//					NSLog(@"isEnabled: %d", isEnabled);
//					[cell setEnabled:isEnabled];
////					NSLog(@"cell: %d", [cell isEnabled]);

//					// does it have a URL string?
//					NSString *urlStr = [item urlString];
//					if (urlStr)
//					{
//						if ([item isLeaf])
//						{
//							[item setNodeIcon:snippetImage];
//						}
//						else
//						{
//							[item setNodeIcon:folderImage];
//						}
//					}
//					else
//					{
//						// it's a separator, don't bother with the icon
//					}
				}
				else
				{
					// check if it's a special folder (DEVICES or PLACES), we don't want it to have an icon
					if ([self isSpecialGroup:item])
					{
						[item setNodeIcon:nil];
					}
					else
					{
						// it's a folder, use the folderImage as its icon
						[item setNodeIcon:folderImage];
					}
				}
			}
			
			// set the cell's image
			[(ImageAndTextCell*)cell setImage:[item nodeIcon]];
			
			BOOL isEnabled = [item isEnabled];
//			NSLog(@"%@ isEnabled: %d, %d", [item nodeTitle], isEnabled, [cell isHighlighted]);
			[cell setEnabled:isEnabled];
		}
	}
}

-(BOOL)outlineView:(NSOutlineView*)outlineView isGroupItem:(id)item
{
	if ([self isSpecialGroup:[item representedObject]])
	{
		return YES;
	}
	else
	{
		return NO;
	}
}

//- (void)outlineViewItemDidCollapse:(NSNotification *)notification
//{
////	NSLog(@"collapse: %@", notification);	
////	NSLog(@"%@", [folderTreeController selectionIndexPath]);
//	
//	[addSnippetToolbarItem setEnabled:YES];
//}

#pragma mark - NSOutlineViewDataSource Protocol -

- (BOOL)outlineView:(NSOutlineView *)outlineView writeItems:(NSArray *)items toPasteboard:(NSPasteboard *)pboard
{
//	NSLog(@"items: %@", items);
	
	NSArray *draggedTypes = [NSArray arrayWithObject:kDraggedDataType];
	[pboard declareTypes:draggedTypes owner:self];
	
	self.draggedNodes = items;
	
	return YES;
}

- (NSDragOperation)outlineView:(NSOutlineView *)outlineView validateDrop:(id < NSDraggingInfo >)info proposedItem:(id)item proposedChildIndex:(NSInteger)index
{
//	NSLog(@"validateDrop: %@, item: %@, childIndex: %d", info, [[item representedObject] nodeTitle], index);
	
	NSPasteboard *pboard = [info draggingPasteboard];
	NSArray *draggedTypes = [NSArray arrayWithObject:kDraggedDataType];
	
	if (![pboard availableTypeFromArray:draggedTypes]) {
		return NSDragOperationNone;
	}
	
	id draggindSource = [info draggingSource];
	
	if ((draggindSource == outlineView) &&
		(index != NSOutlineViewDropOnItemIndex)) {
		if (![item indexPath]) {
			/* Not move to root path */
			return NSDragOperationNone;
		}
		return NSDragOperationMove;
	}
	else if ((draggindSource == snippetTableView) &&
			 (index == NSOutlineViewDropOnItemIndex)) {
		if (![[item representedObject] folder]) {
			/* Not drag to root folder */
			return NSDragOperationNone;
		}
		return NSDragOperationGeneric;
	}
	
	return NSDragOperationNone;
}

- (BOOL)outlineView:(NSOutlineView *)outlineView acceptDrop:(id < NSDraggingInfo >)info item:(id)item childIndex:(NSInteger)index
{
//	NSLog(@"acceptDrop item: %@, childIndex: %d", [[item representedObject] nodeTitle], index);
	
	id draggingSource = [info draggingSource];
	
	if (draggingSource == outlineView) {
		if (self.draggedNodes == nil || ![self.draggedNodes count]) {
			return NO;
		}
		
		NSArray *treeNodes = self.draggedNodes;
		[draggedNodes release], draggedNodes = nil;
		
		NSIndexPath *targetIndexPath;
		
		if (item) {
			targetIndexPath = [[item indexPath] indexPathByAddingIndex:index];
		}
		else {
			targetIndexPath = [NSIndexPath indexPathWithIndex:index];
		}
//		NSLog(@"targetIndexPath: %@", targetIndexPath);
		
		NSIndexPath *draggedNodeIndexPath = [[treeNodes objectAtIndex:0] indexPath];
		
		if ([draggedNodeIndexPath compare:targetIndexPath] == NSOrderedSame) {
			return NO;
		}
		
		NSUInteger draggedNodeIndex = [draggedNodeIndexPath lastIndex];
		NSUInteger lowerIndex = (index < draggedNodeIndex) ? index : draggedNodeIndex;
		
		[folderTreeController moveNodes:treeNodes toIndexPath:targetIndexPath];
		[self _renumberFoldersFromIndex:lowerIndex];
		
//		[self _inspectAllFolders];		// temp!!!
	}
	else if (draggingSource == snippetTableView) {
		/* drag snippets to a folder */			
		NSPasteboard *pboard = [info draggingPasteboard];
		NSData *data = [pboard dataForType:kDraggedDataType];
		NSIndexSet *rowIndexes = [NSKeyedUnarchiver unarchiveObjectWithData:data];
		[snippetArrayController setSelectionIndexes:rowIndexes];
//		NSLog(@"rowIndexes: %@", rowIndexes);
		
		NSArray *selectedObjects = [snippetArrayController selectedObjects];
		
		if (![selectedObjects count]) {
			return NO;
		}
		
		NSManagedObject *firstSnippet = [selectedObjects objectAtIndex:0];
		NSUInteger indexOfFirstSnippet = [[firstSnippet valueForKey:kIndex] unsignedIntegerValue];
		NSManagedObject *sourceFolder = [firstSnippet valueForKey:kFolder];
//		NSLog(@"indexOfFirstSnippet: %d", indexOfFirstSnippet);
//		NSLog(@"sourceFolder: %@", sourceFolder);
		
		FolderNode *destFolderNode = [item representedObject];	
		NSManagedObject *destFolder = [destFolderNode folder];
		NSInteger snippetsCount = [[destFolder valueForKeyPath:@"snippets.@count"] integerValue];
//		NSLog(@"folder: %@", folder);
		
		/* Move snippets to destination folder */
		for (NSManagedObject *snippet in selectedObjects) {
			[snippet setValue:destFolder forKey:kFolder];
			[snippet setValue:[NSNumber numberWithInteger:snippetsCount] forKey:kIndex];
			snippetsCount++;
		}
				
		[folderTreeController rearrangeObjects];
		
		[self _renumberSnippetsOfFolder:sourceFolder fromIndex:indexOfFirstSnippet];
		
//		[self _inspectAllSnippetsAtSelection];		// temp!!!
	}
	
	return YES;
}

#pragma mark - NSTableView -

- (void)tableView:(NSTableView *)aTableView willDisplayCell:(id)aCell forTableColumn:(NSTableColumn *)aTableColumn row:(NSInteger)rowIndex
{	
	if ([[aTableColumn identifier] isEqualToString:kImageAndTextCellColumn]) {
		// we are displaying the single and only column
		if ([aCell isKindOfClass:[ImageAndTextCell class]]) {
			NSImage *icon = nil;
			
			if (aTableView == snippetTableView) {
				icon = snippetImage;
			}
			else {
				// it's a folder, use the folderImage as its icon
				icon = folderImage;
			}
			
			// set the cell's image
			[(ImageAndTextCell *)aCell setImage:icon];
		}
	}
}

#pragma mark - NSTableViewDataSource protocol - 

- (BOOL)tableView:(NSTableView *)aTableView writeRowsWithIndexes:(NSIndexSet *)rowIndexes toPasteboard:(NSPasteboard *)pboard
{
	//	NSLog(@"aTableView: %@", aTableView);
	
	NSArray *draggedTypes = [NSArray arrayWithObject:kDraggedDataType];
	[pboard declareTypes:draggedTypes owner:self];
	
	NSData *data = [NSKeyedArchiver archivedDataWithRootObject:rowIndexes];
	[pboard setData:data forType:kDraggedDataType];
	return YES;
}

- (NSDragOperation)tableView:(NSTableView *)aTableView validateDrop:(id < NSDraggingInfo >)info proposedRow:(NSInteger)row proposedDropOperation:(NSTableViewDropOperation)operation
{
	//	NSLog(@"validate drop: %d", operation);
	
	NSPasteboard *pboard = [info draggingPasteboard];
	NSArray *draggedTypes = [NSArray arrayWithObject:kDraggedDataType];
	id draggingSource = [info draggingSource];
	
	if ([pboard availableTypeFromArray:draggedTypes]) {		
		if (aTableView == draggingSource) {
			if (operation == NSTableViewDropAbove) {
				return NSDragOperationMove;
			}
		}
		else if (draggingSource == snippetTableView
				 && operation == NSTableViewDropOn) {
			return NSDragOperationGeneric;
			//			return NSDragOperationEvery;
		}
	}
	
	return NSDragOperationNone;
}

- (BOOL)tableView:(NSTableView *)aTableView acceptDrop:(id < NSDraggingInfo >)info row:(NSInteger)row dropOperation:(NSTableViewDropOperation)operation
{
	id draggingSource = [info draggingSource];
	
	NSPasteboard *pboard = [info draggingPasteboard];
	NSData *data = [pboard dataForType:kDraggedDataType];
	NSIndexSet *rowIndexes = [NSKeyedUnarchiver unarchiveObjectWithData:data];
//	NSLog(@"rowIndexes: %@", rowIndexes);
	[snippetArrayController setSelectionIndexes:rowIndexes];
	
	NSArray *arrangedObjects = [snippetArrayController arrangedObjects];
	NSArray *draggedObjects = [snippetArrayController selectedObjects];
	
	if (aTableView == draggingSource) {
		if (row == [rowIndexes firstIndex]) {
			return NO;
		}
		
//		[snippetArrayController setAutomaticallyRearrangesObjects:NO];
		
		NSUInteger first = (row < [rowIndexes firstIndex]) ? row : [rowIndexes firstIndex];
		NSUInteger last = (row > [rowIndexes lastIndex]) ? row : [rowIndexes lastIndex];
//		NSLog(@"first: %d, last: %d, row: %d", first, last, row);
		
		NSUInteger index = first;
		NSUInteger upperThanRowCount = 0;
		while (index != NSNotFound) {
//			NSLog(@"index: %d", index);
			id object = [arrangedObjects objectAtIndex:index];
			NSUInteger oldIndex = [[object valueForKey:kIndex] unsignedIntegerValue];
			
			if (compare(oldIndex, row) == -1) {
				upperThanRowCount++;
			}
			
			index = [rowIndexes indexGreaterThanIndex:index];
		}
//		NSLog(@"upperThanRowCount: %d", upperThanRowCount);	
		
		/* numbering non dragged objects */
		NSUInteger newIndex = 0;
		if (0 < first) {
			newIndex = [[[arrangedObjects objectAtIndex:first] valueForKey:kIndex] unsignedIntegerValue];
		}
//		NSLog(@"newIndex: %d", newIndex);
		
		[snippetArrayController setAutomaticallyRearrangesObjects:NO];
		
		for (NSUInteger i = first; i < last; i++) {
			NSUInteger lowerCount = 0;			
			if ([rowIndexes containsIndex:i]) {
//				NSLog(@"rowIndexes contains %d", i);	
				continue;
			}
			
			if (row <= i) {
				lowerCount = numberOfLowerIndexes(rowIndexes, i, row);
//				NSLog(@"lowerCount: %d", lowerCount);
			}
			
			id object = [arrangedObjects objectAtIndex:i];
//			NSLog(@"object: %@", object);
//			NSLog(@"newIndex: %d", newIndex);
			[object setValue:[NSNumber numberWithUnsignedInteger:newIndex+lowerCount] forKey:kIndex];
			newIndex++;
		}
		
		/* numbering dragged objects */		
		NSUInteger i = row - upperThanRowCount;
		for (id object in draggedObjects) {
//			NSLog(@"dragged object: %d", i);
			[object setValue:[NSNumber numberWithUnsignedInteger:i] forKey:kIndex];
			i++;
		}
		
		/* after move up */
		if (row < first) {
			newIndex = row + [rowIndexes count];
			for (NSUInteger i = row; i < last; i++) {	
				if ([rowIndexes containsIndex:i]) {
//					NSLog(@"rowIndexes contains %d", i);
					continue;
				}
				
				id object = [arrangedObjects objectAtIndex:i];
				[object setValue:[NSNumber numberWithUnsignedInteger:newIndex] forKey:kIndex];
				newIndex++;
			}
		}
		
		[snippetArrayController setAutomaticallyRearrangesObjects:YES];
	}
	
	//	[sourceArrayController renumber];
	return YES;
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)aTableView
{
	return 0;
}

#pragma mark - NSXMLParser -

- (void)parser:(NSXMLParser *)parser didStartElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qualifiedName attributes:(NSDictionary *)attributeDict
{
	//	NSLog(@"didStartElement: %@", elementName);
	
	if (currentElementContent) {
		[currentElementContent release];
	}
	currentElementContent = [[NSMutableString alloc] init];
	
	if ([elementName isEqualToString:kRootElement]) {
		if (foldersFromFile) {
			[foldersFromFile release];
		}
		foldersFromFile = [[NSMutableArray alloc] init];
	}
	else if ([elementName isEqualToString:kFolderElement]) {
		if (currentFolder) {
			[currentFolder release];
		}
		currentFolder = [[NSMutableDictionary alloc] initWithObjectsAndKeys:
						 kFolderElement, kType,
						 [NSMutableArray array], kSnippets,
						 nil];
	}
	else if ([elementName isEqualToString:kSnippetElement]) {
		if (currentSnippet) {
			[currentSnippet release];
		}
		currentSnippet = [[NSMutableDictionary alloc] initWithObjectsAndKeys:
						  kSnippetElement, kType,
						  nil];
	}
}

- (void)parser:(NSXMLParser *)parser foundCharacters:(NSString *)string
{
	//	NSLog(@"string: %@", string);
	[currentElementContent appendString:string];
}

- (void)parser:(NSXMLParser *)parser didEndElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName
{
	//	NSLog(@"didEndElement: %@", elementName);
	
	/* Collection */
	if ([elementName isEqualToString:kFolderElement]) {
		[foldersFromFile addObject:currentFolder];
		[currentFolder release], currentFolder = nil;
		return;
	}
	else if ([elementName isEqualToString:kSnippetElement]) {
		[[currentFolder objectForKey:kSnippets] addObject:currentSnippet];
		[currentSnippet release], currentSnippet = nil;
		return;
	}
	
	/* Characters */
	if ([elementName isEqualToString:kTitleElement]) {
		if (!currentElementContent) {
			return;
		}
		NSMutableDictionary *currentItem = (currentSnippet) ? currentSnippet : currentFolder;
		[currentItem setObject:currentElementContent forKey:elementName];
	}
	else if ([elementName isEqualToString:kContentElement]) {
		if (!currentElementContent) {
			return;
		}
		[currentSnippet setObject:currentElementContent forKey:elementName];
	}
	
	[currentElementContent release], currentElementContent = nil;
}

#pragma mark -
#pragma mark Actions

- (IBAction)addFolder:(id)sender
{
	if (![self _endEditingForWindow]) {
		return;
	}
		
	NSInteger lastIndex = [self _lastIndexOfSnippetFolders];
	lastIndex++;
	FolderNode *newNode = [self _makeFolderNodeWithIndex:lastIndex];
	
	NSUInteger indexes[2] = {0, lastIndex};
	NSIndexPath *indexPath = [NSIndexPath indexPathWithIndexes:indexes length:2];
	[folderTreeController insertObject:newNode atArrangedObjectIndexPath:indexPath];
	
	NSInteger columnIndex = 0;
	NSInteger rowIndex = lastIndex + 1;
	[folderOutlineView editColumn:columnIndex
							  row:rowIndex
						withEvent:nil
						   select:YES];
}

- (IBAction)removeFolder:(id)sender
{	
	NSArray *selectedObjects = [folderTreeController selectedObjects];
	NSArray *selectionIndexPaths = [folderTreeController selectionIndexPaths];
	
//	NSLog(@"selection: %@", selectionIndexPaths);
	
	if ([selectionIndexPaths count] == 0) {
		return;
	}
	
	NSUInteger indexToRemove = [[selectionIndexPaths objectAtIndex:0] indexAtPosition:1];
//	NSLog(@"indexToRemove: %d", indexToRemove);
	
	[self _removeFolderNodes:selectedObjects];
	[folderTreeController removeObjectsAtArrangedObjectIndexPaths:selectionIndexPaths];
	
	[self _renumberFoldersFromIndex:indexToRemove];
}

- (IBAction)toggleFolderEnabled:(id)sender
{
//	NSLog(@"toggleFolderEnabled: %@", [folderTreeController selectedNodes]);
	
	NSArray *selectedObjects = [folderTreeController selectedObjects];
	
	if (![selectedObjects count]) {
		return;
	}
	
	BOOL isEnabled = [[selectedObjects objectAtIndex:0] isEnabled];
	
	for (FolderNode *folderNode in selectedObjects) {
		[folderNode setIsEnabled:!isEnabled];
	}
	
//	[self _inspectAllFolders];
	
//	NSIndexSet *indexes = [folderOutlineView selectedRowIndexes];

	/* Deselect all to avoid a display glitch */
	[folderOutlineView deselectAll:self];
	
//	[folderOutlineView selectRowIndexes:indexes byExtendingSelection:YES];
	
//	NSUInteger index = [indexes firstIndex];
//	
//	while (index != NSNotFound) {
//		NSRect rect = [folderOutlineView rectOfRow:index];
//		[folderOutlineView drawRow:index clipRect:rect];
//		index = [indexes indexGreaterThanIndex:index];
//	}
	
	[folderOutlineView display];
}

- (IBAction)addSnippet:(id)sender
{
	[self _endEditingForWindow];
	
	NSManagedObject *managedObject = [snippetArrayController newObject];
//	NSLog(@"managedObject: %@", managedObject);
	[snippetArrayController addObject:managedObject];
	
	NSArray *arrangedObjects = [snippetArrayController arrangedObjects];
	NSInteger rowIndex = [arrangedObjects indexOfObject:managedObject];
//	NSLog(@"starting edit of %@ in rowIndex %d", managedObject, rowIndex);
	[managedObject release], managedObject = nil;
	
	NSInteger columnIndex = 0;					// the 'title' column
	[snippetTableView editColumn:columnIndex
							 row:rowIndex
					   withEvent:nil
						  select:YES];
}

//- (IBAction)removeSnippet:(id)sender
//{
//	NSManagedObjectContext *moc = [snippetsController managedObjectContext];
//	NSArray *selectedObjects = [snippetArrayController selectedObjects];
//	[snippetArrayController removeObjects:selectedObjects];
//	
//	for (NSManagedObject *snippet in selectedObjects) {
//		[moc deleteObject:snippet];
//	}
//}

- (IBAction)toggleSnippetEnabled:(id)sender
{
	NSArray *selectedObjects = [snippetArrayController selectedObjects];
	
	if (![selectedObjects count]) {
		return;
	}
	
//	NSLog(@"selectedObjects: %@", selectedObjects);
	
	BOOL isEnabled = [[[selectedObjects objectAtIndex:0] valueForKey:kEnabled] boolValue];
	NSNumber *newEnabled = [NSNumber numberWithBool:!isEnabled];
//	NSLog(@"isEnabled: %d", isEnabled);
	
	for (NSManagedObject *snippet in selectedObjects) {
		[snippet setValue:newEnabled forKey:kEnabled];
	}
}

- (IBAction)importSnippets:(id)sender
{
	NSArray *fileTypes = [NSArray arrayWithObject:kXMLFileType];
	NSOpenPanel *openPanel = [NSOpenPanel openPanel];
	[openPanel setAllowsMultipleSelection:NO];
	
	NSInteger returnCode;
	
	if ([openPanel respondsToSelector:@selector( setDirectoryURL: )]) {
		[openPanel setDirectoryURL:[NSURL fileURLWithPath:NSHomeDirectory()]];
		[openPanel setAllowedFileTypes:fileTypes];
		returnCode = [openPanel runModal];
	}
	else {
		/* Deprecated in Mac OS X 10.6 */
		returnCode = [openPanel runModalForDirectory:NSHomeDirectory() 
											   file:nil
											  types:fileTypes];
	}
	
	if (returnCode != NSOKButton) {
		return;
	}
	
	NSArray *fileURLs = [openPanel URLs];
	
	if (![fileURLs count]) {
		return;
	}
	
	NSURL *url = [fileURLs objectAtIndex:0];
	
	if (!url) {
		return;
	}
	
	[self _parseXMLFileAtURL:url];
	
	if (foldersFromFile) {
//		NSLog(@"parsed: %@", foldersFromFile);
		[self _addImportedFolders:foldersFromFile];
		[foldersFromFile release], foldersFromFile = nil;
	}
}

- (IBAction)exportSnippets:(id)sender
{
	NSSortDescriptor *descriptor = [[NSSortDescriptor alloc] initWithKey:kIndex ascending:YES];
	NSArray *sortDescriptors = [NSArray arrayWithObject:descriptor];
	[descriptor release], descriptor = nil;
	
	NSArray *arrangedObjects = [folderArrayController arrangedObjects];
//	NSLog(@"arrangedObjects: %@", arrangedObjects);
	
	arrangedObjects = [arrangedObjects sortedArrayUsingDescriptors:sortDescriptors];
	
	NSXMLElement *rootElement = (NSXMLElement *)[NSXMLNode elementWithName:kRootElement];
	
	for (NSManagedObject *folder in arrangedObjects) {		
		NSString *folderTitle = [folder valueForKey:kTitle];
		NSArray *snippets = [[[folder valueForKey:kSnippets] allObjects] sortedArrayUsingDescriptors:sortDescriptors];
		
		NSXMLElement *folderElement = (NSXMLElement *)[NSXMLNode elementWithName:kFolderElement];
		
		[folderElement addChild:[NSXMLNode elementWithName:kTitleElement stringValue:folderTitle]];
		
		NSXMLElement *snippetsElement = (NSXMLElement *)[NSXMLNode elementWithName:kSnippetsElement];
		
		for (NSManagedObject *snippet in snippets) {
			NSString *snippetTitle = [snippet valueForKey:kTitle];
			NSString *content = [snippet valueForKey:kContent];
			
			NSXMLElement *snippetElement = (NSXMLElement *)[NSXMLNode elementWithName:kSnippetElement];
			[snippetElement addChild:[NSXMLNode elementWithName:kTitleElement stringValue:snippetTitle]];
			
			NSXMLElement *contentElement = [[NSXMLNode alloc] initWithKind:NSXMLElementKind
																   options:NSXMLNodePreserveWhitespace];
			[contentElement setName:kContentElement];
			[contentElement setStringValue:content];
			
			[snippetElement addChild:contentElement];
			[contentElement release], contentElement = nil;
			
			[snippetsElement addChild:snippetElement];
		}
		
		[folderElement addChild:snippetsElement];
		[rootElement addChild:folderElement];
	}
	
	NSXMLDocument *xmlDocument = [[[NSXMLDocument alloc] initWithRootElement:rootElement] autorelease];
	[xmlDocument setVersion:@"1.0"];
	[xmlDocument setCharacterEncoding:@"UTF-8"];
	
	//	NSLog(@"xml: %@", xmlDocument);
	
	NSSavePanel *savePanel = [NSSavePanel savePanel];
	[savePanel setAccessoryView:nil];
	[savePanel setCanSelectHiddenExtension:YES];
	[savePanel setRequiredFileType:kXMLFileType];
	
	NSInteger returnCode;
	
	if ([savePanel respondsToSelector:@selector( setDirectoryURL: )]) {
		[savePanel setDirectoryURL:[NSURL fileURLWithPath:NSHomeDirectory()]];
		[savePanel setNameFieldStringValue:DEFAULT_EXPORT_FILENAME];
		returnCode = [savePanel runModal];
	}
	else {
		/* Deprecated in Mac OS X 10.6 */
		returnCode = [savePanel runModalForDirectory:NSHomeDirectory() file:DEFAULT_EXPORT_FILENAME];
	}
	
	if (returnCode == NSOKButton) {
		NSData *data = [xmlDocument XMLDataWithOptions:NSXMLNodePrettyPrint];
		if (![data writeToFile:[savePanel filename] atomically:YES]) {
			NSBeep();
			NSRunAlertPanel(nil, 
							NSLocalizedString(@"Could not write document out...", nil), 
							NSLocalizedString(@"OK", nil), 
							nil, 
							nil);
			return;
		}
	}
}

#pragma mark -
#pragma mark Public

/* path through snippetsController */
- (BOOL)saveStoreFile
{
	return [snippetsController saveStoreFile];
}

#pragma mark -
#pragma mark Private

- (void)_prepareSourceList
{
	NSMutableArray *children = [[NSMutableArray alloc] init];
	FolderNode *node;
	
	for (NSManagedObject *folder in [snippetsController folders]) {
		node = [[FolderNode alloc] initLeaf];		// doesn't contain children
		[node setNodeTitle:[folder valueForKey:kTitle]];
		[node setFolder:folder];
		[children addObject:node];
		[node release], node = nil;
	}
	
	FolderNode *rootNode = [[FolderNode alloc] init];
	[rootNode setNodeTitle:GROUP_NAME];
	[rootNode setChildren:children];
	[children release], children = nil;
	
	[self willChangeValueForKey:@"sourceList"];
	self.sourceList = [NSMutableArray arrayWithObject:rootNode];
	[self didChangeValueForKey:@"sourceList"];

	[rootNode release], rootNode = nil;
}

//// -------------------------------------------------------------------------------
////	selectParentFromSelection:
////
////	Take the currently selected node and select its parent.
//// -------------------------------------------------------------------------------
//- (void)selectParentFromSelection
//{
//	if ([[folderTreeController selectedNodes] count] > 0)
//	{
//		NSTreeNode* firstSelectedNode = [[folderTreeController selectedNodes] objectAtIndex:0];
//		NSTreeNode* parentNode = [firstSelectedNode parentNode];
//		if (parentNode)
//		{
//			// select the parent
//			NSIndexPath* parentIndex = [parentNode indexPath];
//			[folderTreeController setSelectionIndexPath:parentIndex];
//		}
//		else
//		{
//			// no parent exists (we are at the top of tree), so make no selection in our outline
//			NSArray* selectionIndexPaths = [folderTreeController selectionIndexPaths];
//			[folderTreeController removeSelectionIndexPaths:selectionIndexPaths];
//		}
//	}
//}

// -------------------------------------------------------------------------------
//	isSpecialGroup:
// -------------------------------------------------------------------------------
- (BOOL)isSpecialGroup:(FolderNode *)groupNode
{ 
	return ([groupNode nodeIcon] == nil &&
			[[groupNode nodeTitle] isEqualToString:GROUP_NAME]);
}

- (void)_expandGroups
{
	id item = [folderOutlineView itemAtRow:0];
	if ([folderOutlineView isExpandable:item] && ![folderOutlineView isItemExpanded:item]) {
		[folderOutlineView expandItem:item];
		
		NSUInteger indexes[2] = {0, 0};
		NSIndexPath *indexPath = [NSIndexPath indexPathWithIndexes:indexes length:2];
		[folderTreeController setSelectionIndexPath:indexPath];
	}	
}

- (void)_cacheIconImages
{
	NSWorkspace *ws = [NSWorkspace sharedWorkspace];
	NSImage *image;
	
	if (image = [ws iconForFileType:NSFileTypeForHFSTypeCode(kGenericFolderIcon)]) {
		[self setFolderImage:image];
		[folderImage setSize:NSMakeSize(kIconSizeInTableView,kIconSizeInTableView)];
	}
	
	if (image = [ws iconForFileType:NSFileTypeForHFSTypeCode(kClippingTextTypeIcon)]) {
		[self setSnippetImage:image];
		[snippetImage setSize:NSMakeSize(kIconSizeInTableView,kIconSizeInTableView)];
	}
}

- (void)_moveUpDraggedObjects:(NSArray *)draggedObjects withIndexes:(NSIndexSet *)rowIndexes
{
	NSUInteger index = [rowIndexes firstIndex];
	for (NSManagedObject *object in draggedObjects) {
//		NSLog(@"index: %d", index);
		
		[object setValue:[NSNumber numberWithUnsignedInteger:index] forKey:kIndex];
		
		if ([rowIndexes indexGreaterThanIndex:index] != NSNotFound) {
			index = [rowIndexes indexGreaterThanIndex:index];
		}
	}
}

- (BOOL)_endEditingForWindow
{
	BOOL editingEnded = [self.window makeFirstResponder:self.window];
	if (!editingEnded) {
		NSRunAlertPanel(nil, 
						NSLocalizedString(@"Unable to end editing", nil), 
						NSLocalizedString(@"OK", nil), 
						nil, 
						nil);
		return NO;
	}
	
	return YES;
}

#pragma mark - Folder -

- (id)_rootTreeNodeForSnippetFolder
{
	NSArray *rootNodes = [[folderTreeController arrangedObjects] childNodes];
	if (!rootNodes || ![rootNodes count]) {
		return nil;
	}
	
	return [rootNodes objectAtIndex:0];
}

- (NSArray *)_treeNodesForSnippetFolder
{
	id rootNode = [self _rootTreeNodeForSnippetFolder];
	if (rootNode == nil) {
		return nil;
	}
	
	return [rootNode childNodes];
}

- (NSInteger)_lastIndexOfSnippetFolders
{
	NSArray *snippetFolders = [self _treeNodesForSnippetFolder];
	
	if ((snippetFolders == nil)
		|| ([snippetFolders count] == 0)) {
		return -1;
	}
	
	return [[[[[snippetFolders lastObject] representedObject] folder] valueForKey:kIndex] integerValue];
}

- (FolderNode *)_makeFolderNodeForFolder:(NSManagedObject *)folder
{
	FolderNode *node = [[FolderNode alloc] initLeaf];
	[node setNodeTitle:[folder valueForKey:kTitle]];
	[node setFolder:folder];
	
	return [node autorelease];
}

- (FolderNode *)_makeFolderNodeWithIndex:(NSInteger)index
{
	NSManagedObjectContext *moc = [snippetsController managedObjectContext];
	NSManagedObjectModel *mom = [snippetsController managedObjectModel];
	NSEntityDescription *entity = [[mom entitiesByName] objectForKey:kFolderEntity];
	NSManagedObject *folder = [[NSManagedObject alloc] initWithEntity:entity
									   insertIntoManagedObjectContext:moc];
	[folder setValue:[NSNumber numberWithInteger:index] forKey:kIndex];
	
	FolderNode *node = [[FolderNode alloc] initLeaf];
	[node setNodeTitle:[folder valueForKey:kTitle]];
	[node setFolder:folder];
	[folder release], folder = nil;
	
	return [node autorelease];
}

- (void)_removeFolderNodes:(NSArray *)folderNodes
{
	NSManagedObjectContext *moc = [snippetsController managedObjectContext];
	NSManagedObject *folder;
	
	for (FolderNode *folderNode in folderNodes) {
		folder = [folderNode folder];
//		NSLog(@"folder: %@", folder);
		[moc deleteObject:folder];
	}
}

- (void)_renumberAllFolders
{
	NSUInteger i = 0;
	for (NSTreeNode *firstTreeNode in [self _treeNodesForSnippetFolder]) {
		FolderNode *folderNode = [firstTreeNode representedObject];
//		NSLog(@"item: %d", [folderNode index]);
		[folderNode setIndex:i];
		i++;
		
//		NSLog(@"item: %d", [folderNode index]);
	}
}

- (void)_renumberFoldersFromIndex:(NSUInteger)index
{
	NSArray *treeNodes = [self _treeNodesForSnippetFolder];
	NSUInteger folderSize = [treeNodes count];
	NSTreeNode *firstTreeNode;
	FolderNode *folderNode;
	
	for (NSUInteger i = index; i < folderSize; i++) {
		firstTreeNode = [treeNodes objectAtIndex:i];
		folderNode = [firstTreeNode representedObject];
//		NSLog(@"item: %d", [folderNode index]);
		[folderNode setIndex:i];
		
//		NSLog(@"item: %d", [folderNode index]);
	}
}

- (void)_renumberSnippetsOfFolder:(NSManagedObject *)folder fromIndex:(NSUInteger)index
{
	NSMutableSet *snippets = [[[folder mutableSetValueForKey:kSnippets] mutableCopy] autorelease];
	if (![snippets count]) {
		return;
	}
	
	NSPredicate *predicate = [NSPredicate predicateWithFormat:@"%K > %@",
							  kIndex, [NSNumber numberWithUnsignedInteger:index]];
	[snippets filterUsingPredicate:predicate];
	
//	NSLog(@"snippets: %@", snippets);
	
	if (![snippets count]) {
		return;
	}
	
	NSSortDescriptor *sortDescriptor = [[NSSortDescriptor alloc] initWithKey:kIndex ascending:YES];
	NSArray *descriptors = [NSArray arrayWithObject:sortDescriptor];
	[sortDescriptor release], sortDescriptor = nil;
	
	NSArray *filteredSnippets;
	
	if ([snippets respondsToSelector:@selector( sortedArrayUsingDescriptors: )]) {
		/* Mac OS X 10.6 or highter */
		filteredSnippets = [snippets sortedArrayUsingDescriptors:descriptors];
	}
	else {
		filteredSnippets = [[snippets allObjects] sortedArrayUsingDescriptors:descriptors];
	}
	
//	NSLog(@"filteredSnippets: %@", filteredSnippets);
	
	NSUInteger newIndex = index;
	
	for (NSManagedObject *snippet in filteredSnippets) {
		[snippet setValue:[NSNumber numberWithUnsignedInteger:newIndex] forKey:kIndex];
		newIndex++;
	}
}

/* for debug */
- (void)_inspectAllFolders
{	
	for (NSTreeNode *treeNode in [self _treeNodesForSnippetFolder]) {
		FolderNode *folderNode = [treeNode representedObject];
		NSManagedObject *folder = [folderNode folder];
		NSLog(@"%d: [%@] %@\n  folder: %@",
			  [folderNode index], 
			  ([folderNode isEnabled]) ? @"ON " : @"OFF",
			  [folderNode nodeTitle],
			  folder);
	}
}

- (void)_inspectAllSnippetsAtSelection
{	
	NSArray *selectedObjects = [snippetArrayController selectedObjects];
	
	if (![selectedObjects count]) {
		NSLog(@"No selected objects");
		return;
	}
	
	for (NSManagedObject *snippet in selectedObjects) {
		NSLog(@"%d: [%@] %@",
			  [[snippet valueForKey:kIndex] unsignedIntegerValue], 
			  ([snippet valueForKey:kEnabled]) ? @"ON " : @"OFF",
			  [snippet valueForKey:kTitle]);
	}
}

#pragma mark - Import -

- (void)_parseXMLFileAtURL:(NSURL *)url
{	
	NSXMLParser *xmlParser = [[[NSXMLParser alloc] initWithContentsOfURL:url] autorelease];
	[xmlParser setDelegate:self];
	NSInteger returnCode = [xmlParser parse];
	
	if (!returnCode) {
		NSRunAlertPanel(nil, 
						NSLocalizedString(@"Failed to parse XML file", nil), 
						NSLocalizedString(@"OK", nil), 
						nil, 
						nil);
		return;
	}
}

- (void)_addImportedFolders:(NSArray *)folders
{	
	if (![self _endEditingForWindow]) {
		return;
	}
	
	NSInteger folderIndex = [self _lastIndexOfSnippetFolders];
	NSIndexPath *indexPath;
	FolderNode *folderNode;
	
	for (NSDictionary *folder in folders) {
		folderIndex++;
		
		NSManagedObject *newFolder = [folderArrayController newObject];
		[newFolder setValue:[folder objectForKey:kTitle] forKey:kTitle];
		[newFolder setValue:[NSNumber numberWithInteger:folderIndex] forKey:kIndex];
		
		NSUInteger i = 0;
		for (NSDictionary *snippet in [folder objectForKey:kSnippets]) {
//			NSLog(@"snippet: %@", snippet);
			
			NSManagedObject *newSnippet = [snippetArrayController newObject];
			[newSnippet setValue:[NSNumber numberWithUnsignedInteger:i] forKey:kIndex];
			[newSnippet setValue:[snippet objectForKey:kTitle] forKey:kTitle];
			[newSnippet setValue:[snippet objectForKey:kContent] forKey:kContent];
			[newSnippet setValue:newFolder forKey:kFolder];				// to-one relationship
			[[newFolder valueForKey:kSnippets] addObject:newSnippet];	// inverse relationship
			[newSnippet release], newSnippet = nil;
			i++;
		}
		
		[folderArrayController addObject:newFolder];
		
		folderNode = [self _makeFolderNodeForFolder:newFolder];
		[newFolder release], newFolder = nil;
		
		NSUInteger indexes[2] = {0, folderIndex};
		indexPath = [[NSIndexPath alloc] initWithIndexes:indexes length:2];
		[folderTreeController insertObject:folderNode atArrangedObjectIndexPath:indexPath];
		[indexPath release], indexPath = nil;
	}
}

- (void)_handleNSManagedObjectContextObjectsDidChange:(NSNotification *)aNotification
{
//	NSLog(@"note: %@", [aNotification userInfo]);
	
	NSUndoManager *um = [snippetsController.managedObjectContext undoManager];
	
//	NSLog(@"isUndoing: %d, isRedoing: %d", [um isUndoing], [um isRedoing]);
	
	if (![um isUndoing] && ![um isRedoing]) {
		return;
	}
	
	NSIndexPath *selectionIndexPath = [folderTreeController selectionIndexPath];
	
	[self _prepareSourceList];
	[self _expandGroups];
		
//	[folderTreeController rearrangeObjects];
	
//	[folderTreeController setSelectionIndexPath:nil];
	[folderTreeController setSelectionIndexPath:selectionIndexPath];
}

@end
