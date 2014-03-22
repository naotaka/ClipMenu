//
//  NSIndexPath+NaoAdditions.h
//  ClipMenu
//
//  Created by naotaka on 08/10/19.
//  Copyright 2008 Naotaka Morimoto. All rights reserved.
//

#import <Cocoa/Cocoa.h>


@interface NSIndexPath (MyExtensions)

// get us the final piece of the index path, i.e, the one that tells
// us were this path fits among its siblings

- (NSUInteger)lastIndex;

// answer whether receiver is the ancestor (other is a descendant)

- (BOOL)isAncestorOfIndexPath:(NSIndexPath *)other;

// answer whether receiver has same immediate parent as other

- (BOOL)isSiblingOfIndexPath:(NSIndexPath *)other;

// find a common ancestor in the tree controller
// return nil if no common ancestor
// these may not be necessary

- (NSIndexPath *)firstCommonAncestorWithIndexPath:(NSIndexPath *)other;
+ (NSIndexPath *)firstCommonAncestorAmongIndexPaths:(NSArray *)otherPaths;

@end


@interface NSIndexPath (NaoAdditions)
- (NSIndexPath *)parentPathIndex;
- (NSIndexPath *)incrementLastNodeIndex;

@end
