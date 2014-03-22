/* AppController */

#import <Cocoa/Cocoa.h>

@class SnippetEditorController;

@interface AppController : NSObject
{	
	SnippetEditorController *snippetEditorController;
	
//	NSOperationQueue *queue;
	ProcessSerialNumber frontPSN;
}
//@property (nonatomic, retain) NSOperationQueue *queue;

- (IBAction)showPreferencePanel:(id)sender;
- (IBAction)showSnippetEditor:(id)sender;
- (IBAction)clearHistory:(id)sender;

- (void)popUpClipMenu:(id)sender;
- (void)popUpActionMenu:(id)sender;
- (void)popUpHistoryMenu:(id)sender;
- (void)popUpSnippetsMenu:(id)sender;
- (void)selectMenuItem:(id)sender;
- (void)selectSnippetMenuItem:(id)sender;
- (void)selectActionMenuItem:(id)sender;

- (void)keepCurrentFrontProcessAndActivate;
- (BOOL)restorePreviousFrontProcess;

@end
