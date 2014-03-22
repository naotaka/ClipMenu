//
//  NSIndexPath+NaoAdditions.m
//  ClipMenu
//
//  Created by naotaka on 08/10/19.
//  Copyright 2008 Naotaka Morimoto. All rights reserved.
//

#import "NSIndexPath+NaoAdditions.h"
//#import "NSTreeController_Extensions.h"

@implementation NSIndexPath (MyExtensions)

- (NSUInteger)lastIndex;
{
	return [self indexAtPosition: [self length] - 1];
}

- (BOOL)isAncestorOfIndexPath:(NSIndexPath *)other; // i.e., other descends from receiver
{
	NSUInteger l1 = [self length], l2 = [other length];
	
	if ( l1 < l2 ) {
		NSUInteger elems1[l1], elems2[l2], i;
		
		[self getIndexes: elems1];
		[other getIndexes: elems2];
		
		for ( i = 0; i < l1; ++i )
			if ( elems1[i] != elems2[i] )
				return NO;
		
		return YES;
	}
	
	return NO;
}

- (BOOL)isSiblingOfIndexPath:(NSIndexPath *)other; // i.e., other has same parent as receiver
{
	NSUInteger l1 = [self length], l2 = [other length];
	
	if ( l1 == l2 ) {
		NSUInteger elems1[l1], elems2[l2], i;
		
		[self getIndexes: elems1];
		[other getIndexes: elems2];
		
		for ( i = 0; i < l1 - 1; ++i )
			if ( elems1[i] != elems2[i] )
				return NO;
		
		return YES;
	}
	
	return NO;
}

- (NSIndexPath *)firstCommonAncestorWithIndexPath:(NSIndexPath *)other;
{
	NSUInteger l1 = [self length], l2 = [other length];
	
	if ( l1 && l2 ) {
		NSUInteger elems1[l1], elems2[l2], i, min = ( l1 < l2 ) ? l1-1 : l2-1;
		
		[self getIndexes: elems1];
		[other getIndexes: elems2];
		
		for ( i = 0; i < min; ++i )
			if ( elems1[i] != elems2[i] )
				break;
		
		return i ? [NSIndexPath indexPathWithIndexes: elems1 length: i] : nil;
	}
	
	return nil;
}

+ (NSIndexPath *)firstCommonAncestorAmongIndexPaths:(NSArray *)paths;
{
	if ( [paths count] < 1 ) return nil;
	
	NSEnumerator *pathEnumerator = [paths objectEnumerator];
	NSIndexPath  *path1 = [pathEnumerator nextObject], *path, *result = [path1 indexPathByRemovingLastIndex];
	
	while ( path = [pathEnumerator nextObject] ) {
		NSIndexPath *candidate = [path firstCommonAncestorWithIndexPath: path1];
		
		if ( !candidate ) return nil;
		
		if ( [candidate length] < [result length] ) result = candidate;
	}
	
	return result;
}

@end


@implementation NSIndexPath (NaoAdditions)

- (NSIndexPath *)parentPathIndex
{
	if ([self length] > 1) {
		return [self indexPathByRemovingLastIndex];
	}
	
	return [NSIndexPath indexPathWithIndex:[self lastIndex]];
}

- (NSIndexPath *)incrementLastNodeIndex
{
	NSInteger lastNodeIndex = [self lastIndex];
	NSIndexPath *tempPath = [self indexPathByRemovingLastIndex];
	NSInteger insertionIndex = lastNodeIndex + 1;
	
	NSAssert(insertionIndex >= 0, @"The insertionIndex must be a positive number");
	
	return (tempPath)
	? [tempPath indexPathByAddingIndex:insertionIndex]
	: [NSIndexPath indexPathWithIndex:insertionIndex];
}

@end
