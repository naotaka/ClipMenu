//
//  ActionFactory.m
//  ClipMenu
//
//  Created by Naotaka Morimoto on 08/03/06.
//  Copyright 2008 Naotaka Morimoto. All rights reserved.
//

#import "ActionFactory.h"


NSString *const CMBuiltinActionTypeKey = @"builtin";
NSString *const CMJavaScriptActionTypeKey = @"js";

@implementation ActionFactory

- (NSDictionary *)_actionTypes
{
	NSArray *typeKeys = [NSArray arrayWithObjects:
		CMBuiltinActionTypeKey,
		CMJavaScriptActionTypeKey,
		nil];
	NSArray *typeStrings = [NSArray arrayWithObjects:@"Built-in", @"JavaScript", nil];
	
	return [NSDictionary dictionaryWithObjects:typeStrings forKeys:typeKeys];
}

#pragma mark Public

- (NSDictionary *)createActionForType:(NSString *)type name:(NSString *)name path:(NSString *)path
{
	//	NSString *typeString = [[self _actionTypes] objectForKey:type];
	NSMutableDictionary *action = [NSMutableDictionary dictionaryWithObjectsAndKeys:
		type, @"type",
		nil];
		
	if (name) {
		[action setObject:name forKey:@"name"];
	}

	if (path) {
		[action setObject:path forKey:@"path"];
	}
	
	//	if ([type isEqualToString:CMBuiltinActionTypeKey]) {
	//		[action setObject:name forKey:@"name"];
	//	}
	
	return action;
}

- (NSDictionary *)createActionForType:(NSString *)type name:(NSString *)name
{	
	return [self createActionForType:type name:name path:nil];
}

@end
