//
//  JavaScriptSupport.m
//  ClipMenu
//
//  Created by Naotaka Morimoto on 08/02/28.
//  Copyright 2008 Naotaka Morimoto. All rights reserved.
//

#import "JavaScriptSupport.h"
#import "constants.h"
#import "CMUtilities.h"
#import "ActionController.h"


@interface JavaScriptSupport ()
- (NSString *)_loadScript:(NSString *)filePath;

- (BOOL)_require:(NSString *)filename;
- (void)_activate;
@end

#pragma mark -

@implementation JavaScriptSupport

@synthesize scriptObject;

- (id)initWithScriptObject:(WebScriptObject *)webScriptObject
{
	self = [super init];
	if (self) {
		[self setScriptObject:webScriptObject];
	}
	return self;
}

- (void)dealloc
{
	[scriptObject release], scriptObject = nil;
	
	[super dealloc];
}

#pragma mark -
#pragma mark WebSpripting protocol

+ (NSString *)webScriptNameForSelector:(SEL)aSelector
{
//	NSLog(@"webScriptNameForSelector");

	if (aSelector == @selector( _require: )) {
		return @"require";
	}
	else if (aSelector == @selector( _activate )) {
		return @"activate";
	}
	
	return nil;
}

+ (BOOL)isSelectorExcludedFromWebScript:(SEL)aSelector
{
	if (aSelector == @selector( _require: ) ||
		aSelector == @selector( _activate )) {
		return NO;
	}
	return YES;
}

//+ (BOOL)isKeyExcludedFromWebScript:(const char *)name
//{
//	return NO;
//}

#pragma mark -
#pragma mark Private

- (NSString *)_loadScript:(NSString *)filePath
{		
	if (![[NSFileManager defaultManager] fileExistsAtPath:filePath]) {
		return nil;
	}
	
	NSData *data = [NSData dataWithContentsOfFile:filePath];
	if (!data) {
		return nil;
	}
	
	return [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
}

#pragma mark - JavaScript methods -

- (BOOL)_require:(NSString *)filename
{
	if (!filename || [filename isEqualToString:kEmptyString]) {
		return NO;
	}
	
	/* Check lib directories existance */
	
	NSMutableArray *libPaths = [NSMutableArray array];
	
	// The first is user's lib directory
	NSString *userLibFolder = [CMUtilities userLibFolder];
	if (userLibFolder) {
		[libPaths addObject:userLibFolder];
	}
	
	NSString *scriptLibFolder = [CMUtilities scriptLibFolder];
	if (scriptLibFolder) {
		[libPaths addObject:scriptLibFolder];
	}
	
	if ([libPaths count] == 0) {
		return NO;
	}
	
	/* Build script path */
	NSString *scriptName = ([[filename pathExtension] isEqualToString:kJavaScriptExtension])
	? filename
	: [filename stringByAppendingPathExtension:kJavaScriptExtension];
	
	/* Load script */
	for (NSString *path in libPaths) {
		NSString *scriptFilePath = [path stringByAppendingPathComponent:scriptName];		
		NSString *script = [self _loadScript:scriptFilePath];
		if (script) {
			[scriptObject evaluateWebScript:script];
			return YES;
		}
	}
	
	NSLog(@"Could not find the file");
	return NO;
}

- (void)_activate
{	
	/* for prompt called by JavaScript */
	[[ActionController sharedInstance] keepCurrentFrontProcessAndActivate];
}

@end
