//
//  ActionNodeFactory.h
//  ClipMenu
//
//  Created by Naotaka Morimoto on 08/03/06.
//  Copyright 2008 Naotaka Morimoto. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@class ActionNode, ActionFactory;

@interface ActionNodeFactory : NSObject
{
	ActionFactory *actionFactory;
}
@property (nonatomic, retain) ActionFactory *actionFactory;

- (ActionNode *)createFolderNodeWithTitle:(NSString *)title children:(NSArray *)children;
- (ActionNode *)createActionNodeForType:(NSString *)type title:(NSString *)title actionName:(NSString *)actionName path:(NSString *)path;

- (ActionNode *)createBuiltinActionWithTitle:(NSString *)title actionName:(NSString *)actionName;
- (ActionNode *)createJavaScriptActionWithTitle:(NSString *)title path:(NSString *)path;

@end
