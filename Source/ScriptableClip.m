//
//  ScriptableClip.m
//  ClipMenu
//
//  Created by naotaka on 09/11/13.
//  Copyright 2009 Naotaka Morimoto. All rights reserved.
//

#import "ScriptableClip.h"
#import "Clip.h"

#import "NSColor+String.h"

/* AttributedString */
#define COLOR_KEY @"color"
#define FOREGROUND_COLOR_KEY @"foreground"
#define BACKGROUND_COLOR_KEY @"background"
#define FONT_KEY @"font"
#define NAME_KEY @"name"
#define SIZE_KEY @"size"
#define UNDERLINE_STYLE_KEY @"underline"
#define STYLE_KEY @"style"
#define PATTERN_KEY @"pattern"
#define BYWORD_KEY @"byWord"


#pragma mark -

id
getValueFromWebScriptObject(WebScriptObject *scriptObject, NSString *key)
{
	id result = nil;
	@try {
		result = [scriptObject valueForKey:key];
	}
	@catch (NSException *e) {
		result = nil;
	}
	return result;
}

NSInteger
getUnderlineStyleConstantForName(NSString *name)
{
	NSString *lowerName = [name lowercaseString];
	static NSDictionary *styles = nil;
	
	if (styles == nil) {
		NSArray *keys = [[NSArray alloc] initWithObjects:
						 @"none", @"single", @"thick", @"double", nil];
		NSArray *values = [[NSArray alloc] initWithObjects:
						   [NSNumber numberWithInteger:NSUnderlineStyleNone],
						   [NSNumber numberWithInteger:NSUnderlineStyleSingle],
						   [NSNumber numberWithInteger:NSUnderlineStyleThick],
						   [NSNumber numberWithInteger:NSUnderlineStyleDouble],
						   nil];
		styles = [[NSDictionary alloc] initWithObjects:values forKeys:keys];
		[keys release], keys = nil;
		[values release], values = nil;
	}
	
	NSNumber *num = [styles objectForKey:lowerName];
//	[styles release], styles = nil;
	
	if (num == nil) {
		return NSUnderlineStyleNone;
	}
	
	return [num integerValue];
}

NSInteger
getUnderlinePatternConstantForName(NSString *name)
{
	NSString *lowerName = [name lowercaseString];
	static NSDictionary *styles = nil;
	
	if (styles == nil) {
		NSArray *keys = [[NSArray alloc] initWithObjects:
						 @"solid", @"dot", @"dash", @"dashdot", @"dashdotdot", nil];
		NSArray *values = [[NSArray alloc] initWithObjects:
						   [NSNumber numberWithInteger:NSUnderlinePatternSolid],
						   [NSNumber numberWithInteger:NSUnderlinePatternDot],
						   [NSNumber numberWithInteger:NSUnderlinePatternDash],
						   [NSNumber numberWithInteger:NSUnderlinePatternDashDot],
						   [NSNumber numberWithInteger:NSUnderlinePatternDashDotDot],
						   nil];
		styles = [[NSDictionary alloc] initWithObjects:values forKeys:keys];
		[keys release], keys = nil;
		[values release], values = nil;
	}
	
	NSNumber *num = [styles objectForKey:lowerName];
//	[styles release], styles = nil;
	
	if (num == nil) {
		return NSUnderlinePatternSolid;
	}
	
	return [num integerValue];
}

#pragma mark -

@interface ScriptableClip ()
- (void)_changeStringAttributes:(WebScriptObject *)scriptObject forType:(CMChangeAttributesType)type;
- (NSDictionary *)_getColorsFromWebScriptObject:(WebScriptObject *)scriptObject;
- (NSFont *)_getFontFromWebScriptObject:(WebScriptObject *)scriptObject;
- (NSNumber *)_getUnderlineStyleFromWebScriptObject:(WebScriptObject *)scriptObject;
@end

#pragma mark -

@implementation ScriptableClip

@synthesize clip;

- (id)initWithClip:(Clip *)aClip
{
	self = [super init];
	if (self == nil) {
		return nil;
	}
	
	[self setClip:aClip];
	
	return self;
}

- (void)dealloc
{
	[clip release], clip = nil;
	
	[super dealloc];
}

#pragma mark -

- (void)setStringAttributes:(WebScriptObject *)scriptObject
{		
	[self _changeStringAttributes:scriptObject forType:CMChangeAttributesSetType];
}

- (void)addStringAttributes:(WebScriptObject *)scriptObject
{
	[self _changeStringAttributes:scriptObject forType:CMChangeAttributesAddType];
}

#pragma mark -
#pragma mark WebSpripting protocol

+ (NSString *)webScriptNameForSelector:(SEL)aSelector
{
//	NSLog(@"webScriptNameForSelector");
	
	if (aSelector == @selector( setStringAttributes: )) {
		return @"setStringAttributes";
	}
	else if (aSelector == @selector( addStringAttributes: )) {
		return @"addStringAttributes";
	}
	
	return nil;
}

+ (BOOL)isSelectorExcludedFromWebScript:(SEL)aSelector
{
	if (aSelector == @selector( setStringAttributes: ) ||
		aSelector == @selector( addStringAttributes: )) {
		return NO;
	}
	return YES;
}

#pragma mark -
#pragma mark Private

- (void)_changeStringAttributes:(WebScriptObject *)scriptObject forType:(CMChangeAttributesType)type
{	
	Clip *aClip = self.clip;
	
	if (aClip.stringValue == nil) {
		return;
	}
	
	NSMutableArray *types = [NSMutableArray arrayWithArray:aClip.types];
	BOOL containsRTFD = [types containsObject:NSRTFDPboardType];
	NSMutableAttributedString *attrString = [NSMutableAttributedString alloc];
	
	if (aClip.RTFData) {
		if (containsRTFD) {
			attrString = [attrString initWithRTFD:aClip.RTFData documentAttributes:nil];
		}
		else {
			attrString = [attrString initWithRTF:aClip.RTFData documentAttributes:nil];	
		}
	}
	else {
		attrString = [[NSMutableAttributedString alloc] initWithString:aClip.stringValue];
		if ([types containsObject:NSRTFPboardType]) {
			[types removeObject:NSRTFPboardType];
		}
		[types insertObject:NSRTFPboardType atIndex:0];
	}
	
	NSRange range = NSMakeRange(0, [attrString length]);
	NSMutableDictionary *attrs = [[NSMutableDictionary alloc] init];
	
	/* Color */	
	NSDictionary *colors = [self _getColorsFromWebScriptObject:scriptObject];
	NSColor *color;
	for (NSString *key in colors) {
		color = [colors objectForKey:key];
		if ([key isEqualToString:FOREGROUND_COLOR_KEY]) {
			[attrs setObject:color forKey:NSForegroundColorAttributeName];
		}
		else if ([key isEqualToString:BACKGROUND_COLOR_KEY]) {
			[attrs setObject:color forKey:NSBackgroundColorAttributeName];
		}
	}
	
	/* Font */
	NSFont *font = [self _getFontFromWebScriptObject:scriptObject];
	if (font) {
		[attrs setObject:font forKey:NSFontAttributeName];
	}
	
	/* Underline Style */
	NSNumber *underlineStyle = [self _getUnderlineStyleFromWebScriptObject:scriptObject];
	if (underlineStyle) {
		[attrs setObject:underlineStyle forKey:NSUnderlineStyleAttributeName];
	}
	
	if ([attrs count]) {		
		[attrString beginEditing];
		
		@try {
			/* Use this way
			   because performSelector:withObject:withObject: always raises exception */
			switch (type) {
				case CMChangeAttributesSetType:
					[attrString setAttributes:attrs range:range];
					break;
				case CMChangeAttributesAddType:
					[attrString addAttributes:attrs range:range];
					break;
				default:
					NSAssert(NO, @"Unknown change type");
					break;
			}
			[attrString fixAttributesInRange:range];
		}
		@catch (NSException *ex) {
			NSLog(@"exception: %@", ex);
		}
		
		[attrString endEditing];
		
		aClip.types = types;		
		aClip.RTFData = (containsRTFD) 
		? [attrString RTFDFromRange:range documentAttributes:nil]
		: [attrString RTFFromRange:range documentAttributes:nil];
	}
	
	[attrs release], attrs = nil;
	[attrString release], attrString = nil;
}

- (NSDictionary *)_getColorsFromWebScriptObject:(WebScriptObject *)scriptObject
{
	NSMutableDictionary *colors = [NSMutableDictionary dictionaryWithCapacity:2];
	NSString *colorName;
	NSColor *color;
	@try {
		WebScriptObject *colorObject = [scriptObject valueForKey:COLOR_KEY];
		if (colorObject) {
			colorName = getValueFromWebScriptObject(colorObject, FOREGROUND_COLOR_KEY);
			if (colorName) {
				color = [NSColor colorWithString:colorName];
				[colors setObject:color forKey:FOREGROUND_COLOR_KEY];
			}
			
			colorName = getValueFromWebScriptObject(colorObject, BACKGROUND_COLOR_KEY);
			if (colorName) {
				color = [NSColor colorWithString:colorName];
				[colors setObject:color forKey:BACKGROUND_COLOR_KEY];
			}	
		}
	}
	@catch (NSException *e) {
	}
	return colors;
}

- (NSFont *)_getFontFromWebScriptObject:(WebScriptObject *)scriptObject
{
	NSFont *font = nil;
	@try {
		WebScriptObject *fontObject = [scriptObject valueForKey:FONT_KEY];
		if (fontObject) {
			NSString *fontName = getValueFromWebScriptObject(fontObject, NAME_KEY);
			CGFloat fontSize = [getValueFromWebScriptObject(fontObject, SIZE_KEY) floatValue];
			font = [NSFont fontWithName:fontName size:fontSize];
		}
	}
	@catch (NSException *e) {
	}
	return font;
}

- (NSNumber *)_getUnderlineStyleFromWebScriptObject:(WebScriptObject *)scriptObject
{
	NSNumber *underlineStyle = nil;
	NSString *styleName;
	NSNumber *byWordNumer;
	NSInteger styleConstant;
	NSInteger patternConstant;
	NSUInteger maskConstant = 0;
	@try {
		WebScriptObject *styleObject = [scriptObject valueForKey:UNDERLINE_STYLE_KEY];
		if (styleObject) {
			styleName = getValueFromWebScriptObject(styleObject, STYLE_KEY);
			styleConstant = getUnderlineStyleConstantForName(styleName);
			
			styleName = getValueFromWebScriptObject(styleObject, PATTERN_KEY);
			patternConstant = getUnderlinePatternConstantForName(styleName);
			
			byWordNumer = getValueFromWebScriptObject(styleObject, BYWORD_KEY);
			if ([byWordNumer boolValue]) {
				maskConstant = NSUnderlineByWordMask;
			}
						
			underlineStyle = [NSNumber numberWithInteger:styleConstant | patternConstant | maskConstant];
		}
	}
	@catch (NSException *e) {
	}
	return underlineStyle;
}

@end
