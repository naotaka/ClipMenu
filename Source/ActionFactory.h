//
//  ActionFactory.h
//  ClipMenu
//
//  Created by Naotaka Morimoto on 08/03/06.
//  Copyright 2008 Naotaka Morimoto. All rights reserved.
//

#import <Cocoa/Cocoa.h>


@interface ActionFactory : NSObject
{
}

- (NSDictionary *)createActionForType:(NSString *)type name:(NSString *)name path:(NSString *)path;
- (NSDictionary *)createActionForType:(NSString *)type name:(NSString *)name;

@end
