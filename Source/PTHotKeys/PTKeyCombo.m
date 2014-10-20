//
//  PTKeyCombo.m
//  Protein
//
//  Created by Quentin Carnicelli on Sat Aug 02 2003.
//  Copyright (c) 2003 Quentin D. Carnicelli. All rights reserved.
//

#import "PTKeyCombo.h"
#import "PTKeyCodeTranslator.h"

@implementation PTKeyCombo

+ (id)clearKeyCombo
{
	return [self keyComboWithKeyCode: -1 modifiers: -1];
}

+ (id)keyComboWithKeyCode: (NSInteger)keyCode modifiers: (NSUInteger)modifiers
{
	return [[self alloc] initWithKeyCode: keyCode modifiers: modifiers];
}

- (id)initWithKeyCode: (NSInteger)keyCode modifiers: (NSUInteger)modifiers
{
	self = [super init];

	if( self )
	{
        switch ( keyCode )
        {
            case kVK_F1:
            case kVK_F2:
            case kVK_F3:
            case kVK_F4:
            case kVK_F5:
            case kVK_F6:
            case kVK_F7:
            case kVK_F8:
            case kVK_F9:
            case kVK_F10:
            case kVK_F11:
            case kVK_F12:
            case kVK_F13:
            case kVK_F14:
            case kVK_F15:
            case kVK_F16:
            case kVK_F17:
            case kVK_F18:
            case kVK_F19:
            case kVK_F20:
                mModifiers = modifiers | NSFunctionKeyMask;
                break;
            default:
                mModifiers = modifiers;
                break;
        }

		mKeyCode = keyCode;
	}

	return self;
}

- (id)initWithPlistRepresentation: (id)plist
{
	int keyCode, modifiers;

	if( !plist || ![plist count] )
	{
		keyCode = -1;
		modifiers = -1;
	}
	else
	{
		keyCode = [[plist objectForKey: @"keyCode"] intValue];
		if( keyCode < 0 ) keyCode = -1;

		modifiers = [[plist objectForKey: @"modifiers"] intValue];
		if( modifiers <= 0 ) modifiers = -1;
	}

	return [self initWithKeyCode: keyCode modifiers: modifiers];
}

- (id)plistRepresentation
{
	return [NSDictionary dictionaryWithObjectsAndKeys:
				[NSNumber numberWithInteger: [self keyCode]], @"keyCode",
				[NSNumber numberWithInteger: [self modifiers]], @"modifiers",
				nil];
}

- (id)copyWithZone:(NSZone*)zone;
{
	return self;
}

- (BOOL)isEqual: (PTKeyCombo*)combo
{
	return	[self keyCode] == [combo keyCode] &&
			[self modifiers] == [combo modifiers];
}

#pragma mark -

- (NSInteger)keyCode
{
	return mKeyCode;
}

- (NSUInteger)modifiers
{
	return mModifiers;
}

- (BOOL)isValidHotKeyCombo
{
	return mKeyCode >= 0 && mModifiers > 0;
}

- (BOOL)isClearCombo
{
	return mKeyCode == -1 && mModifiers == 0;
}

@end

#pragma mark -

@implementation PTKeyCombo (UserDisplayAdditions)

+ (NSString*)_stringForModifiers: (long)modifiers
{
	static unichar modToChar[4][2] =
	{
		{ cmdKey, 		kCommandUnicode },
		{ optionKey,	kOptionUnicode },
		{ controlKey,	kControlUnicode },
		{ shiftKey,		kShiftUnicode }
	};

	NSString* str = [NSString string];
	long i;

	for( i = 0; i < 4; i++ )
	{
		if( modifiers & modToChar[i][0] )
			str = [str stringByAppendingString: [NSString stringWithCharacters: &modToChar[i][1] length: 1]];
	}

	return str;
}

+ (NSDictionary*)_keyCodesDictionary
{
	static NSDictionary* keyCodes = nil;

	if( keyCodes == nil )
	{
		NSURL *url = [NSURL fileURLWithPath:[[NSBundle bundleForClass: self] pathForResource: @"PTKeyCodes" ofType: @"plist"]];
		NSString *contents = [NSString stringWithContentsOfURL:url encoding:NSUTF8StringEncoding error:NULL];
		keyCodes = [contents propertyList];
	}

	return keyCodes;
}

+ (NSString*)_stringForKeyCode: (short)keyCode legacyKeyCodeMap: (NSDictionary*)dict
{
	id key;
	NSString* str;

	key = [NSString stringWithFormat: @"%d", keyCode];
	str = [dict objectForKey: key];

	if( !str )
		str = [NSString stringWithFormat: @"%X", keyCode];

	return str;
}

+ (NSString*)_stringForKeyCode: (short)keyCode newKeyCodeMap: (NSDictionary*)dict
{
	NSString* result;
	NSString* keyCodeStr;
	NSDictionary* unmappedKeys;
	NSArray* padKeys;

	keyCodeStr = [NSString stringWithFormat: @"%d", keyCode];

	//Handled if its not handled by translator
	unmappedKeys = [dict objectForKey:@"unmappedKeys"];
	result = [unmappedKeys objectForKey: keyCodeStr];
	if( result )
		return result;

	//Translate it
	result = [[[PTKeyCodeTranslator currentTranslator] translateKeyCode:keyCode] uppercaseString];

	//Handle if its a key-pad key
	padKeys = [dict objectForKey:@"padKeys"];
	if( [padKeys indexOfObject: keyCodeStr] != NSNotFound )
	{
		result = [NSString stringWithFormat:@"%@ %@", [dict objectForKey:@"padKeyString"], result];
	}

	return result;
}

+ (NSString*)_stringForKeyCode: (short)keyCode
{
	NSDictionary* dict;

	dict = [self _keyCodesDictionary];
	if( [[dict objectForKey: @"version"] intValue] <= 0 )
		return [self _stringForKeyCode: keyCode legacyKeyCodeMap: dict];

	return [self _stringForKeyCode: keyCode newKeyCodeMap: dict];
}

- (NSString*)keyCodeString
{
	// special case: the modifiers for the "clear" key are 0x0
	if ( [self isClearCombo] ) return @"";

    return [[self class] _stringForKeyCode:[self keyCode]];
}

- (NSUInteger)modifierMask
{
	// special case: the modifiers for the "clear" key are 0x0
	if ( [self isClearCombo] ) return 0;

	static NSUInteger modToChar[4][2] =
	{
		{ cmdKey, 		NSCommandKeyMask },
		{ optionKey,	NSAlternateKeyMask },
		{ controlKey,	NSControlKeyMask },
		{ shiftKey,		NSShiftKeyMask }
	};

    NSUInteger i, ret = 0;

    for ( i = 0; i < 4; i++ )
    {
        if ( [self modifiers] & modToChar[i][0] ) {
            ret |= modToChar[i][1];
        }
    }

    return ret;
}

- (NSString*)description
{
	NSString* desc;

	if( [self isValidHotKeyCombo] ) //This might have to change
	{
		desc = [NSString stringWithFormat: @"%@%@",
				[[self class] _stringForModifiers: [self modifiers]],
				[[self class] _stringForKeyCode: [self keyCode]]];
	}
	else
	{
		desc = NSLocalizedString( @"(None)", @"Hot Keys: Key Combo text for 'empty' combo" );
	}

	return desc;
}

@end
