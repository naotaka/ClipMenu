//
//  Clip.m
//  ClipMenu
//
//  Created by Naotaka Morimoto on 07/12/02.
//  Copyright 2007 Naotaka Morimoto. All rights reserved.
//

#import "Clip.h"


#define TYPES_KEY @"types"
#define CREATED_DATE_KEY @"createdDate"
#define LAST_USED_DATE_KEY @"lastUsedDate"
#define STRING_VALUE_KEY @"stringValue"
#define RTFDATA_KEY @"RTFData"
#define RTF_KEY @"RTF"
#define RTFD_KEY @"RTFD"
#define PDF_KEY @"PDF"
#define FILENAMES_KEY @"filenames"
#define URL_KEY @"URL"
#define IMAGE_KEY @"image"


//@interface Clip (Private)
//- (BOOL)_isEqualToTIFF:(NSImage *)otherImage;
//@end
//
//@implementation Clip (Private)
//	
//- (BOOL)_isEqualToTIFF:(NSImage *)otherImage
//{
////	NSLog(@"Enter image equality check.");
//	
//	NSData *TIFFImage = [image TIFFRepresentation];
//	NSData *otherData = [otherImage TIFFRepresentation];
//	
//	NSBitmapImageRep *imageRep = [NSBitmapImageRep imageRepWithData:TIFFImage];
//	NSBitmapImageRep *otherRep = [NSBitmapImageRep imageRepWithData:otherData];
//	
////	NSLog(@"length: %d, other: %d", [TIFFImage length], [otherData length]);
////	NSLog(@"imageRep: %@", imageRep);
////	NSLog(@"otherRep: %@", otherRep);
//
//	/* NSImageRep */
//	if (!NSEqualSizes([imageRep size],[otherRep size])) {
//		return NO;
//	}
//	if (![[imageRep colorSpaceName] isEqualToString:[otherRep colorSpaceName]]) {
//		return NO;
//	}
//	if ([imageRep bitsPerSample] != [otherRep bitsPerSample]) {
//		return NO;
//	}
//	if ([imageRep hasAlpha] != [otherRep hasAlpha]) {
//		return NO;
//	}
//	if ([imageRep isOpaque] != [otherRep isOpaque]) {
//		return NO;
//	}
//	
//	/* NSBitmapImageRep */
////		NSLog(@"me: %d, other: %d", [imageRep bitmapFormat], [otherRep bitmapFormat]);
//	if ([imageRep bitmapFormat] != [otherRep bitmapFormat]) {	// this doesn't work correctly
////		NSLog(@"Not equal!");
//		return NO;
//	}
//	
//	if ([imageRep isPlanar] != [otherRep isPlanar]) {
//		return NO;
//	}
//	if ([imageRep samplesPerPixel] != [otherRep samplesPerPixel]) {
//		return NO;
//	}
//	
//	/* NSData */
//	if (![TIFFImage isEqualToData:otherData]) {
////		NSLog(@"Not equal!");
//		return NO;
//	}
//	
////	NSLog(@"Same image.");
//	return YES;
//}
//
//@end

@interface Clip ()
- (NSBitmapImageRep *)_representationOfBitmapImageRep:(NSBitmapImageRep *)bitmapRep withSize:(NSSize)size;
@end

#pragma mark -

@implementation Clip

@synthesize types;
@synthesize createdDate;
@synthesize lastUsedDate;
@synthesize stringValue;
@synthesize RTFData;
//@synthesize RTF;
//@synthesize RTFD;
@synthesize PDF;
@synthesize filenames;
@synthesize URL;
@synthesize image;

#pragma mark Class methods

+ (NSArray *)availableTypes
{
	return [NSArray arrayWithObjects:
		NSStringPboardType,
		NSRTFPboardType,
		NSRTFDPboardType,
		NSPDFPboardType,
		NSFilenamesPboardType,
		NSURLPboardType,
		NSTIFFPboardType,
		NSPICTPboardType,
		nil];
}

+ (NSArray *)availableTypeNames
{
	return [NSArray arrayWithObjects:
		@"String",
		@"RTF",
		@"RTFD",
		@"PDF",
		@"Filenames",
		@"URL",
		@"TIFF",
		@"PICT",
		nil];
}

+ (NSDictionary *)availableTypeDictionary
{		
	return [NSDictionary dictionaryWithObjects:[self availableTypeNames] 
									   forKeys:[self availableTypes]];
}

+ (NSImage *)fileTypeIconForPboardType:(NSString *)aType
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	
	NSString *pbType = nil;
	if ([aType isEqualToString:NSStringPboardType]) {
		pbType = @"String";
	}
	else if ([aType isEqualToString:NSRTFPboardType]) {
		pbType = @"RTF";
	}
	else if ([aType isEqualToString:NSRTFDPboardType]) {
		pbType = @"RTFD";
	}
	else if ([aType isEqualToString:NSPDFPboardType]) {
		pbType = @"PDF";
	}
	else if ([aType isEqualToString:NSFilenamesPboardType]) {
		pbType = @"Filenames";
	}
	else if ([aType isEqualToString:NSURLPboardType]) {
		pbType = @"URL";
	}
	else if ([aType isEqualToString:NSTIFFPboardType]) {
		pbType = @"TIFF";
	}
	else if ([aType isEqualToString:NSPICTPboardType]) {
		pbType = @"PICT";
	}
	
	NSString *fileTypeSelectionTagKey = [NSString stringWithFormat:
		@"menuIconOfFileTypeTagFor%@", pbType];
	NSString *fileTypeKey = [NSString stringWithFormat:
		@"menuIconOfFileTypeFor%@", pbType];
	NSString *fileType = [defaults stringForKey:fileTypeKey];
	
	switch ([defaults integerForKey:fileTypeSelectionTagKey]) {
		case 1: {
			OSType hfsTypeCode = NSHFSTypeCodeFromFileType([NSString stringWithFormat:@"'%@'", fileType]);
			fileType = NSFileTypeForHFSTypeCode(hfsTypeCode);
			break;
		}
	}
	
	return [[NSWorkspace sharedWorkspace] iconForFileType:fileType];
}

#pragma mark Initialize

+ (id)clipWithString:(NSString *)aString
{
//	Clip *clip = [[[[self class] alloc] init] autorelease];
//	[clip setStringValue:aString];	
//	[clip setTypes:[NSArray arrayWithObject:NSStringPboardType]];
//	return clip;
	
	return [[[[self class] alloc] initWithString:aString] autorelease];
}

/* Designated Initializer */
- (id)init
{
	self = [super init];
	if (self == nil) {
		return nil;
	}
	
	NSDate *currentDate = [NSDate date];
	[self setCreatedDate:currentDate];
	[self setLastUsedDate:currentDate];
	
	return self;
}

- (id)initWithString:(NSString *)aString
{
	Clip *clip = [self init];
	if (clip == nil) {
		return nil;
	}
	
	[clip setStringValue:aString];	
	[clip setTypes:[NSArray arrayWithObject:NSStringPboardType]];
	return clip;
}

- (id)initWithClip:(Clip *)aClip
{
	Clip *clip = [self init];
	if (clip == nil) {
		return nil;
	}
	
	[clip setTypes:[aClip types]];
	[clip setCreatedDate:[aClip createdDate]];
	[clip setLastUsedDate:[aClip lastUsedDate]];
	[clip setStringValue:[aClip stringValue]];
	[clip setRTFData:[aClip RTFData]];
//	[clip setRTF:[aClip RTF]];
//	[clip setRTFD:[aClip RTFD]];
	[clip setPDF:[aClip PDF]];
	[clip setFilenames:[aClip filenames]];
	[clip setURL:[aClip URL]];
	[clip setImage:[aClip image]];
	
	return clip;
}

- (void)dealloc
{
	[types release], types = nil;
	[createdDate release], createdDate = nil;
	[lastUsedDate release], lastUsedDate = nil;
	[stringValue release], stringValue = nil;
	[RTFData release], RTFData = nil;
//	[RTF release], RTF = nil;
//	[RTFD release], RTFD = nil;
	[PDF release], PDF = nil;
	[filenames release], filenames = nil;
	[URL release], URL = nil;
	[image release], image = nil;
	[thumbnail release], thumbnail = nil;
	
	[super dealloc];
}

#pragma mark - Copying -

- (id)copyWithZone:(NSZone *)zone
{
	return [[[self class] allocWithZone:zone] initWithClip:self];
}

#pragma mark - Archiving -

- (void)encodeWithCoder:(NSCoder *)encoder
{
	[encoder encodeObject:self.types forKey:TYPES_KEY];
	[encoder encodeObject:self.createdDate forKey:CREATED_DATE_KEY];
	[encoder encodeObject:self.lastUsedDate forKey:LAST_USED_DATE_KEY];
	[encoder encodeObject:self.stringValue forKey:STRING_VALUE_KEY];
	[encoder encodeObject:self.RTFData forKey:RTFDATA_KEY];
//	[encoder encodeObject:self.RTF forKey:RTF_KEY];
//	[encoder encodeObject:self.RTFD forKey:RTFD_KEY];
	[encoder encodeObject:self.PDF forKey:PDF_KEY];
	[encoder encodeObject:self.filenames forKey:FILENAMES_KEY];
	[encoder encodeObject:self.URL forKey:URL_KEY];
	[encoder encodeObject:self.image forKey:IMAGE_KEY];
}

- (id)initWithCoder:(NSCoder *)decoder
{
	self = [super init];
	if (self) {
		NSDate *createdAt = [decoder decodeObjectForKey:CREATED_DATE_KEY];
		if (createdAt == nil) {
			createdAt = [NSDate date];
		}
		
		NSDate *usedAt = [decoder decodeObjectForKey:LAST_USED_DATE_KEY];
		if (usedAt == nil) {
			usedAt = [decoder decodeObjectForKey:@"lastAccessedDate"];		// ivar name of v0.4.2a2 to v0.4.2a4
			if (usedAt == nil) {
				usedAt = createdAt;
			}
		}
		
		NSData *rtfData = [decoder decodeObjectForKey:RTFDATA_KEY];
		if (rtfData == nil) {
			rtfData = [decoder decodeObjectForKey:RTFD_KEY];
			if (rtfData == nil) {
				rtfData = [decoder decodeObjectForKey:RTF_KEY];
			}
		}
		
		[self setTypes:[decoder decodeObjectForKey:TYPES_KEY]];
		[self setCreatedDate:createdAt];
		[self setLastUsedDate:usedAt];
		[self setStringValue:[decoder decodeObjectForKey:STRING_VALUE_KEY]];
		[self setRTFData:rtfData];
//		[self setRTF:[decoder decodeObjectForKey:RTF_KEY]];
//		[self setRTFD:[decoder decodeObjectForKey:RTFD_KEY]];
		[self setPDF:[decoder decodeObjectForKey:PDF_KEY]];
		[self setFilenames:[decoder decodeObjectForKey:FILENAMES_KEY]];
		[self setURL:[decoder decodeObjectForKey:URL_KEY]];
		[self setImage:[decoder decodeObjectForKey:IMAGE_KEY]];
	}
	return self;
}

#pragma mark -

- (NSString *)description
{
	return [NSString stringWithFormat:@"types: %@\nstring: %@", self.types, self.stringValue];
}

- (NSString *)primaryPboardType
{
	if (!self.types || [self.types count] < 0) {
		return nil;
	}
	
	return [self.types objectAtIndex:0];
}

- (NSImage *)thumbnailOfSize:(NSSize)size
{
	if (thumbnail &&
		NSEqualSizes(thumbnailSize, size)) {
//		NSLog(@"cachedSize: %@", NSStringFromSize(thumbnailSize));
		return thumbnail;
	}
		
	NSArray *representations = [self.image representations];
	NSBitmapImageRep *bitmapRep = nil;
	
	for (NSImageRep *rep in representations) {
		if ([rep isKindOfClass:[NSBitmapImageRep class]]) {
			bitmapRep = (NSBitmapImageRep *)rep;
			break;
		}
	}
	
	if (bitmapRep == nil) {
		return nil;
	}
	
	NSInteger origWidth = [bitmapRep pixelsWide];
	NSInteger origHeight = [bitmapRep pixelsHigh];
	
	CGFloat aspect = (CGFloat)origWidth / (CGFloat)origHeight;
	
//	NSLog(@"width: %d, height: %d, aspect: %f", origWidth, origHeight, aspect);
	
	CGFloat targetWidth = size.width;
	CGFloat targetHeight = size.height;
	CGFloat newWidth;
	CGFloat newHeight;
	
	/* Resize */
	/* from Zachary Wily's NSBitmapImageRep+sizing.m of iPhotoToGallery */
	/* http://github.com/zwily/iphototogallery */
	if (1 <= aspect) {
		newWidth = targetWidth;
		newHeight = newWidth / aspect;
		
		if (targetHeight < newHeight) {
			newHeight = targetHeight;
			newWidth = targetHeight * aspect;
		}
	}
	else {
		newHeight = targetHeight;
		newWidth = targetHeight * aspect;
		
		if (targetWidth < newWidth) {
			newWidth = targetWidth;
			newHeight = targetWidth / aspect;
		}
	}
	
	// Don't go any bigger!
	if (origWidth < newWidth) {
		newWidth = origWidth;
	}
	
	if (origHeight < newHeight) {
		newHeight = origHeight;
	}
	
	/* Make new image representation */
	NSImageRep *newImageRep;
	
	if ([self.image respondsToSelector:@selector( bestRepresentationForRect:context:hints: )]) {
		/* Mac OS X 10.6 and later */
		newImageRep = [self.image bestRepresentationForRect:NSMakeRect(0, 0, newWidth, newHeight)
													context:nil
													  hints:nil]; 
	}
	else {
		newImageRep = [self _representationOfBitmapImageRep:bitmapRep
												   withSize:NSMakeSize(newWidth, newHeight)];
	}
	
	if (newImageRep == nil) {
//		NSLog(@"No newImageRep");
		return nil;
	}

	thumbnail = [[NSImage alloc] initWithSize:NSMakeSize(newWidth, newHeight)];
	[thumbnail addRepresentation:newImageRep];
	
	thumbnailSize = size;
//	[self.image setCacheMode:NSImageCacheNever];

	return thumbnail;
}

#pragma mark - Override -

NSUInteger
integerFromBytes(uint8_t * bytes, NSUInteger length)
{
    NSUInteger i, value = 0;
    for (i = 0; i < length; i++)
        value = (value << 8) | bytes[i];
    return value;
}

- (NSUInteger)hash
{
//	if (cachedHash) {
////		NSLog(@"cached hash: %u\n", cachedHash);
//		return cachedHash;
//	}
	
	cachedHash = 0;
	
	cachedHash = [[self.types componentsJoinedByString:@""] hash];
	
	
	if (self.image) {
//		NSLog(@"image: %u", [[self.image TIFFRepresentation] length]);
		cachedHash ^= [[self.image TIFFRepresentation] length];
	}
	
	if (self.filenames) {
//		NSLog(@"filenames: %@", self.filenames);
		for (NSString *filename in filenames) {
//			NSLog(@"f: %d", [filename hash]);
			cachedHash ^= [filename hash];
		}
	}
	else if (self.URL) {
//		NSLog(@"URL: %@", self.URL);
		for (NSString *aURL in URL) {
//			NSLog(@"aURL: %d", [aURL hash]);
			cachedHash ^= [aURL hash];
		}
	}	
	else if (self.PDF) {
		cachedHash ^= [self.PDF length];
	}
	else if (self.stringValue) {
//		NSLog(@"String: %u", [self.stringValue hash]);
		cachedHash ^= [self.stringValue hash];
	}

	if (self.RTFData) {
		/* Despite attributes modified, length doesn't change. Why? */
		
//		NSLog(@"RTFData: %qu", [self.RTFData length]);
		
//		NSData *rtfData = self.RTFData;
//		NSUInteger rtfLength = [rtfData length];
//		unsigned char *buffer = NSZoneMalloc([self zone], rtfLength);
//		[rtfData getBytes:buffer length:rtfLength];
//		NSLog(@"bytes: %qi", buffer);
//		
//		
//		NSUInteger v = 0;
//		for (NSUInteger i = 0; i < rtfLength; i++) {
////			v += buffer[i];
//			char c = buffer[i];
////			NSLog(@"c: %d", (int)c);
//			v += (int)(c);
//		}
//		
//		NSLog(@"casted buffer: %d", v);
//
////		cachedHash ^= (NSUInteger)*buffer;
//		NSZoneFree([self zone], buffer);

		cachedHash ^= [self.RTFData length];
	}
	
//	if (self.RTFD) {
////		NSLog(@"RTFD");
//		cachedHash ^= [self.RTFD length];
//	}
//	else if (self.RTF) {
////		NSLog(@"RTF: %u", [self.RTF length]);
//		cachedHash ^= [self.RTF length];
//	}
	
//	NSLog(@"hash: %u\n", cachedHash);
		
	return cachedHash;
}

- (BOOL)isEqual:(id)anObject
{
	if (anObject == self) {
		return YES;
	}
	
	if (!anObject || ![anObject isKindOfClass:[Clip class]]) {
		return NO;
	}
	
	if ([self hash] == [anObject hash]) {
		return YES;
	}
	
	return NO;
}

//- (id)valueForKey:(NSString *)key
//{
//	id value;
//	
//	if ([key isEqualToString:@"stringValue"]) {
//		value = @"stringValue";
//	}
//	else {
//		value = [super valueForKey:key];
//	}
//	
//	return value;
//}

#pragma mark Private

/* from Zachary Wily's NSBitmapImageRep+sizing.m of iPhotoToGallery */
/* http://github.com/zwily/iphototogallery */
- (NSBitmapImageRep *)_representationOfBitmapImageRep:(NSBitmapImageRep *)bitmapRep withSize:(NSSize)size
{
    NSRect rect = NSMakeRect(0, 0, size.width, size.height);
    NSImage *anImage = [[[NSImage alloc] initWithSize:size] autorelease];
    NSBitmapImageRep *outRep;
    [anImage lockFocus];
    [[NSGraphicsContext currentContext] setImageInterpolation: NSImageInterpolationHigh];
    [[NSGraphicsContext currentContext] setShouldAntialias:YES];
    [bitmapRep drawInRect:rect];
    outRep = [[[NSBitmapImageRep alloc] initWithFocusedViewRect:rect] autorelease];
    [anImage unlockFocus];
    return outRep;
}

@end
