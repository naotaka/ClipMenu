//
//  PTHotKey.m
//  Protein
//
//  Created by Quentin Carnicelli on Sat Aug 02 2003.
//  Copyright (c) 2003 Quentin D. Carnicelli. All rights reserved.
//

#import "PTHotKey.h"

#import "PTHotKeyCenter.h"
#import "PTKeyCombo.h"

@implementation PTHotKey

- (id)init
{
	return [self initWithIdentifier: nil keyCombo: nil withObject:nil];
}

- (id)initWithIdentifier: (id)identifier keyCombo: (PTKeyCombo*)combo
{
	return [self initWithIdentifier: identifier keyCombo: combo withObject:nil];

}

- (id)initWithIdentifier: (id)identifier keyCombo: (PTKeyCombo*)combo withObject: (id)object
{
	self = [super init];

	if( self )
	{
		[self setIdentifier: identifier];
		[self setKeyCombo: combo];
        [self setObject: object];
	}

	return self;
}


- (NSString*)description
{
	return [NSString stringWithFormat: @"<%@: %@, %@>", NSStringFromClass( [self class] ), [self identifier], [self keyCombo]];
}

#pragma mark -

- (void)setIdentifier: (id)ident
{
	mIdentifier = ident;
}

- (id)identifier
{
	return mIdentifier;
}

- (void)setKeyCombo: (PTKeyCombo*)combo
{
	if( combo == nil )
		combo = [PTKeyCombo clearKeyCombo];

	mKeyCombo = combo;
}

- (PTKeyCombo*)keyCombo
{
	return mKeyCombo;
}

- (void)setName: (NSString*)name
{
	mName = name;
}

- (NSString*)name
{
	return mName;
}

- (void)setTarget: (id)target
{
	mTarget = target;
}

- (id)target
{
	return mTarget;
}

- (void)setObject:(id)object
{
	mObject = object;
}

- (id)object
{
	return mObject;
}

- (void)setAction: (SEL)action
{
	mAction = action;
}

- (SEL)action
{
	return mAction;
}

- (void)setKeyUpAction: (SEL)action
{
	mKeyUpAction = action;
}

- (SEL)keyUpAction
{
    return mKeyUpAction;
}

- (UInt32)carbonHotKeyID
{
	return mCarbonHotKeyID;
}

- (void)setCarbonHotKeyID: (UInt32)hotKeyID;
{
	mCarbonHotKeyID = hotKeyID;
}

- (EventHotKeyRef)carbonEventHotKeyRef
{
	return mCarbonEventHotKeyRef;
}

- (void)setCarbonEventHotKeyRef: (EventHotKeyRef)hotKeyRef
{
	mCarbonEventHotKeyRef = hotKeyRef;
}

#pragma mark -

- (void)invoke
{
	[mTarget performSelector: mAction withObject: self];
}

- (void)uninvoke
{
    if ([mTarget respondsToSelector:mKeyUpAction])
        [mTarget performSelector: mKeyUpAction withObject: self];
}

@end
