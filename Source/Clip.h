//
//  Clip.h
//  ClipMenu
//
//  Created by Naotaka Morimoto on 07/12/02.
//  Copyright 2007 Naotaka Morimoto. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface Clip : NSObject <NSCoding>
{
	NSArray *types;
	NSDate *createdDate;
	NSDate *lastUsedDate;

	NSString *stringValue;
	NSData *RTFData;
//	NSData *RTF;
//	NSData *RTFD;
	NSData *PDF;
	NSArray *filenames;
	NSArray *URL;
	NSImage *image;
	
	NSUInteger cachedHash;
	NSImage *thumbnail;
	NSSize thumbnailSize;
}
@property (nonatomic, retain) NSArray *types;
@property (nonatomic, retain) NSDate *createdDate;
@property (nonatomic, retain) NSDate *lastUsedDate;
@property (nonatomic, retain) NSString *stringValue;
@property (nonatomic, retain) NSData *RTFData;
//@property (nonatomic, readonly) NSData *RTF;
//@property (nonatomic, readonly) NSData *RTFD;
@property (nonatomic, retain) NSData *PDF;
@property (nonatomic, retain) NSArray *filenames;
@property (nonatomic, retain) NSArray *URL;
@property (nonatomic, retain) NSImage *image;

+ (id)clipWithString:(NSString *)aString;
- (id)initWithString:(NSString *)aString;
- (id)initWithClip:(Clip *)aClip;

+ (NSArray *)availableTypes;
+ (NSArray *)availableTypeNames;
+ (NSDictionary *)availableTypeDictionary;
+ (NSImage *)fileTypeIconForPboardType:(NSString *)aType;

- (NSString *)description;
- (NSString *)primaryPboardType;
- (NSImage *)thumbnailOfSize:(NSSize)size;
//- (BOOL)isEqualToClip:(Clip *)otherClip;

@end
