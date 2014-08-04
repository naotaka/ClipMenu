//
//  PTHotKey+ShortcutRecorder.m
//  ShortcutRecorder
//
//  Created by Ilya Kulakov on 27.02.11.
//  Copyright 2011 Wireload. All rights reserved.
//

#import "PTHotKey+ShortcutRecorder.h"
#import <ShortcutRecorder/SRRecorderControl.h>


@implementation PTHotKey (ShortcutRecorder)

+ (PTHotKey *)hotKeyWithIdentifier:(id)anIdentifier
                          keyCombo:(NSDictionary *)aKeyCombo
                            target:(id)aTarget
                            action:(SEL)anAction
{
    return [PTHotKey hotKeyWithIdentifier:anIdentifier keyCombo:aKeyCombo target:aTarget action:anAction withObject:nil];
}

+ (PTHotKey *)hotKeyWithIdentifier:(id)anIdentifier
                          keyCombo:(NSDictionary *)aKeyCombo
                            target:(id)aTarget
                            action:(SEL)anAction
                        withObject:(id)anObject
{
    NSInteger keyCode = [[aKeyCombo objectForKey:@"keyCode"] integerValue];
    NSUInteger modifiers = SRCocoaToCarbonFlags([[aKeyCombo objectForKey:@"modifierFlags"] unsignedIntegerValue]);
    PTKeyCombo *newKeyCombo = [[PTKeyCombo alloc] initWithKeyCode:keyCode modifiers:modifiers];
    PTHotKey *newHotKey = [[PTHotKey alloc] initWithIdentifier:anIdentifier keyCombo:newKeyCombo];
    [newHotKey setTarget:aTarget];
    [newHotKey setAction:anAction];
    [newHotKey setObject:anObject];
    return newHotKey;
}

+ (PTHotKey *)hotKeyWithIdentifier:(id)anIdentifier
                          keyCombo:(NSDictionary *)aKeyCombo
                            target:(id)aTarget
                            action:(SEL)anAction
                       keyUpAction:(SEL)aKeyUpAction
{				
    PTHotKey *newHotKey = [PTHotKey hotKeyWithIdentifier:anIdentifier
                                                keyCombo:aKeyCombo
                                                  target:aTarget
                                                  action:anAction];
    [newHotKey setKeyUpAction:aKeyUpAction];
    return newHotKey;
}

@end
