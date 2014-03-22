//
//  ActionNode.m
//  ClipMenu
//
//  Created by Naotaka Morimoto on 08/02/13.
//  Copyright 2008 Naotaka Morimoto. All rights reserved.
//

#import "ActionNode.h"

/* extern */
NSString *const nodeTitleKey = @"nodeTitle";
NSString *const isLeafKey = @"isLeaf";
NSString *const childrenKey = @"children";
NSString *const actionKey = @"action";


@implementation ActionNode

@synthesize action;

/* designated initializer */
- (id)initWithAction:(NSDictionary *)anAction
{
	self = [super initLeaf];
	if (self) {
		[self setActionCommand:anAction];
	}
	return self;
}

- (id)initWithDictionary:(NSDictionary *)aDictonary
{
	BOOL isDictLeaf = [[aDictonary objectForKey:isLeafKey] boolValue];
	
	if (isDictLeaf) {
		self = [self initWithAction:[aDictonary objectForKey:actionKey]];
		if (!self) {
			return nil;
		}
	}
	else {
		self = [self init];
		if (!self) {
			return nil;
		}
		
		NSMutableArray *childNodes = [NSMutableArray array];
		
		for (NSDictionary *child in [aDictonary objectForKey:childrenKey]) {
			ActionNode *childNode = [[ActionNode alloc] initWithDictionary:child];
			[childNodes addObject:childNode];			
			[childNode release], childNode = nil;
		}
		
		[self setChildren:childNodes];
	}
	
	[self setNodeTitle:[aDictonary objectForKey:nodeTitleKey]];

	return self;
}

- (void)dealloc
{
	[action release], action = nil;
	
	[super dealloc];
}

#pragma mark -
#pragma mark Override

//- (NSDictionary *)dictionaryRepresentation
//{
//	NSMutableArray *childNodes;
//	
//	if (0 < [children count]) {
//		childNodes = [NSMutableArray array];
//		for (ActionNode *node in children) {
//			[childNodes addObject:[node dictionaryRepresentation]];
//		}
//	}
//	else {
//		childNodes = [self children];
//	}
//	
//	return	[NSDictionary dictionaryWithObjectsAndKeys:
//			[self nodeTitle], nodeTitleKey,
//			childNodes, childrenKey,
//			[NSNumber numberWithBool:[self isLeaf]], isLeafKey,
//			[self action], actionKey,
//			nil];
//}

// -------------------------------------------------------------------------------
//	mutableKeys:
//
//	Maintain support for archiving and copying.
// -------------------------------------------------------------------------------
- (NSArray *)mutableKeys
{
	return [[super mutableKeys] arrayByAddingObjectsFromArray:
		[NSArray arrayWithObjects:@"action", nil]];
}

@end
