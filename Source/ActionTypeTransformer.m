//
//  ActionTypeTransformer.m
//  ClipMenu
//
//  Created by Naotaka Morimoto on 08/02/27.
//  Copyright 2008 Naotaka Morimoto. All rights reserved.
//

#import "ActionTypeTransformer.h"
#import "ActionController.h"


@implementation ActionTypeTransformer

+ (Class)transformedValueClass
{
	return [NSString class];
}

+ (BOOL)allowsReverseTransformation
{
	return NO;
}

- (id)transformedValue:(id)value
{
	if (value == nil) {
		return nil;
	}
	
	NSString *result = nil;
	
	if ([value isEqualToString:CMBuiltinActionTypeKey]) {
		result = NSLocalizedString(@"Built-in", nil);
	}
	else if ([value isEqualToString:CMJavaScriptActionTypeKey]) {
		result = NSLocalizedString(@"JavaScript", nil);
	}
	
	return result;
}

@end
