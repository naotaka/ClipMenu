//
//  ActionNodeFactory.m
//  ClipMenu
//
//  Created by Naotaka Morimoto on 08/03/06.
//  Copyright 2008 Naotaka Morimoto. All rights reserved.
//

#import "ActionNodeFactory.h"
#import "ActionNode.h"
#import "ActionFactory.h"
#import "ActionController.h"
#import "constants.h"


@implementation ActionNodeFactory

@synthesize actionFactory;

- (id)init
{
	self = [super init];
	if (self) {
		ActionFactory *factory = [[ActionFactory alloc] init];
		[self setActionFactory:factory];
		[factory release], factory = nil;
	}
	return self;
}

- (void)dealloc
{
	[actionFactory release], actionFactory = nil;
	
	[super dealloc];
}

#pragma mark Public

- (ActionNode *)createFolderNodeWithTitle:(NSString *)title children:(NSArray *)children
{	
	ActionNode *newNode = [[[ActionNode alloc] init] autorelease];
	[newNode setValue:title forKey:nodeTitleKey];
	[newNode setValue:children forKey:childrenKey];
	
	return newNode;
}

- (ActionNode *)createActionNodeForType:(NSString *)type title:(NSString *)title actionName:(NSString *)actionName path:(NSString *)path
{
	NSDictionary *action = [actionFactory createActionForType:type name:actionName path:path];
	
	ActionNode *newNode = [[[ActionNode alloc] initWithAction:action] autorelease];
	[newNode setValue:title forKey:nodeTitleKey];
	
	return newNode;
}

- (ActionNode *)createBuiltinActionWithTitle:(NSString *)title actionName:(NSString *)actionName
{
	return [self createActionNodeForType:CMBuiltinActionTypeKey title:title
							  actionName:actionName
									path:nil];
}

- (ActionNode *)createJavaScriptActionWithTitle:(NSString *)title path:(NSString *)path
{
	return [self createActionNodeForType:CMJavaScriptActionTypeKey 
								   title:title 
							  actionName:nil 
									path:path];
}

@end
