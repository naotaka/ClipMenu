//
//  ActionController.h
//  ClipMenu
//
//  Created by Naotaka Morimoto on 08/01/20.
//  Copyright 2008 Naotaka Morimoto. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>

extern NSString *const CMBuiltinActionTypeKey;
extern NSString *const CMJavaScriptActionTypeKey;

//extern NSString *const nodeTitleKey;
//extern NSString *const isLeafKey;
//extern NSString *const childrenKey;

@class ActionNodeFactory, BuiltInActionController, Clip;

@interface ActionController : NSObject
{
	WebView *webView;
	
	ActionNodeFactory *actionNodeFactory;
	BuiltInActionController *builtInActionController;
		
	NSMutableArray *actionNodes;
	NSArray *builtinActionNodes;
	NSArray *bundledActionNodes;
	NSArray *usersActionNodes;
	
	NSInteger selectedClipTag;
	NSManagedObject *selectedSnippet;
	
	ProcessSerialNumber frontPSN;
}
@property (nonatomic, retain) WebView *webView;
@property (nonatomic, retain) ActionNodeFactory *actionNodeFactory;
@property (nonatomic, retain) BuiltInActionController *builtInActionController;
@property (nonatomic, copy) NSMutableArray *actionNodes;
@property (nonatomic, retain) NSArray *builtinActionNodes;
@property (nonatomic, retain) NSArray *bundledActionNodes;
@property (nonatomic, retain) NSArray *usersActionNodes;
@property (nonatomic, assign) NSInteger selectedClipTag;
@property (nonatomic, assign) NSManagedObject *selectedSnippet;

+ (ActionController *)sharedInstance;
+ (NSMutableArray *)defaultActions;

- (void)prepareActions;
- (BOOL)saveActions;
- (void)loadActions;

- (void)invokeCommandForKey:(NSString *)key toTarget:(id)target;
//- (NSString *)invokeScript:(NSString *)scriptPath toText:(NSString *)clipText;
- (Clip *)invokeScript:(NSString *)scriptPath toClip:(Clip *)clip;
- (void)clearSelection;


//- (BOOL)moveCurrentProcessToForeground;
- (void)keepCurrentFrontProcessAndActivate;
- (BOOL)restorePreviousFrontProcess;

@end
