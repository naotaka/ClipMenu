//
//  JavaScriptSupport.h
//  ClipMenu
//
//  Created by Naotaka Morimoto on 08/02/28.
//  Copyright 2008 Naotaka Morimoto. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>


@interface JavaScriptSupport : NSObject 
{
	WebScriptObject *scriptObject;
}
@property (nonatomic, retain) WebScriptObject *scriptObject;

- (id)initWithScriptObject:(WebScriptObject *)webScriptObject;

@end
