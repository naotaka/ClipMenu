#import "ActionNodeController.h"
//#import "NSTreeController+NaoAdditions.h"
#import "NSIndexPath+NaoAdditions.h"
#import "ActionNode.h"
#import "ImageAndTextCell.h"
#import "ActionTypeTransformer.h"
#import "ActionController.h"
#import "CMUtilities.h"
#import "constants.h"


#define SMALL_ICON_SIZE 16
#define DragDropItemPboardType @"DRAG_DROP_ITEM_PBOARD_TYPE"
#define COLUMNID_NAME			@"NameColumn"	// the single column name in our outline view


@interface ActionNodeController (Private)
- (void)_bindDetailsWithTreeController:(NSTreeController *)aController;
- (void)_changeReservedTreeContentToIndex:(NSInteger)selectedIndex;
- (void)_cacheIconImages;

//- (void)_applyImageAndTextCellForOutlineView:(NSOutlineView *)outlineView;
- (NSIndexPath *)_destinationIndexPathFromNode:(NSTreeNode *)destinationNode childIndex:(NSInteger)index;
@end

@implementation ActionNodeController (Private)

- (void)_bindDetailsWithTreeController:(NSTreeController *)aController
{
	NSDictionary *options = [NSDictionary dictionaryWithObjectsAndKeys:
		kEmptyString, NSNoSelectionPlaceholderBindingOption,
		nil];
	
	[nameField bind:@"value"
		   toObject:aController
		withKeyPath:@"selection.nodeTitle"
			options:options];
	
	NSDictionary *optionsForActionType = [NSDictionary dictionaryWithObjectsAndKeys:
		@"ActionTypeTransformer", NSValueTransformerNameBindingOption,
		kEmptyString, NSNoSelectionPlaceholderBindingOption,
		nil];
	[typeField bind:@"value"
		   toObject:aController
		withKeyPath:@"selection.action.type"
			options:optionsForActionType];
	
	[pathField bind:@"value"
		   toObject:aController
		withKeyPath:@"selection.action.path"
			options:options];
}

- (void)_changeReservedTreeContentToIndex:(NSInteger)selectedIndex
{
	NSString *contentKeyPath = nil;
	
	switch (selectedIndex) {
		case CMSelectedSegmentForBuiltinAction:
			contentKeyPath = @"builtinNodes";
			break;
		case CMSelectedSegmentForScriptAction:
			contentKeyPath = @"bundledNodes";
			break;
		case CMSelectedSegmentForUserScriptAction:
			contentKeyPath = @"usersNodes";
			break;
		default:
			NSAssert(NO, @"Should not reach here");
			break;
	}
	
	//			NSLog(@"reserveTreeController: %@", [reserveTreeController infoForBinding:@"contentArray"]);
	
	/* unset */
	[reserveTreeController unbind:@"contentArray"];
	[reserveTreeController setContent:nil];
	
	/* set */
	[reserveTreeController bind:@"contentArray"
					   toObject:self
					withKeyPath:contentKeyPath
						options:nil];
}

- (void)_cacheIconImages
{
	NSWorkspace *ws = [NSWorkspace sharedWorkspace];
	NSImage *image;
	
	if (image = [ws iconForFileType:NSFileTypeForHFSTypeCode(kGenericFolderIcon)]) {
		folderImage = [image retain];
		[folderImage setSize:NSMakeSize(SMALL_ICON_SIZE,SMALL_ICON_SIZE)];		
	}
	
//		itemImage = [[ws iconForFileType:NSFileTypeForHFSTypeCode(kGenericDocumentIcon)] retain];
//		[itemImage setSize:NSMakeSize(SMALL_ICON_SIZE,SMALL_ICON_SIZE)];
	
	NSString *fileNameForAction = [[NSBundle mainBundle] pathForImageResource:@"ActionIcon"];
	if (fileNameForAction) {
		itemImage = [[NSImage alloc] initWithContentsOfFile:fileNameForAction];
	}
	
	if (image = [ws iconForFileType:@"js"]) {
		jsImage = [image retain];
		[jsImage setSize:NSMakeSize(SMALL_ICON_SIZE,SMALL_ICON_SIZE)];
	}
}

//- (void)_applyImageAndTextCellForOutlineView:(NSOutlineView *)outlineView
//{	
//	NSTableColumn *tableColumn = [outlineView tableColumnWithIdentifier:COLUMNID_NAME];
//	ImageAndTextCell *imageAndTextCell = [[[ImageAndTextCell alloc] init] autorelease];
//	[imageAndTextCell setEditable:YES];
//	[imageAndTextCell setLineBreakMode:NSLineBreakByTruncatingTail];
//	[tableColumn setDataCell:imageAndTextCell];
//}

- (NSIndexPath *)_destinationIndexPathFromNode:(NSTreeNode *)destinationNode childIndex:(NSInteger)index
{	
	NSIndexPath *destinationIndexPath = nil;
	
	BOOL destinationIsRoot = (destinationNode == nil);
	BOOL destinationIsInsideAFolder = (index >= 0);
	
	if (destinationIsRoot) {
		NSUInteger insertionIndex = (index >= 0) ? index : [actionNodes count];
		destinationIndexPath = [NSIndexPath indexPathWithIndex:insertionIndex];
	} 
	else {		// has parent
		destinationIndexPath = [destinationNode indexPath];
		//		NSLog(@"destinationIndexPath: %@", destinationIndexPath);
		
		if (destinationIsInsideAFolder) {
			//			NSLog(@"index >= 0");
			destinationIndexPath = [destinationIndexPath indexPathByAddingIndex:index];
		}
		else {					// above an item
			if ([destinationNode isLeaf]) {
				//				NSLog(@"above an item and not a folder");
				//				NSLog(@"destinationIndexPath: %@", destinationIndexPath);
				destinationIndexPath = [destinationIndexPath incrementLastNodeIndex];
			}
			else {
				NSArray *children = [[destinationNode representedObject] valueForKey:childrenKey];
				destinationIndexPath = [destinationIndexPath indexPathByAddingIndex:[children count]];
			}
		}
	}
	
	return destinationIndexPath;
}

@end

#pragma mark -

@implementation ActionNodeController

@synthesize indexOfActionTypeSegment;
@synthesize draggedNodes;
@synthesize actionNodes;
@synthesize builtinNodes;
@synthesize bundledNodes;
@synthesize usersNodes;
@synthesize folderImage;
@synthesize itemImage;
@synthesize jsImage;

#pragma mark Initialize

+ (void)initialize
{
	ActionTypeTransformer *actionTypeTransformer = [[[ActionTypeTransformer alloc] init] autorelease];
	[NSValueTransformer setValueTransformer:actionTypeTransformer forName:@"ActionTypeTransformer"];
}

- (id)init
{
	self = [super init];
	if (self) {		
		ActionController *actionController = [ActionController sharedInstance];
		[actionController prepareActions];
		
		[self setValue:[actionController actionNodes] forKey:@"actionNodes"];
		[self setValue:[actionController builtinActionNodes] forKey:@"builtinNodes"];
		[self setValue:[actionController bundledActionNodes] forKey:@"bundledNodes"];
		[self setValue:[actionController usersActionNodes] forKey:@"usersNodes"];
						
		[self _cacheIconImages];
	}
	return self;
}

- (void)dealloc
{
	/* KVO */
	[self removeObserver:self
			  forKeyPath:@"indexOfActionTypeSegment"];
	
	[actionNodes release], actionNodes = nil;
	[builtinNodes release], builtinNodes = nil;
	[bundledNodes release], bundledNodes = nil;
	[usersNodes release], usersNodes = nil;
	
	[folderImage release], folderImage = nil;
	[itemImage release], itemImage = nil;
	[jsImage release], jsImage = nil;
	
	[super dealloc];
}

#pragma mark -
#pragma mark Accessors
#pragma mark - Setter -

- (void)setActionNodes:(NSMutableArray *)newNodes
{
	if (actionNodes != newNodes) {
		[actionNodes autorelease];
//		actionNodes = [[NSMutableArray alloc] initWithArray:newNodes];
		actionNodes = [newNodes mutableCopy];
	}
}

#pragma mark -
#pragma mark KVO

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
//	NSLog(@"observeValueForKeyPath: %@", keyPath);

	if ([keyPath isEqualToString:@"indexOfActionTypeSegment"]) {
		if ([change objectForKey:NSKeyValueChangeNewKey]) {
			NSInteger selectedIndex = [[change objectForKey:NSKeyValueChangeNewKey] integerValue];
			[self _changeReservedTreeContentToIndex:selectedIndex];
		}
	}
}

#pragma mark -
#pragma mark Delegate

#pragma mark - NSControl -

- (BOOL)control:(NSControl *)control textShouldEndEditing:(NSText *)fieldEditor
{
	if ([[fieldEditor string] length] == 0) {
		// don't allow empty node names
		return NO;
	}
	
	return YES;
}

#pragma mark - NSOutlineView -

- (void)outlineViewSelectionDidChange:(NSNotification *)notification
{	
	NSOutlineView *outlineView = [notification object];
	
//	NSLog(@"outlineViewSelectionDidChange: %@", outlineView);
	
	if (outlineView == actionsOutlineView) {
		[self _bindDetailsWithTreeController:actionTreeController];
	}
	else {
		[self _bindDetailsWithTreeController:reserveTreeController];
	}
}

- (void)outlineView:(NSOutlineView *)outlineView willDisplayCell:(NSCell *)cell forTableColumn:(NSTableColumn *)tableColumn item:(id)item
{	
	if ([[tableColumn identifier] isEqualToString:COLUMNID_NAME]) {
		// we are displaying the single and only column
		if ([cell isKindOfClass:[ImageAndTextCell class]]) {
			NSImage *nodeIcon = nil;
	
			ActionNode *node = [item representedObject];
			if (node) {
				if ([node isLeaf]) {
					NSDictionary *action = [node action];
					NSString *actionType = nil;
					if (action &&
						(actionType = [action objectForKey:@"type"])) {
						if ([actionType isEqualToString:CMBuiltinActionTypeKey]) {
							nodeIcon = itemImage;
						}
						else if ([actionType isEqualToString:CMJavaScriptActionTypeKey]) {
							nodeIcon = jsImage;
						}
					}
					else {
						// it's a separator, don't bother with the icon
					}
				}
				else {
					// it's a folder, use the folderImage as its icon
					nodeIcon = folderImage;
				}
			}
			// set the cell's image
			[(ImageAndTextCell *)cell setImage:nodeIcon];
		}
	}
}

#pragma mark NSOutlineView data source

- (BOOL)outlineView:(NSOutlineView *)outlineView writeItems:(NSArray *)items toPasteboard:(NSPasteboard *)pboard
{	
	NSArray *pboardTypes = [NSArray arrayWithObjects:DragDropItemPboardType, nil];
	[pboard declareTypes:pboardTypes owner:self];
	
	draggedNodes = items;
//	NSLog(@"draggedNodes: %@", draggedNodes);
	
	return YES;
}

- (NSDragOperation)outlineView:(NSOutlineView *)outlineView validateDrop:(id <NSDraggingInfo>)info proposedItem:(id)item proposedChildIndex:(NSInteger)index
{
//	NSLog(@"validateDrop: %@", item);
	
	NSPasteboard *pboard = [info draggingPasteboard];
	NSArray *pboardTypes = [NSArray arrayWithObjects:DragDropItemPboardType, nil];
	
	if ([pboard availableTypeFromArray:pboardTypes]) {
		if ([info draggingSource] == outlineView) {
			return NSDragOperationMove;
		}
		else {
			return NSDragOperationCopy;
		}
	}
	
	return NSDragOperationNone;
}

- (BOOL)outlineView:(NSOutlineView *)outlineView acceptDrop:(id <NSDraggingInfo>)info item:(id)item childIndex:(NSInteger)index
{	
//	NSLog(@"childIndex: %d", index);
	
	NSIndexPath *destinationIndexPath = [self _destinationIndexPathFromNode:item childIndex:index];
//	NSLog(@"destinationIndexPath: %@", destinationIndexPath);
	
	/* if draggingSource is self, it's a move */
	if ([info draggingSource] == outlineView) {		
//		NSInteger nodeCount = 0;
		for (id node in draggedNodes) {
//			nodeCount++;
			
			id item = [[node representedObject] copy];
			NSIndexPath *sourceIndexPath = [node indexPath];
			NSIndexPath *parentIndexPath = ([node parentNode]) ? [[node parentNode] indexPath] : nil;
//			NSLog(@"parentIndexPath: %@", parentIndexPath);
//			NSLog(@"sourceIndexPath: %@", sourceIndexPath);
//			NSLog(@"destinationPath: %@", destinationIndexPath);
			
			NSComparisonResult comparisonResult = [sourceIndexPath compare:destinationIndexPath];
			BOOL isSibling = [sourceIndexPath isSiblingOfIndexPath:destinationIndexPath];
			BOOL sourceAndDestinationHaveSameParent = NO;
			if ([[sourceIndexPath indexPathByRemovingLastIndex] compare:[destinationIndexPath indexPathByRemovingLastIndex]] == NSOrderedSame) {
				sourceAndDestinationHaveSameParent = YES;
			}
			BOOL destinationIsParent = NO;
			if (parentIndexPath &&
				[[parentIndexPath parentPathIndex] compare:[destinationIndexPath parentPathIndex]] == NSOrderedSame) {
				destinationIsParent = YES;
			}
			BOOL destinationIsRoot = ([destinationIndexPath length] == 1);
			NSIndexPath *firstCommonAncestorIndexPath = [sourceIndexPath firstCommonAncestorWithIndexPath:destinationIndexPath];
//			NSLog(@"source compare dest: %d", comparisonResult);
//			NSLog(@"source parent path: %@, dest path: %@", [sourceIndexPath indexPathByRemovingLastIndex], [destinationIndexPath indexPathByRemovingLastIndex]);
//			NSLog(@"sourceAndDestinationHaveSameParent: %d", sourceAndDestinationHaveSameParent);
//			NSLog(@"destinationIsRoot: %d", destinationIsRoot);
//			NSLog(@"destinationIsParent: %d", destinationIsParent);
//			NSLog(@"isSibling: %d", isSibling);
//			NSLog(@"firstCommonAncestorIndexPath: %@", firstCommonAncestorIndexPath);
			
			NSIndexPath *removeObjectPathIndex = nil;
			NSIndexPath *decrementedDestinationPathIndex = nil;
			if (comparisonResult == NSOrderedDescending) {
				if (isSibling) {
					removeObjectPathIndex = [sourceIndexPath incrementLastNodeIndex];
				}
				else if (destinationIsRoot || destinationIsParent) {
//					NSLog(@"destinationIsRoot || destinationIsParent");
					
					NSUInteger sourceLength = [sourceIndexPath length];
					NSUInteger indexes[sourceLength];
					[sourceIndexPath getIndexes:indexes];
					
					for (NSInteger i = 0; i < sourceLength; i++) {
//						NSLog(@"indexes[%d] = %d", i, indexes[i]);
						if ([firstCommonAncestorIndexPath length] == i) {
//							NSLog(@"firstCommonAncestorIndexPath is equal to 'i'");
							indexes[i] = indexes[i] + 1;
						}
					}
										
					removeObjectPathIndex = [NSIndexPath indexPathWithIndexes:indexes 
																	   length:sourceLength];
				}
				else {
//					NSLog(@"OrderedDescending, not sibling");
					removeObjectPathIndex = sourceIndexPath;
				}				
			}
			else {
//				NSLog(@"OrderedAscending");
				removeObjectPathIndex = sourceIndexPath;

				NSUInteger sourceLength = [sourceIndexPath length];
				NSUInteger destLength = [destinationIndexPath length];
				NSUInteger min = (sourceLength < destLength) ? sourceLength-1 : destLength-1;
				NSUInteger destIndexes[destLength];
				[destinationIndexPath getIndexes:destIndexes];
				
//				NSLog(@"sourceLength: %d, destLength: %d", sourceLength, destLength);
//				NSLog(@"min: %d", min);
				
				if (sourceAndDestinationHaveSameParent) {
					destIndexes[min] = destIndexes[min] - 1;
//					NSLog(@"path: %d", destIndexes[min]);
				}
				
				decrementedDestinationPathIndex = [NSIndexPath indexPathWithIndexes:destIndexes
																			 length:destLength];
			}
//			NSLog(@"removeObjectPathIndex: %@", removeObjectPathIndex);
			
			@try {
				[actionTreeController insertObject:item atArrangedObjectIndexPath:destinationIndexPath];
				[actionTreeController removeObjectAtArrangedObjectIndexPath:removeObjectPathIndex];
			}
			@catch (NSException *ex) {
				NSLog(@"Exception: %@", ex);
			}
			@finally {
				[item release], item = nil;
			}
			
			if (decrementedDestinationPathIndex) {
//				NSLog(@"decrementedDestinationPathIndex: %@", decrementedDestinationPathIndex);
				destinationIndexPath = decrementedDestinationPathIndex;
			}
			
			destinationIndexPath = [destinationIndexPath incrementLastNodeIndex];
//			NSLog(@"incremented destinationIndexPath: %@", destinationIndexPath);
		}
					
		return YES;
	}
	else {
		/* draggingSource is not self, it's a copy */
//		NSLog(@"copy");
		
		for (id node in draggedNodes) {
			id item = [[node representedObject] copy];
			@try {
				[actionTreeController insertObject:item atArrangedObjectIndexPath:destinationIndexPath];
			}
			@catch (NSException *ex) {
				NSLog(@"Exception: %@", ex);
			}
			@finally {
				[item release], item = nil;
			}
			
			destinationIndexPath = [destinationIndexPath incrementLastNodeIndex];
		}
		
		return YES;
	}

	return NO;
}

#pragma mark -- Hacks for Drag and Drop --

- (id)outlineView:(NSOutlineView *)outlineView child:(NSInteger)index ofItem:(id)item
{
	return nil;
}

- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item
{
	return NO;
}

- (NSInteger)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(id)item
{
	return 0;
}

- (id)outlineView:(NSOutlineView *)outlineView objectValueForTableColumn:(NSTableColumn *)tableColumn byItem:(id)item
{
	return nil;
}

#pragma mark -
#pragma mark Public

- (void)handleAwakeFromNib
{
//	/* apply our custom ImageAndTextCell for rendering the first column's cells */
//	[self _applyImageAndTextCellForOutlineView:actionsOutlineView];
//	[self _applyImageAndTextCellForOutlineView:reservedActionsOutlineView];
	
	/* Drag and Drop */
	NSArray *draggedTypes = [NSArray arrayWithObjects:DragDropItemPboardType, nil];
	[actionsOutlineView registerForDraggedTypes:draggedTypes];
	[actionsOutlineView setDraggingSourceOperationMask:(NSDragOperationCopy | NSDragOperationMove)
										   forLocal:YES];
	
	[reservedActionsOutlineView setDraggingSourceOperationMask:(NSDragOperationCopy)
										  forLocal:YES];
	
	/* OutlineView sort setting */
	NSSortDescriptor *descriptor = [[NSSortDescriptor alloc] initWithKey:nodeTitleKey ascending:YES];
	[reservedActionsOutlineView setSortDescriptors:[NSArray arrayWithObject:descriptor]];
	[descriptor release], descriptor = nil;
	
//	[reservedActionsOutlineView selectColumnIndexes:[NSIndexSet indexSetWithIndex:0]
//							   byExtendingSelection:NO];
	
	/* Binding */
	[reserveTreeController bind:@"contentArray"
					   toObject:self
					withKeyPath:@"builtinNodes"
						options:nil];
	
	[self _bindDetailsWithTreeController:actionTreeController];
	
	[self addObserver:self
		   forKeyPath:@"indexOfActionTypeSegment"
			  options:NSKeyValueObservingOptionNew
			  context:nil];
}

#pragma mark Actions

/* Buttons */

- (IBAction)add:(id)sender
{
	NSArray *selectedObjects = [reserveTreeController selectedObjects];
	if (!(0 < [selectedObjects count])) {
		return;
	}
	
	for (id item in selectedObjects) {
		NSIndexPath *indexPath = [NSIndexPath indexPathWithIndex:[actionNodes count]];
		[actionTreeController insertObject:item atArrangedObjectIndexPath:indexPath];
	}
}

- (IBAction)remove:(id)sender
{
	NSArray *selectedIndexPaths = [actionTreeController selectionIndexPaths];
	if (!([selectedIndexPaths count] > 0)) {
		return;
	}
	
	for (NSIndexPath *indexPath in [selectedIndexPaths reverseObjectEnumerator]) {
		[actionTreeController removeObjectAtArrangedObjectIndexPath:indexPath];
	}
}

@end
