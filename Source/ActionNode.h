//
//  ActionNode.h
//  ClipMenu
//
//  Created by Naotaka Morimoto on 08/02/13.
//  Copyright 2008 Naotaka Morimoto. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "BaseNode.h"

extern NSString *const nodeTitleKey;
extern NSString *const isLeafKey;
extern NSString *const childrenKey;
extern NSString *const actionKey;


@interface ActionNode : BaseNode 
{
	NSDictionary *action;
}
@property (nonatomic, retain, setter=setActionCommand:) NSDictionary *action;

- (id)initWithAction:(NSDictionary *)anAction;
- (id)initWithDictionary:(NSDictionary *)aDictonary;
//- (NSDictionary *)dictionaryRepresentation;

@end
