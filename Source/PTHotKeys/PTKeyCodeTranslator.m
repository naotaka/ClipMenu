//
//  PTKeyCodeTranslator.m
//  Chercher
//
//  Created by Finlay Dobbie on Sat Oct 11 2003.
//  Copyright (c) 2003 Cliché Software. All rights reserved.
//

#import "PTKeyCodeTranslator.h"


@implementation PTKeyCodeTranslator

+ (id)currentTranslator
{
    static PTKeyCodeTranslator *current = nil;
    TISInputSourceRef currentLayout = TISCopyCurrentKeyboardLayoutInputSource();

    if (current == nil) {
        current = [[PTKeyCodeTranslator alloc] initWithKeyboardLayout:currentLayout];
    } else if ([current keyboardLayout] != currentLayout) {
        [current release];
        current = [[PTKeyCodeTranslator alloc] initWithKeyboardLayout:currentLayout];
    }

	CFRelease(currentLayout);

    return current;
}

- (id)initWithKeyboardLayout:(TISInputSourceRef)aLayout
{
    if ((self = [super init]) != nil) {
        keyboardLayout = aLayout;

		CFRetain(keyboardLayout);

        CFDataRef uchr = TISGetInputSourceProperty( keyboardLayout , kTISPropertyUnicodeKeyLayoutData );
        uchrData = ( const UCKeyboardLayout* )CFDataGetBytePtr(uchr);
    }

    return self;
}

- (void)dealloc
{
	CFRelease(keyboardLayout);

	[super dealloc];
}

- (NSString *)translateKeyCode:(short)keyCode {
    UniCharCount maxStringLength = 4, actualStringLength;
    UniChar unicodeString[4];
    UCKeyTranslate( uchrData, keyCode, kUCKeyActionDisplay, 0, LMGetKbdType(), kUCKeyTranslateNoDeadKeysBit, &deadKeyState, maxStringLength, &actualStringLength, unicodeString );
    return [NSString stringWithCharacters:unicodeString length:1];
}

- (TISInputSourceRef)keyboardLayout {
    return keyboardLayout;
}

- (NSString *)description {
    NSString *kind;
    kind = @"uchr";

    NSString *layoutName;
    layoutName = TISGetInputSourceProperty( keyboardLayout, kTISPropertyLocalizedName );
    return [NSString stringWithFormat:@"PTKeyCodeTranslator layout=%@ (%@)", layoutName, kind];
}

@end
