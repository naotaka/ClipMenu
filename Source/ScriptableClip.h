//
//  ScriptableClip.h
//  ClipMenu
//
//  Created by naotaka on 09/11/13.
//  Copyright 2009 Naotaka Morimoto. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>

typedef enum {
	CMChangeAttributesSetType,
	CMChangeAttributesAddType,
} CMChangeAttributesType;

@class Clip;

@interface ScriptableClip : NSObject {
	Clip *clip;
}
@property (nonatomic, copy) Clip *clip;

- (id)initWithClip:(Clip *)aClip;

- (void)setStringAttributes:(WebScriptObject *)scriptObject;
- (void)addStringAttributes:(WebScriptObject *)scriptObject;

@end
