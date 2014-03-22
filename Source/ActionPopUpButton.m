//
//  ActionPopUpButton.m
//  SnippetsPractice
//
//  Created by naotaka on 08/11/15.
//  Copyright 2008 Naotaka Morimoto. All rights reserved.
//

#import "ActionPopUpButton.h"


@implementation ActionPopUpButton

- (void)mouseDown:(NSEvent *)theEvent
{
	NSPoint locationInWindow = [theEvent locationInWindow];
//	NSLog(@"locationInWindow: %@", NSStringFromPoint(locationInWindow));
	
	NSEvent *newEvent = [NSEvent mouseEventWithType:[theEvent type]
										   location:locationInWindow
									  modifierFlags:[theEvent modifierFlags]
										  timestamp:[theEvent timestamp]
									   windowNumber:[theEvent windowNumber]
											context:[theEvent context]
										eventNumber:[theEvent eventNumber]
										 clickCount:[theEvent clickCount]
										   pressure:[theEvent pressure]];
	
	[self highlight:YES];
	
	[NSMenu popUpContextMenu:[self menu] withEvent:newEvent forView:self];
	
	[self highlight:NO];
}

@end
