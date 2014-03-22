/* ActionNodeController */

#import <Cocoa/Cocoa.h>

typedef enum {
	CMSelectedSegmentForBuiltinAction = 0,
	CMSelectedSegmentForScriptAction,
	CMSelectedSegmentForUserScriptAction
} CMSelectedSegment;

@interface ActionNodeController : NSObject
{
	IBOutlet NSOutlineView *actionsOutlineView;
	IBOutlet NSOutlineView *reservedActionsOutlineView;
	
	IBOutlet NSTreeController *actionTreeController;
	IBOutlet NSTreeController *reserveTreeController;
		
	IBOutlet NSTextField *nameField;
	IBOutlet NSTextField *typeField;
	IBOutlet NSTextField *pathField;
	
	NSInteger indexOfActionTypeSegment;
	
	NSArray *draggedNodes;

	/* Model */
	NSMutableArray *actionNodes;
	NSArray *builtinNodes;
	NSArray *bundledNodes;
	NSArray *usersNodes;
	
	/* cached images for generic folder and url document */
	NSImage *folderImage;
	NSImage *itemImage;
	NSImage *jsImage;
}
@property (nonatomic, assign) NSInteger indexOfActionTypeSegment;
@property (nonatomic, assign) NSArray *draggedNodes;
@property (nonatomic, copy) NSMutableArray *actionNodes;
@property (nonatomic, retain) NSArray *builtinNodes;
@property (nonatomic, retain) NSArray *bundledNodes;
@property (nonatomic, retain) NSArray *usersNodes;
@property (nonatomic, retain) NSImage *folderImage;
@property (nonatomic, retain) NSImage *itemImage;
@property (nonatomic, retain) NSImage *jsImage;

- (void)handleAwakeFromNib;

- (IBAction)add:(id)sender;
- (IBAction)remove:(id)sender;

@end
