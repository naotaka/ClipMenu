//
//  NSString+NaoAdditions.m
//
//  Created by Naotaka Morimoto on 07/11/03.
//  Copyright 2007 Naotaka Morimoto. All rights reserved.
//

#import "NSString+NaoAdditions.h"

#define EMPTY_STRING @""


@implementation NSString (NaoAdditions)

- (NSString *)strip
{
	return [self stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

- (NSString *)entityReference
{
	if (!self || [self isEqualToString:EMPTY_STRING]) {
		return self;
	}
	
	NSString *convertedString;
	convertedString = (NSString *)CFBridgingRelease(CFXMLCreateStringByEscapingEntities(NULL,
																	  (__bridge CFStringRef)self,NULL));
	return convertedString;
}

@end
