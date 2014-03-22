//
//  PTHotKeyCenter.m
//  Protein
//
//  Created by Quentin Carnicelli on Sat Aug 02 2003.
//  Copyright (c) 2003 Quentin D. Carnicelli. All rights reserved.
//

#import "PTHotKeyCenter.h"
#import "PTHotKey.h"
#import "PTKeyCombo.h"
#import <Carbon/Carbon.h>

@interface PTHotKeyCenter (Private)
- (PTHotKey*)_hotKeyForCarbonHotKey: (EventHotKeyRef)carbonHotKey;
- (PTHotKey*)_hotKeyForCarbonHotKeyID: (EventHotKeyID)hotKeyID;

- (void)_updateEventHandler;
- (void)_hotKeyDown: (PTHotKey*)hotKey;
- (void)_hotKeyUp: (PTHotKey*)hotKey;
static OSStatus hotKeyEventHandler(EventHandlerCallRef inHandlerRef, EventRef inEvent, void* refCon );
@end

@implementation PTHotKeyCenter

static PTHotKeyCenter *_sharedHotKeyCenter = nil;

+ (PTHotKeyCenter*)sharedCenter
{
	if( _sharedHotKeyCenter == nil )
	{
		_sharedHotKeyCenter = [[self alloc] init];
	}

	return _sharedHotKeyCenter;
}

- (id)init
{
	self = [super init];

	if( self )
	{
		mHotKeys = [[NSMutableDictionary alloc] init];
	}

	return self;
}

- (void)dealloc
{
	[mHotKeys release];
	[super dealloc];
}

#pragma mark -

- (BOOL)registerHotKey: (PTHotKey*)hotKey
{
	OSStatus err;
	EventHotKeyID hotKeyID;
	EventHotKeyRef carbonHotKey;

	if( [[self allHotKeys] containsObject: hotKey] == YES )
		[self unregisterHotKey: hotKey];

	if( [[hotKey keyCombo] isValidHotKeyCombo] == NO )
		return YES;

	hotKeyID.signature = 'PTHk';
	hotKeyID.id = ++mHotKeyCount;

	err = RegisterEventHotKey(  (SInt32)[[hotKey keyCombo] keyCode],
								(UInt32)[[hotKey keyCombo] modifiers],
								hotKeyID,
								GetEventDispatcherTarget(),
								0,
								&carbonHotKey );

	if( err )
		return NO;

	[hotKey setCarbonHotKeyID:hotKeyID.id];
	[hotKey setCarbonEventHotKeyRef:carbonHotKey];

	if( hotKey )
		[mHotKeys setObject: hotKey forKey: [NSNumber numberWithInteger:hotKeyID.id]];

	[self _updateEventHandler];

	return YES;
}

- (void)unregisterHotKey: (PTHotKey*)hotKey
{
	EventHotKeyRef carbonHotKey;

	if( [[self allHotKeys] containsObject: hotKey] == NO )
		return;

	carbonHotKey = [hotKey carbonEventHotKeyRef];

	if( carbonHotKey )
	{
		UnregisterEventHotKey( carbonHotKey );
		//Watch as we ignore 'err':

		[mHotKeys removeObjectForKey: [NSNumber numberWithInteger:[hotKey carbonHotKeyID]]];

		[hotKey setCarbonHotKeyID:0];
		[hotKey setCarbonEventHotKeyRef:NULL];

		[self _updateEventHandler];

		//See that? Completely ignored
	}
}

- (NSArray*)allHotKeys
{
	return [mHotKeys allValues];
}

- (PTHotKey*)hotKeyWithIdentifier: (id)ident
{
	NSEnumerator* hotKeysEnum = [[self allHotKeys] objectEnumerator];
	PTHotKey* hotKey;

	if( !ident )
		return nil;

	while( (hotKey = [hotKeysEnum nextObject]) != nil )
	{
		if( [[hotKey identifier] isEqual: ident] )
			return hotKey;
	}

	return nil;
}

#pragma mark -

- (PTHotKey*)_hotKeyForCarbonHotKey: (EventHotKeyRef)carbonHotKeyRef
{
	NSEnumerator *e = [mHotKeys objectEnumerator];
	PTHotKey *hotkey = nil;

	while( (hotkey = [e nextObject]) )
	{
		if( [hotkey carbonEventHotKeyRef] == carbonHotKeyRef )
			return hotkey;
	}

	return nil;
}

- (PTHotKey*)_hotKeyForCarbonHotKeyID: (EventHotKeyID)hotKeyID
{
	return [mHotKeys objectForKey:[NSNumber numberWithInteger:hotKeyID.id]];
}

- (void)_updateEventHandler
{
	if( [mHotKeys count] && mEventHandlerInstalled == NO )
	{
		EventTypeSpec eventSpec[2] = {
			{ kEventClassKeyboard, kEventHotKeyPressed },
			{ kEventClassKeyboard, kEventHotKeyReleased }
		};

		InstallEventHandler( GetEventDispatcherTarget(),
							 (EventHandlerProcPtr)hotKeyEventHandler,
							 2, eventSpec, nil, nil);

		mEventHandlerInstalled = YES;
	}
}

- (void)_hotKeyDown: (PTHotKey*)hotKey
{
	[hotKey invoke];
}

- (void)_hotKeyUp: (PTHotKey*)hotKey
{
}

- (void)sendEvent: (NSEvent*)event
{
	// Not sure why this is needed? - Andy Kim (Aug 23, 2009)

	short subType;
	EventHotKeyRef carbonHotKey;

	if( [event type] == NSSystemDefined )
	{
		subType = [event subtype];

		if( subType == 6 ) //6 is hot key down
		{
			carbonHotKey= (EventHotKeyRef)[event data1]; //data1 is our hot key ref
			if( carbonHotKey != nil )
			{
				PTHotKey* hotKey = [self _hotKeyForCarbonHotKey: carbonHotKey];
				[self _hotKeyDown: hotKey];
			}
		}
		else if( subType == 9 ) //9 is hot key up
		{
			carbonHotKey= (EventHotKeyRef)[event data1];
			if( carbonHotKey != nil )
			{
				PTHotKey* hotKey = [self _hotKeyForCarbonHotKey: carbonHotKey];
				[self _hotKeyUp: hotKey];
			}
		}
	}
}

- (OSStatus)sendCarbonEvent: (EventRef)event
{
	OSStatus err;
	EventHotKeyID hotKeyID;
	PTHotKey* hotKey;

	NSAssert( GetEventClass( event ) == kEventClassKeyboard, @"Unknown event class" );

	err = GetEventParameter(	event,
								kEventParamDirectObject,
								typeEventHotKeyID,
								nil,
								sizeof(EventHotKeyID),
								nil,
								&hotKeyID );
	if( err )
		return err;


	NSAssert( hotKeyID.signature == 'PTHk', @"Invalid hot key id" );
	NSAssert( hotKeyID.id != 0, @"Invalid hot key id" );

	hotKey = [self _hotKeyForCarbonHotKeyID:hotKeyID];

	switch( GetEventKind( event ) )
	{
		case kEventHotKeyPressed:
			[self _hotKeyDown: hotKey];
		break;

		case kEventHotKeyReleased:
			[self _hotKeyUp: hotKey];
		break;

		default:
			NSAssert( 0, @"Unknown event kind" );
		break;
	}

	return noErr;
}

static OSStatus hotKeyEventHandler(EventHandlerCallRef inHandlerRef, EventRef inEvent, void* refCon )
{
	return [[PTHotKeyCenter sharedCenter] sendCarbonEvent: inEvent];
}

@end
