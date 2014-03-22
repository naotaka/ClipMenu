//
//  ActionController.m
//  ClipMenu
//
//  Created by Naotaka Morimoto on 08/01/20.
//  Copyright 2008 Naotaka Morimoto. All rights reserved.
//

#import "ActionController.h"
#import "ActionNodeFactory.h"
#import "ActionNode.h"
#import "ActionFactory.h"
#import "BuiltInActionController.h"
#import "JavaScriptSupport.h"
#import "ClipsController.h"
#import "Clip.h"
#import "ScriptableClip.h"
#import "constants.h"
#import "CMUtilities.h"


#pragma mark -

static ActionController *sharedInstance = nil;

NSString *const scriptExceptionKey = @"__scriptException";
NSString *const namespaceKey = @"ClipMenu";
NSString *const clipKey = @"clip";
NSString *const clipTextKey = @"clipText";

/* - fileInfo - */
NSString *const filenameKey = @"filename";
NSString *const filePathKey = @"filePath";
NSString *const resourcePathSeparator = @"ClipMenu.app/Contents/Resources/";
NSString *const saveFileName = @"actions.plist";


@interface ActionController ()
- (void)_prepareDefaultActionNodes;
- (void)_prepareBuiltinActionNodes;
- (void)_prepareBundledScriptActionNodes;
- (void)_prepareUsersScriptActionNodes;
- (NSArray *)_makeScriptNodesWithWalkingDirectory:(NSString *)directoryPath;
- (ActionNode *)_javaScriptNodeWithName:(NSString *)name;
- (NSDictionary *)_javaScriptFileInfoWithName:(NSString *)name;
- (NSString *)_saveFilePath;

//- (void)_prepareCommands;
- (NSString *)_loadScript:(NSString *)filePath;

- (void)_alertPanelWithTitle:(NSString *)title messageText:(NSString *)messageText;
- (id)_init;
@end

#pragma mark -

@implementation ActionController

@synthesize webView;
@synthesize actionNodeFactory;
@synthesize builtInActionController;
@synthesize actionNodes;
@synthesize builtinActionNodes;
@synthesize bundledActionNodes;
@synthesize usersActionNodes;
@synthesize selectedClipTag;
@synthesize selectedSnippet;

#pragma mark Initialize

+ (void)initialize
{
	if (sharedInstance == nil) {
		sharedInstance = [[self alloc] _init];
	}
}

+ (ActionController *)sharedInstance
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
		WebView *wv = [[WebView alloc] init];
		//		[wv setFrameLoadDelegate:self];
		[wv setPolicyDelegate:self];
		[[wv mainFrame] loadHTMLString:kEmptyString baseURL:nil];
		[self setValue:wv forKey:@"webView"];
		[wv release], wv = nil;
		
		actionNodeFactory = [[ActionNodeFactory alloc] init];
		builtInActionController = [[BuiltInActionController alloc] init];
		
		//		[self _prepareCommands];
	}
	return self;
}

- (void)dealloc
{
	[webView release], webView = nil;
	[actionNodeFactory release], actionNodeFactory = nil;
	[actionNodes release], actionNodes = nil;
	[builtinActionNodes release], builtinActionNodes = nil;
	[bundledActionNodes release], bundledActionNodes = nil;
	[usersActionNodes release], usersActionNodes = nil;
	[builtInActionController release], builtInActionController = nil;
	
	[super dealloc];
}

#pragma mark -
#pragma mark Class Methods

+ (NSMutableArray *)defaultActions
{
	NSMutableArray *newActions = [NSMutableArray array];

	NSMutableDictionary *removeAction = [NSMutableDictionary dictionaryWithObjectsAndKeys:
		@"removeAction", @"name",
		kEmptyString, @"path",
		nil];
	[newActions addObject:removeAction];
	
	return newActions;
}

#pragma mark -
#pragma mark Accessors

#pragma mark - Write -

- (void)setActionNodes:(NSMutableArray *)newNodes
{
	if (actionNodes != newNodes) {
		[actionNodes autorelease];
//		actionNodes = [[NSMutableArray alloc] initWithArray:newNodes];
		actionNodes = [newNodes mutableCopy];
	}
}

#pragma mark -
#pragma mark Delegate
//#pragma mark - WebFrameLoadDelegate Protocol -
//
//- (void)webView:(WebView *)sender windowScriptObjectAvailable:(WebScriptObject *)windowScriptObject
//{
//	NSLog(@"WebFrameLoadDelegate");
//}
	
#pragma mark - WebPolicyDelegate Protocol -

/* Prevent accessing external resources */
- (void)webView:(WebView *)sender decidePolicyForNavigationAction:(NSDictionary *)actionInformation request:(NSURLRequest *)request frame:(WebFrame *)frame decisionListener:(id<WebPolicyDecisionListener>)listener
{	
	[listener ignore];
}

#pragma mark -
#pragma mark Public
	
- (void)prepareActions
{
	[self _prepareBuiltinActionNodes];
	[self _prepareBundledScriptActionNodes];
	[self _prepareUsersScriptActionNodes];
}

- (BOOL)saveActions
{
	NSString *path = [CMUtilities applicationSupportFolder];
	if (![CMUtilities prepareSaveToPath:path]) {
		return NO;
	}
	
//	return [NSKeyedArchiver archiveRootObject:actionNodes toFile:[self _saveFilePath]];	// old format
		
	NSMutableArray *plistArray = [NSMutableArray array];
	
	for (ActionNode *node in actionNodes) {
//		NSLog(@"node: %@", [node dictionaryRepresentation]);
		
		[plistArray addObject:[node dictionaryRepresentation]];
	}
	
	NSString *plistPath = [path stringByAppendingPathComponent:saveFileName];
	NSString *errorDescription;
	
	NSData *xmlData = [NSPropertyListSerialization dataFromPropertyList:plistArray
																 format:NSPropertyListXMLFormat_v1_0
													   errorDescription:&errorDescription];
	
	if (xmlData) {
		[xmlData writeToFile:plistPath atomically:YES];
		return YES;
	}
	else {
		NSLog(@"%@", errorDescription);
		[errorDescription release], errorDescription = nil;
		return NO;
	}
}

- (void)loadActions
{	
	NSFileManager *fileManager = [NSFileManager defaultManager];
	NSString *path = [CMUtilities applicationSupportFolder];
	NSString *plistPath = [path stringByAppendingPathComponent:saveFileName];
	
	/* Property List format */
	if ([fileManager fileExistsAtPath:plistPath]) {
		NSData *plistData = [NSData dataWithContentsOfFile:plistPath];
		if (!plistData) {
//			NSLog(@"loadData is nil");
			[self _prepareDefaultActionNodes];
			return;
		}	
		
		NSString *errorDescription;
		
		NSArray *plist = [NSPropertyListSerialization propertyListFromData:plistData
														  mutabilityOption:NSPropertyListImmutable
																	format:NULL
														  errorDescription:&errorDescription];
		if (plist) {
			NSMutableArray *unarhivedNodes = [NSMutableArray array];
			
			for (NSDictionary *dict in plist) {
				ActionNode *node = [[ActionNode alloc] initWithDictionary:dict];
				[unarhivedNodes addObject:node];
				[node release], node = nil;
			}
			
			[self setActionNodes:unarhivedNodes];
		}
		else {
			NSLog(@"%@", errorDescription);
			[errorDescription release], errorDescription = nil;
		}
	}
	/* old format */
	else if ([fileManager fileExistsAtPath:[self _saveFilePath]]) {
		NSMutableArray *loadedData = [NSKeyedUnarchiver unarchiveObjectWithFile:[self _saveFilePath]];
		if (loadedData == nil) {
			//		NSLog(@"loadData is nil");
			[self _prepareDefaultActionNodes];
			
			return;
		}
		
		[self setValue:loadedData forKey:@"actionNodes"];
	}
	/* first startup */
	else {
//		NSLog(@"loadData is nil");
		[self _prepareDefaultActionNodes];
		return;
	}
}

- (void)invokeCommandForKey:(NSString *)key toTarget:(id)target
{
	NSDictionary *actions = [builtInActionController actions];
	NSDictionary *action = [actions objectForKey:key];
	SEL sel = NSSelectorFromString([action objectForKey:@"actionName"]);
	if (!sel) {
		return;
	}
	
	[builtInActionController performSelector:sel withObject:target];
}
	
//- (NSString *)invokeScript:(NSString *)scriptPath toText:(NSString *)clipText
//{	
//	if (!clipText || [clipText length] == 0) {
//		return nil;
//	}
//	
//	NSString *scriptContent = [self _loadScript:scriptPath];
//	if (scriptContent == nil) {
//		[self _alertPanelWithTitle:NSLocalizedString(@"Unable to load script", nil)
//					   messageText:NSLocalizedString(@"Your script file does not exist.", nil)];
//		return nil;
//	}
//	
////	NSString *script = [NSString stringWithFormat:
////		@"try { %@ } catch (e) { %@ = e.toString() }",
////		scriptContent,
////		scriptExceptionKey];
//	
////	NSString *script = [NSString stringWithFormat:
////		@"function __wrapper() { try { %@ } catch (e) { %@ = e.toString(); return; } } __wrapper();",
////		scriptContent,
////		scriptExceptionKey];
//	
//	NSString *script = [NSString stringWithFormat:
//		@"function __wrapper(clipText) { try { %@ } catch (e) { %@ = e.toString(); return; } }",
//		scriptContent,
//		scriptExceptionKey];
//	
//	/* setup WebScriptObject */
//	WebScriptObject *scriptObject = [webView windowScriptObject];
//	
////	[scriptObject setValue:clipText forKey:clipTextKey];
//	[scriptObject setValue:kEmptyString forKey:scriptExceptionKey];
//	
//	JavaScriptSupport *jss = [[[JavaScriptSupport alloc] initWithScriptObject:scriptObject] autorelease];
//	[scriptObject setValue:jss forKey:namespaceKey];
//	
//	/* evaluate JavaScript */
////	id scriptResult = [scriptObject evaluateWebScript:script];
//		
//	[scriptObject evaluateWebScript:script];
//	
//	NSArray *args = [NSArray arrayWithObjects:clipText, nil];
//	id scriptResult = [scriptObject callWebScriptMethod:@"__wrapper" withArguments:args];
//	
//	if (!scriptResult) {
//		[self _alertPanelWithTitle:NSLocalizedString(@"Script Error", nil)
//					   messageText:NSLocalizedString(@"Failed to evaluate script", nil)];
//		return nil;
//	}
//	
////	NSLog(@"scriptResult: %@", [scriptResult className]);
//	
//	/* Error check */
//	if (![[scriptObject valueForKey:scriptExceptionKey] isEqualToString:kEmptyString]) {
//		[self _alertPanelWithTitle:NSLocalizedString(@"Script Exception Raised", nil)
//					   messageText:[scriptObject valueForKey:scriptExceptionKey]];
//		return nil;
//	}
//	else if ([scriptResult isMemberOfClass:[WebUndefined class]]) {
////		[self _alertPanelWithTitle:NSLocalizedString(@"Script Error", nil)
//////					   messageText:@"The returned value is the JavaScript \"undefined\"."];
////					   messageText:NSLocalizedString(@"Script error has occurred", nil)];
//		return nil;
//	}
//	
//	/* Restore process if needed */
//	[self restorePreviousFrontProcess];
//	
//	NSString *result = ([scriptResult respondsToSelector:@selector( stringValue )])
//		? [scriptResult stringValue]
//		: scriptResult;
//	
//	return result;
//}

- (Clip *)invokeScript:(NSString *)scriptPath toClip:(Clip *)clip
{	
	if (clip == nil) {
		return nil;
	}
	
	NSString *clipText = [clip stringValue];
	if (!clipText || [clipText length] == 0) {
		return nil;
	}
	
	ScriptableClip *scriptableClip = [[[ScriptableClip alloc] initWithClip:clip] autorelease];
	
	NSString *scriptContent = [self _loadScript:scriptPath];
	if (scriptContent == nil) {
		[self _alertPanelWithTitle:NSLocalizedString(@"Unable to load script", nil)
					   messageText:NSLocalizedString(@"Your script file does not exist.", nil)];
		return nil;
	}
	
//	NSString *script = [NSString stringWithFormat:
//						@"function __wrapper(clipText) { try { %@ } catch (e) { %@ = e.toString(); return; } }",
//						scriptContent,
//						scriptExceptionKey];
	
	NSString *script = [NSString stringWithFormat:
						@"function __wrapper() { try { %@ } catch (e) { %@ = e.toString(); return; } }",
						scriptContent,
						scriptExceptionKey];
	
	/* Setup WebScriptObject */
	WebScriptObject *scriptObject = [webView windowScriptObject];
	
	[scriptObject setValue:kEmptyString forKey:scriptExceptionKey];
	[scriptObject setValue:clipText forKey:clipTextKey];
	[scriptObject setValue:scriptableClip forKey:clipKey];

	JavaScriptSupport *jss = [[[JavaScriptSupport alloc] initWithScriptObject:scriptObject] autorelease];
	[scriptObject setValue:jss forKey:namespaceKey];
	
	/* Evaluate JavaScript */
	id scriptResult;
	scriptResult = [scriptObject evaluateWebScript:script];
	
	if (!scriptResult) {
		[self _alertPanelWithTitle:NSLocalizedString(@"Script Error", nil)
					   messageText:NSLocalizedString(@"Failed to evaluate script", nil)];
		return nil;
	}
	
//	NSArray *args = [NSArray arrayWithObjects:clipText, nil];
//	scriptResult = [scriptObject callWebScriptMethod:@"__wrapper" withArguments:args];
	
	scriptResult = [scriptObject callWebScriptMethod:@"__wrapper" withArguments:nil];
	
	if (!scriptResult) {
		[self _alertPanelWithTitle:NSLocalizedString(@"Script Error", nil)
					   messageText:NSLocalizedString(@"Failed to evaluate script", nil)];
		return nil;
	}
	
//	NSLog(@"scriptResult: %@", [scriptResult className]);
	
	
//	id lengthObject = [scriptResult valueForKey:@"length"];
//	NSUInteger length = ([lengthObject isKindOfClass:[NSNumber class]])
//	? [lengthObject unsignedIntegerValue] : 0;
//	NSMutableArray *arrayFromScript = [[NSMutableArray alloc] initWithCapacity:length];
//	for (NSInteger i = 0; i < length; i++) {
//		id element = [scriptResult webScriptValueAtIndex:i];
//		if (element) {
//			[arrayFromScript addObject:element];
//		}
//	}
//	NSLog(@"scriptResult: %@", arrayFromScript);
//	[arrayFromScript release], arrayFromScript = nil;
	
//	NSLog(@"scriptResult: %@", [scriptResult valueForKey:@"0"]);
//	NSLog(@"scriptResult: %@", [scriptResult valueForKey:@"color"]);

	
	/* Error check */
	if (![[scriptObject valueForKey:scriptExceptionKey] isEqualToString:kEmptyString]) {
		[self _alertPanelWithTitle:NSLocalizedString(@"Script Exception Raised", nil)
					   messageText:[scriptObject valueForKey:scriptExceptionKey]];
		return nil;
	}
	else if ([scriptResult isMemberOfClass:[WebUndefined class]]) {
		//		[self _alertPanelWithTitle:NSLocalizedString(@"Script Error", nil)
		////					   messageText:@"The returned value is the JavaScript \"undefined\"."];
		//					   messageText:NSLocalizedString(@"Script error has occurred", nil)];
		return nil;
	}
	
	/* Restore process if needed */
	[self restorePreviousFrontProcess];

	/* Return Clip */
	if ([scriptResult isKindOfClass:[ScriptableClip class]]) {
		return [(ScriptableClip *)scriptResult clip];
	}
	
	NSString *result = ([scriptResult respondsToSelector:@selector( stringValue )])
	? [scriptResult stringValue]
	: scriptResult;
	
	Clip *newClip = [Clip clipWithString:result];
	
	return newClip;
}

- (void)clearSelection
{
	[self setSelectedClipTag:0];
	[self setSelectedSnippet:nil];
}


#pragma mark - Process -

//- (BOOL)moveCurrentProcessToForeground
//{
//	ProcessSerialNumber psn;
//	
//	GetCurrentProcess(&psn);
//	TransformProcessType(&psn, kProcessTransformToForegroundApplication);
//	OSErr osError = SetFrontProcess(&psn);
//	if (osError != noErr) {
//		return NO;
//	}
//	return YES;
//}

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

#pragma mark -
#pragma mark Private

#pragma mark - Action Node -

- (void)_prepareDefaultActionNodes
{	
	NSMutableArray *newNodes = [NSMutableArray array];
	NSArray *jsNodes;
	
	/* Paste as Plain Text */
	[newNodes addObject:[actionNodeFactory createBuiltinActionWithTitle:NSLocalizedString(@"Paste as Plain Text", nil)
															 actionName:CMBuiltInActionPasteAsPlainText]];
	
	/* Case */
	jsNodes = [NSArray arrayWithObjects:
			   [self _javaScriptNodeWithName:@"Case/Capitalize.js"],
			   [self _javaScriptNodeWithName:@"Case/lowercase.js"],
			   [self _javaScriptNodeWithName:@"Case/Title Case.js"],
			   [self _javaScriptNodeWithName:@"Case/UPPERCASE.js"],
			   nil];	
	[newNodes addObject:[actionNodeFactory createFolderNodeWithTitle:NSLocalizedString(@"Case", nil)
															children:jsNodes]];	
	/* Trim */
	jsNodes = [NSArray arrayWithObjects:
			   [self _javaScriptNodeWithName:@"Trim/LTrim.js"],
			   [self _javaScriptNodeWithName:@"Trim/RTrim.js"],
			   [self _javaScriptNodeWithName:@"Trim/Trim.js"],
			   nil];	
	[newNodes addObject:[actionNodeFactory createFolderNodeWithTitle:NSLocalizedString(@"Trim", nil)
															children:jsNodes]];
	
	/* Remove Action */
	[newNodes addObject:[actionNodeFactory createBuiltinActionWithTitle:NSLocalizedString(@"Remove", nil)
															 actionName:CMBuiltInActionRemove]];
	
	[self setActionNodes:newNodes];
}

- (void)_prepareBuiltinActionNodes
{
	NSMutableArray *newNodes = [NSMutableArray array];
	
	/* Paste as */
	[newNodes addObject:[actionNodeFactory createBuiltinActionWithTitle:NSLocalizedString(@"Paste as Plain Text", nil)
															 actionName:CMBuiltInActionPasteAsPlainText]];
	
	[newNodes addObject:[actionNodeFactory createBuiltinActionWithTitle:NSLocalizedString(@"Paste as File Path", nil)
															 actionName:CMBuiltInActionPasteAsFilePath]];
	
	[newNodes addObject:[actionNodeFactory createBuiltinActionWithTitle:NSLocalizedString(@"Paste as HFS File Path", nil)
															 actionName:CMBuiltInActionPasteAsHFSFilePath]];
	
	/* Remove Action */
	[newNodes addObject:[actionNodeFactory createBuiltinActionWithTitle:NSLocalizedString(@"Remove", nil)
															 actionName:CMBuiltInActionRemove]];
	
//	[newNodes addObject:[actionNodeFactory createBuiltinActionWithTitle:NSLocalizedString(@"Speak", nil)
//															 actionName:CMBuiltInActionSpeak]];
	
	[self setValue:newNodes forKey:@"builtinActionNodes"];
}

- (void)_prepareBundledScriptActionNodes
{
	NSString *bundledActionsFolder = [CMUtilities bundledActionsFolder];
	if (!bundledActionsFolder) {
		return;
	}
	
	NSArray *newNodes = [self _makeScriptNodesWithWalkingDirectory:bundledActionsFolder];
	
	[self setValue:newNodes forKey:@"bundledActionNodes"];
}

- (void)_prepareUsersScriptActionNodes
{			
	NSString *userActionsFolder = [CMUtilities userActionsFolder];
	if (!userActionsFolder) {
		return;
	}
	
	NSArray *newNodes = [self _makeScriptNodesWithWalkingDirectory:userActionsFolder];
	//	NSLog(@"newNode: %@", newNodes);
	
	[self setValue:newNodes forKey:@"usersActionNodes"];
}

- (NSArray *)_makeScriptNodesWithWalkingDirectory:(NSString *)directoryPath
{	
	NSMutableArray *nodes = [NSMutableArray array];
	
	NSFileManager *fileManager = [NSFileManager defaultManager];
	NSError *error = nil;
	BOOL isDir = NO;
	
	NSArray *directoryContents = [fileManager contentsOfDirectoryAtPath:directoryPath
																  error:&error];
	
	if (error) {
		NSLog(@"Failed to make scripts nodes");
		return nil;
	}
	
	for (NSString *path in directoryContents) {		
		NSString *fullPath = [directoryPath stringByAppendingPathComponent:path];
		NSString *filename = [path lastPathComponent];
		
		if ([filename length] == 0 ||
			[filename characterAtIndex:0] == '.') {
			continue;
		}
		
		NSString *rootname = [filename stringByDeletingPathExtension];
		NSString *localizedName = [CMUtilities localizedFileName:rootname];
		NSString *pathExtension = [filename pathExtension];
		
		//		NSLog(@"path: %@\nfilename: %@\nrootname: %@\npathExtension: %@",
		//			  path, filename, rootname, pathExtension);
		
		ActionNode *node = nil;
		
		if ([fileManager fileExistsAtPath:fullPath isDirectory:&isDir] && isDir) {
			NSArray *children = [self _makeScriptNodesWithWalkingDirectory:fullPath];
			node = [actionNodeFactory createFolderNodeWithTitle:localizedName
													   children:children];
		}
		else {			
			if (![pathExtension isEqualToString:kJavaScriptExtension]) {
				continue;
			}
			
			node = [actionNodeFactory createJavaScriptActionWithTitle:localizedName
																 path:fullPath];
		}
		
		[nodes addObject:node];
	}
	
	return nodes;
}

- (ActionNode *)_javaScriptNodeWithName:(NSString *)name
{
	NSDictionary *fileInfo = [self _javaScriptFileInfoWithName:name];
	ActionNode *node = [actionNodeFactory createJavaScriptActionWithTitle:[fileInfo objectForKey:
																		   filenameKey]
																	 path:[fileInfo objectForKey:filePathKey]];
	
	return node;
}

- (NSDictionary *)_javaScriptFileInfoWithName:(NSString *)name
{
	NSString *bundledActionsFolder = [CMUtilities bundledActionsFolder];
	if (!bundledActionsFolder) {
		return nil;
	}
	
	NSMutableArray *components = [NSMutableArray arrayWithArray:[name componentsSeparatedByString:@"/"]];
	[components insertObject:bundledActionsFolder atIndex:0];
	
	NSString *filename = [components lastObject];
	[components replaceObjectAtIndex:([components count] - 1) withObject:filename];
	
	NSString *filePath = [NSString pathWithComponents:components];
	
	NSDictionary *fileInfo = [NSDictionary dictionaryWithObjectsAndKeys:
							  filename, filenameKey,
							  filePath, filePathKey,
							  nil];
	
	return fileInfo;
}

- (NSString *)_saveFilePath
{
	return [[CMUtilities applicationSupportFolder] stringByAppendingPathComponent:kActionSaveDataName];
}

#pragma mark - Action -

- (NSString *)_loadScript:(NSString *)path
{	
	NSString *filePath;
	NSArray *components;
	
	components = [path componentsSeparatedByString:resourcePathSeparator];
	
	if (1 < [components count]) {
		filePath = [[[NSBundle mainBundle] resourcePath] 
					stringByAppendingPathComponent:[components lastObject]];
	}
	else {
		filePath = path;
	}
	
	//	NSLog(@"filePath: %@", filePath);
	
	if (![[NSFileManager defaultManager] fileExistsAtPath:filePath]) {
		return nil;
	}
	
	NSData *data = [NSData dataWithContentsOfFile:filePath];
	if (!data) {
		return nil;
	}
	
	return [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
}

#pragma mark - User Interface -

- (void)_alertPanelWithTitle:(NSString *)title messageText:(NSString *)messageText
{
	[self keepCurrentFrontProcessAndActivate];		// Keep the most front of process
	
	NSRunAlertPanel(title,
					messageText,
					NSLocalizedString(@"OK", nil),
					nil,nil);
	
	[self restorePreviousFrontProcess];				// Restore other app to front
}

@end
