//
//  FolderNode.m
//  ClipMenu
//
//  Created by naotaka on 09/11/29.
//  Copyright 2009 Naotaka Morimoto. All rights reserved.
//

#import "FolderNode.h"
#import "constants.h"

#define DEFAULT_TITLE @"Untitled"


@implementation FolderNode

@synthesize folder;

//- (id)init
//{
//	self = [super init];
//	if (self == nil) {
//		return nil;
//	}
//	
//	[self addObserver:self
//		   forKeyPath:@"nodeTitle"
//			  options:NSKeyValueObservingOptionNew | NSKeyValueObservingOptionOld
//			  context:nil];
//	
//	return self;
//}
//
//- (void)dealloc
//{
//	[self removeObserver:self forKeyPath:@"nodeTitle"];
//	
//	[super dealloc];
//}

- (void)setNodeTitle:(NSString *)newNodeTitle
{
	[super setNodeTitle:newNodeTitle];
	
	if (self.folder &&
		![newNodeTitle isEqualToString:DEFAULT_TITLE] &&
		![newNodeTitle isEqualToString:GROUP_NAME]) {
		[self.folder setValue:newNodeTitle forKey:kTitle];
	}
}

- (void)setIndex:(NSInteger)newIndex
{
	if (index == newIndex) {
		return;
	}
	
	index = newIndex;
	
	if (self.folder) {
		[self.folder setValue:[NSNumber numberWithInteger:newIndex] forKey:kIndex];
	}
}

- (NSInteger)index
{
	if (self.folder == nil) {
		return -1;
	}
	
	return [[self.folder valueForKey:kIndex] integerValue];
}

- (void)setIsEnabled:(BOOL)flag
{
	isEnabled = flag;
		
	if (self.folder) {
		[self.folder setValue:[NSNumber numberWithBool:flag] forKey:kEnabled];
	}
}

- (BOOL)isEnabled
{
	if (self.folder == nil) {
		return YES;
	}

	return [[self.folder valueForKey:kEnabled] boolValue];
}

- (void)setSnippets:(NSSet *)newSenippets
{
	if (self.folder == nil) {
		return;
	}
	
	[self.folder setValue:newSenippets forKey:kSnippets];
}

- (NSSet *)snippets
{
	if (self.folder == nil) {
		return nil;
	}
	
	return [self.folder valueForKey:kSnippets];
}

//#pragma mark -
//#pragma mark KVO
//
//- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
//{
//	NSLog(@"change: %@", change);
//	
//	if ([keyPath isEqualToString:@"nodeTitle"]) {
//		NSString *oldTitle = [change objectForKey:kOldKey];
//		if ([oldTitle isEqualToString:DEFAULT_TITLE]) {
//			return;
//		}
//		
//		NSString *newTitle = [change objectForKey:kNewKey];
//		NSLog(@"new: %@", newTitle);
//		
//		[self.folder setValue:newTitle forKey:kTitle];
//	}
//}

@end
