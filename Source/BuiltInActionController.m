//
//  BuiltInActionController.m
//  ClipMenu
//
//  Created by Naotaka Morimoto on 08/03/06.
//  Copyright 2008 Naotaka Morimoto. All rights reserved.
//

#import "BuiltInActionController.h"
#import "constants.h"
#import "CMUtilities.h"
#import "ClipsController.h"
#import "SnippetsController.h"
#import "Clip.h"


NSString *const CMBuiltInActionRemove = @"remove:";
NSString *const CMBuiltInActionPasteAsPlainText = @"pasteAsPlainText:";
NSString *const CMBuiltInActionPasteAsFilePath = @"pasteAsFilePath:";
NSString *const CMBuiltInActionPasteAsHFSFilePath = @"pasteAsHFSFilePath:";
//NSString *const CMBuiltInActionSpeak = @"speak:";


@interface BuiltInActionController (Private)
- (void)_prepareActions;
- (void)_prepareToolTips;

//- (NSDictionary *)_createAction:(NSString *)actionName forTypes:(NSArray *)types toolTip:(NSString *)toolTip;
- (NSDictionary *)_createAction:(NSString *)actionName forTypes:(NSArray *)types;

- (NSDictionary *)_actionToRemove;
- (NSDictionary *)_actionToPasteAsPlainText;
- (NSDictionary *)_actionToPasteAsFilePath;
- (NSDictionary *)_actionToPasteAsHFSFilePath;
//- (NSDictionary *)_actionToSpeak;
@end

@implementation BuiltInActionController (Private)

- (void)_prepareActions
{	
	NSMutableDictionary *newActions = [NSMutableDictionary dictionary];
	
	NSArray *commandNames = [NSArray arrayWithObjects:
							 @"Remove", @"PasteAsPlainText", 
							 @"PasteAsFilePath", @"PasteAsHFSFilePath", nil];
//	NSArray *commandNames = [NSArray arrayWithObjects:
//							 @"Remove", @"PasteAsPlainText", 
//							 @"PasteAsFilePath", @"PasteAsHFSFilePath",
//							 @"Speak", nil];
	NSString *prefix = @"_actionTo";
	
	for (NSString *commandName in commandNames) {
		SEL aSelector = NSSelectorFromString([prefix stringByAppendingString:commandName]);
		NSDictionary *command = [self performSelector:aSelector];
		[newActions setObject:command forKey:[command objectForKey:@"actionName"]];
	}
	
	[self setValue:newActions forKey:@"actions"];
}

- (void)_prepareToolTips
{
	NSDictionary *newToolTips = [NSDictionary dictionaryWithObjectsAndKeys:
								 NSLocalizedString(@"Remove the clip from the clipboard history", nil), CMBuiltInActionRemove,
								 NSLocalizedString(@"Paste the clip as Plain Text", nil), CMBuiltInActionPasteAsPlainText,
								 NSLocalizedString(@"Paste the clip as POSIX File Path", nil), CMBuiltInActionPasteAsFilePath,
								 NSLocalizedString(@"Paste the clip as HFS File Path", nil), CMBuiltInActionPasteAsHFSFilePath,
//								 NSLocalizedString(@"Speak", nil), CMBuiltInActionSpeak,
								 nil];
	
	[self setValue:newToolTips forKey:@"toolTips"];
}

//- (NSDictionary *)_createAction:(NSString *)actionName forTypes:(NSArray *)types toolTip:(NSString *)toolTip
//{
//	NSMutableDictionary *action = [NSMutableDictionary dictionaryWithObjectsAndKeys:
//		actionName, @"actionName",
//		types, @"types",
//		nil];
//	
//	if (toolTip) {
//		[action setObject:toolTip forKey:@"toolTip"];
//	}
//		
//	return action;
//}

- (NSDictionary *)_createAction:(NSString *)actionName forTypes:(NSArray *)types
{
	NSDictionary *action = [NSDictionary dictionaryWithObjectsAndKeys:
		actionName, @"actionName",
		types, @"types",
		nil];
	
	return action;	
}

#pragma mark - Create Built-in Actions -

- (NSDictionary *)_actionToRemove
{
	NSDictionary *action = [self _createAction:CMBuiltInActionRemove
									  forTypes:availableTypes];
	return action;
}

- (NSDictionary *)_actionToPasteAsPlainText
{
	NSArray *types = [NSArray arrayWithObject:NSStringPboardType];
	NSDictionary *action = [self _createAction:CMBuiltInActionPasteAsPlainText
									  forTypes:types];
	return action;
}

- (NSDictionary *)_actionToPasteAsFilePath
{
	NSArray *types = [NSArray arrayWithObject:NSFilenamesPboardType];
	NSDictionary *action = [self _createAction:CMBuiltInActionPasteAsFilePath
									  forTypes:types];
	return action;
}

- (NSDictionary *)_actionToPasteAsHFSFilePath
{
	NSArray *types = [NSArray arrayWithObject:NSFilenamesPboardType];
	NSDictionary *action = [self _createAction:CMBuiltInActionPasteAsHFSFilePath
									  forTypes:types];
	return action;
}

//- (NSDictionary *)_actionToSpeak
//{
//	NSArray *types = [NSArray arrayWithObject:NSStringPboardType];
//	NSDictionary *action = [self _createAction:CMBuiltInActionSpeak
//									  forTypes:types];
//	return action;
//}

@end


@implementation BuiltInActionController

@synthesize actions;
@synthesize toolTips;
@synthesize availableTypes;

#pragma mark Initialize

- (id)init
{
	self = [super init];
	if (self) {
		[self setAvailableTypes:[Clip availableTypes]];
		
		[self _prepareActions];
		[self _prepareToolTips];
	}
	return self;
}

- (void)dealloc
{
	[actions release], actions = nil;
	[toolTips release], toolTips = nil;
	[availableTypes release], availableTypes = nil;

	[super dealloc];
}

#pragma mark -
#pragma mark Actions

- (void)remove:(id)target
{	
	if ([target isKindOfClass:[Clip class]]) {
		[[ClipsController sharedInstance] removeClip:(Clip *)target];
	}
	else {		
		[[SnippetsController sharedInstance] removeSnippet:(NSManagedObject *)target];
	}
}

- (void)pasteAsPlainText:(id)target
{
	NSString *plainText;
	
	if ([target isKindOfClass:[Clip class]]) {
		plainText = [target stringValue];
	}
	else {
		plainText = [target valueForKey:kContent];
	}
	
//	NSString *plainText = ([target isKindOfClass:[Clip class]]) ? [target stringValue] : target;
	Clip *newClip = [Clip clipWithString:plainText];
	
	[[ClipsController sharedInstance] copyClipToPasteboard:newClip];
	[CMUtilities paste];
}

- (void)pasteAsFilePath:(Clip *)clip
{
	NSArray *filenames = [clip filenames];
	NSString *results = [filenames componentsJoinedByString:kNewLine];
	Clip *newClip = [Clip clipWithString:results];
	
	[[ClipsController sharedInstance] copyClipToPasteboard:newClip];
	[CMUtilities paste];
}

- (void)pasteAsHFSFilePath:(Clip *)clip
{
	NSArray *filenames = [clip filenames];
	
	NSMutableArray *paths = [NSMutableArray array];
	
	for (NSString *filename in filenames) {
		NSURL *url = [NSURL fileURLWithPath:filename];
		if (!url) {
			continue;
		}
		CFStringRef hfsPath = CFURLCopyFileSystemPath((CFURLRef)url, kCFURLHFSPathStyle);
		[paths addObject:(NSString *)hfsPath];
		CFRelease(hfsPath);
	}
	
	NSString *results = [paths componentsJoinedByString:kNewLine];	
	Clip *newClip = [Clip clipWithString:results];
	
	[[ClipsController sharedInstance] copyClipToPasteboard:newClip];
	[CMUtilities paste];
}

//- (void)speak:(id)target
//{
//	NSString *plainText;
//	
//	if ([target isKindOfClass:[Clip class]]) {
//		plainText = [target stringValue];
//	}
//	else {
//		plainText = [target valueForKey:kContent];
//	}
//	
//	NSSpeechSynthesizer *synthesizer = [[NSSpeechSynthesizer alloc] init];
//	[synthesizer startSpeakingString:plainText];
//	[synthesizer release], synthesizer = nil;
//}

@end
