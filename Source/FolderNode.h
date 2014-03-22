//
//  FolderNode.h
//  ClipMenu
//
//  Created by naotaka on 09/11/29.
//  Copyright 2009 Naotaka Morimoto. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "BaseNode.h"


@interface FolderNode : BaseNode
{
	NSManagedObject *folder;
	
	NSInteger index;
	BOOL isEnabled;
}
@property(nonatomic, retain) NSManagedObject *folder;
@property(nonatomic, assign) NSInteger index;
@property(nonatomic, assign) BOOL isEnabled;
//@property(nonatomic, readonly) NSSet *snippets;
@property(nonatomic, assign) NSSet *snippets;

@end
