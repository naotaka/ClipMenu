//
//  ClipsController.m
//  ClipMenu
//
//  Created by Naotaka Morimoto on 07/12/02.
//  Copyright 2007 Naotaka Morimoto. All rights reserved.
//

#import "ClipsController.h"
#import "Clip.h"
#import "constants.h"
#import "CMUtilities.h"
#import "PrefsWindowController.h"
#import "MenuController.h"


#define MAX_TIME_INTERVAL 1.0
#define MIN_AUTOSAVE_INTERVAL 15

static ClipsController *sharedInstance = nil;


@interface ClipsController ()
- (void)_updateClips:(id)sender;
- (Clip *)_makeClipFromPasteboard:(NSPasteboard *)pboard;
- (NSArray *)_makeTypesFromPasteboard:(NSPasteboard *)pboard;
- (BOOL)_storeType:(NSString *)type;
- (BOOL)_frontProcessIsInExcludeList;

- (void)_trimHistorySize;
- (void)_startPasteboardObservingTimer;
- (void)_autosave;
- (void)_fireSaveClips;

- (NSString *)_saveFilePath;

- (id)_init;
@end


#pragma mark -

@implementation ClipsController

@synthesize clips;
@synthesize storeTypes;
@synthesize excludeIdentifiers;
@synthesize maxClipsSize;
@synthesize cachedChangeCount;
@synthesize lastClipsUpdated;
@synthesize lastSaved;
//@synthesize isHalted;
@dynamic sortedClips;

#pragma mark Initialize

+ (void)initialize
{
	if (sharedInstance == nil) {
		sharedInstance = [[self alloc] _init];
	}
}

+ (ClipsController *)sharedInstance
{
	return [[sharedInstance retain] autorelease];
}

- (id)init
{
	NSAssert(self != sharedInstance, @"Should never send init to the singleton instance");
	
	[self release];
	[sharedInstance retain];
	return sharedInstance;
}

- (NSSet *)_getExcludeBundleIdentifiersFromList:(NSArray *)excludeList
{
	if ([excludeList count] == 0) {
		return nil;
	}
	
	NSArray *values = [excludeList valueForKey:kCMBundleIdentifierKey];
	return [NSSet setWithArray:values];
}

- (id)_init
{
	self = [super init];
	if (self) {
		NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
		
		[self setClips:[NSMutableSet set]];
		[self setStoreTypes:[defaults objectForKey:CMPrefStoreTypesKey]];
		[self setMaxClipsSize:[defaults integerForKey:CMPrefMaxHistorySizeKey]];
		
		/* Exclude Identifiers */
		NSArray *excludeList = [defaults objectForKey:CMPrefExcludeAppsKey];
//		NSSet *set = nil;
//		
//		if (excludeList && 0 < [excludeList count]) {
//			NSArray *values = [excludeList valueForKey:kCMBundleIdentifierKey];
//			set = [NSSet setWithArray:values];
//		}
		
		NSSet *set = [self _getExcludeBundleIdentifiersFromList:excludeList];
		
		if (set) {
			[self setExcludeIdentifiers:set];
		}
		else {
			[self setExcludeIdentifiers:[NSSet set]];
		}
		
		/* Date */
		NSDate *now;
		
		now = [[NSDate alloc] init];
		[self setLastClipsUpdated:now];
		[now release], now = nil;
		
		now = [[NSDate alloc] initWithTimeIntervalSinceNow:1];
		[self setLastSaved:now];
		[now release], now = nil;
		
		/* Timer */
		[self _startPasteboardObservingTimer];
		[self startAutosaveTimer];
		
		/* KVO */
		[defaults addObserver:self
				   forKeyPath:CMPrefMaxHistorySizeKey
					  options:NSKeyValueObservingOptionNew
					  context:nil];
		[defaults addObserver:self
				   forKeyPath:CMPrefAutosaveDelayKey
					  options:NSKeyValueObservingOptionNew
					  context:nil];
		[defaults addObserver:self
				   forKeyPath:CMPrefTimeIntervalKey
					  options:NSKeyValueObservingOptionNew
					  context:nil];
		[defaults addObserver:self
				   forKeyPath:CMPrefStoreTypesKey
					  options:NSKeyValueObservingOptionNew
					  context:nil];
		[defaults addObserver:self
				   forKeyPath:CMPrefExcludeAppsKey
					  options:NSKeyValueObservingOptionNew
					  context:nil];
	}
	return self;
}

- (void)dealloc
{
	/* KVO */
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	[defaults removeObserver:self forKeyPath:CMPrefMaxHistorySizeKey];
	[defaults removeObserver:self forKeyPath:CMPrefAutosaveDelayKey];
	[defaults removeObserver:self forKeyPath:CMPrefTimeIntervalKey];
	[defaults removeObserver:self forKeyPath:CMPrefStoreTypesKey];
	[defaults removeObserver:self forKeyPath:CMPrefExcludeAppsKey];
	
	[clips release], clips = nil;
	[storeTypes release], storeTypes = nil;
	[excludeIdentifiers release], excludeIdentifiers = nil;
	[lastClipsUpdated release], lastClipsUpdated = nil;
	[lastSaved release], lastSaved = nil;
	
	if (pboardObservingTimer) {
		[pboardObservingTimer invalidate];
		pboardObservingTimer = nil;
	}
	
	if (autosaveTimer) {
		[autosaveTimer invalidate];
		autosaveTimer = nil;
	}
	
	[super dealloc];
}

#pragma mark -
#pragma mark Accessors

#pragma mark - ReadOnly-

- (NSArray *)sortedClips
{
	BOOL reorder = [[NSUserDefaults standardUserDefaults] boolForKey:CMPrefReorderClipsAfterPasting];
	NSString *key = (reorder) ? @"lastUsedDate" : @"createdDate";
	
	NSSortDescriptor *descriptor = [[NSSortDescriptor alloc] initWithKey:key ascending:NO];
	NSArray *descriptors = [[NSArray alloc] initWithObjects:descriptor, nil];
	[descriptor release], descriptor = nil;
	
	NSArray *results;
	
	if ([clips respondsToSelector:@selector( sortedArrayUsingDescriptors: )]) {
		/* Mac OS X 10.6 and lator */
		results = [self.clips sortedArrayUsingDescriptors:descriptors];
	}
	else {
		results = [[self.clips allObjects] sortedArrayUsingDescriptors:descriptors];
	}
	
	[descriptors release], descriptors = nil;
	
	return results;
}

#pragma mark - Write -

- (void)setClips:(NSMutableSet *)newClips
{
	if (clips != newClips) {
		[clips release];
		clips = [newClips mutableCopy];
	}
}

#pragma mark -
#pragma mark KVO

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
//	NSLog(@"observeValueForKeyPath: %@", keyPath);
	
	if ([keyPath isEqualToString:CMPrefMaxHistorySizeKey]) {
		[self _trimHistorySize];
	}
	else if ([keyPath isEqualToString:CMPrefAutosaveDelayKey]) {
		[self startAutosaveTimer];
	}
	else if ([keyPath isEqualToString:CMPrefTimeIntervalKey]) {
		[self _startPasteboardObservingTimer];
	}
	else if ([keyPath isEqualToString:CMPrefStoreTypesKey]) {
		NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
		[self setValue:[defaults objectForKey:CMPrefStoreTypesKey] forKey:@"storeTypes"];
	}	
	else if ([keyPath isEqualToString:CMPrefExcludeAppsKey]) {
		NSArray *excludeList = [change objectForKey:@"new"];
		
		NSSet *set = [self _getExcludeBundleIdentifiersFromList:excludeList];
		
		if (set) {
			[self setExcludeIdentifiers:set];
		}
		else {
			[self setExcludeIdentifiers:[NSSet set]];
		}
	}
}

#pragma mark -
#pragma mark Public

- (void)startAutosaveTimer
{	
	[self stopAutosaveTimer];
	
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	NSUInteger timeInterval = [defaults integerForKey:CMPrefAutosaveDelayKey];
	
	if (timeInterval == 0) {
		return;
	}
	else if (timeInterval < MIN_AUTOSAVE_INTERVAL) {
		timeInterval = MIN_AUTOSAVE_INTERVAL;
	}
	
	autosaveTimer = [NSTimer scheduledTimerWithTimeInterval:timeInterval
													 target:self
												   selector:@selector( _autosave )
												   userInfo:nil
													repeats:YES];
}

- (void)stopAutosaveTimer
{
	if (autosaveTimer) {
		[autosaveTimer invalidate];
		autosaveTimer = nil;
	}
}

- (BOOL)saveClips
{
	BOOL result = NO;

	NSString *path = [CMUtilities applicationSupportFolder];
	if ([CMUtilities prepareSaveToPath:path]) {
		result = [NSKeyedArchiver archiveRootObject:self.sortedClips toFile:[self _saveFilePath]];
	}
	
	return result;
}

- (void)loadClips
{
	NSMutableArray *loadedData = [NSKeyedUnarchiver unarchiveObjectWithFile:[self _saveFilePath]];
	if (loadedData == nil) {
		return;
	}
				
	[self setClips:[NSMutableSet setWithArray:loadedData]];
	[self _trimHistorySize];
}

- (void)removeClips
{
	NSFileManager *fileManager = [NSFileManager defaultManager];
	NSString *path = [self _saveFilePath];
	if ([fileManager fileExistsAtPath:path]) {
		NSError *error = nil;
		[fileManager removeItemAtPath:path error:&error];
	}
}

- (BOOL)exportHistoryStringsAsSingleFile:(NSString *)path
{
	if ([self.clips count] == 0) {
		return YES;
	}
	
	NSFileManager *fileManager = [NSFileManager defaultManager];
	NSError *error = nil;
	BOOL success;
	
	if ([fileManager fileExistsAtPath:path]) {
		success = [fileManager removeItemAtPath:path error:&error];
		if (!success) {
			NSLog(@"Error removing file at %@\n%@", path, [error localizedDescription]);
			return NO;
		}
	}
	
	NSString *separator;
	NSUInteger tag = [[NSUserDefaults standardUserDefaults] 
					  integerForKey:CMPrefTagOfSeparatorForExportHistoryToFileKey];
	switch (tag) {
		case 1:
			separator = kNewLine;
			break;
		case 2:
			separator = kCarriageReturnAndNewLine;
			break;
		case 3:
			separator = kCarriageReturn;
			break;
		case 4:
			separator = kTab;
			break;
		case 5:
			separator = kSingleSpace;
			break;
		case 0:
		default:
			separator = kEmptyString;
			break;
	}
	
	NSEnumerator *enumerator = [self.sortedClips objectEnumerator];
	Clip *clip;
	NSString *stringWithSeparator;
	NSFileHandle *outFile;
	NSData *data;
	const char *utf8String;
	
	while ((clip = [enumerator nextObject])) {
		//		NSLog(@"item: %@", clip);
		
		if (![clip.types containsObject:NSStringPboardType]) {
			continue;
		}
		
		stringWithSeparator = [NSString stringWithFormat:@"%@%@", clip.stringValue, separator];
		
		if ([fileManager fileExistsAtPath:path]) {
			outFile = [NSFileHandle fileHandleForWritingAtPath:path];
			[outFile seekToEndOfFile];
			
			utf8String = [stringWithSeparator UTF8String];
			data = [[NSData alloc] initWithBytes:utf8String length:strlen(utf8String)];
			[outFile writeData:data];
			[data release], data = nil;
			
			[outFile closeFile];
		}
		else {
			error = nil;
			success = [stringWithSeparator writeToFile:path
											atomically:YES
											  encoding:NSUTF8StringEncoding
												 error:&error];
			if (!success) {
				NSLog(@"Error writing file at %@\n%@", path, [error localizedDescription]);
				return NO;
			}
		}
}	
	
//	NSLog(@"Finished export history");
	return YES;
}

- (BOOL)exportHistoryStringsAsMultipleFiles:(NSString *)path
{
	if ([self.clips count] == 0) {
		return YES;
	}
	
	NSURL *destURL = [NSURL fileURLWithPath:path];
	BOOL isSnowLeopardAndLator = [destURL respondsToSelector:@selector( URLByAppendingPathComponent: )];
	
	NSURL *outputFileURL;
	NSString *filename;
	NSString *extension = @"txt";
	NSError *error = nil;
	BOOL success;
	NSUInteger i = 0;
	
	for (Clip *clip in self.sortedClips) {
		i++;

		if (![clip.types containsObject:NSStringPboardType]) {
			continue;
		}
				
		filename = [NSString stringWithFormat:@"%u.%@", i, extension];	// 32-bit unsighed integer
//		NSLog(@"filename: %@", filename);
		
		if (isSnowLeopardAndLator) {
			/* Mac OS X 10.6 and lator */
			outputFileURL = [destURL URLByAppendingPathComponent:filename];
		}
		else {
			/* Mac OS X 10.5 and earlier */
			outputFileURL = [NSURL fileURLWithPath:[NSString stringWithFormat:
													@"%@/%@", path, filename]]; 
		}
		
		success = [clip.stringValue writeToURL:outputFileURL
									atomically:YES
									  encoding:NSUTF8StringEncoding
										 error:&error];
		if (!success) {
			NSLog(@"Error writing file at %@\n%@", outputFileURL, [error localizedDescription]);
			return NO;
		}					  
	}
	
	return YES;
}

- (void)clearAll
{
	[self willChangeValueForKey:@"clips"];
	[self.clips removeAllObjects];
	[self didChangeValueForKey:@"clips"];
}

- (Clip *)clipAtIndex:(NSUInteger)index
{
	return [self.sortedClips objectAtIndex:index];
}

- (BOOL)removeClipAtIndex:(NSUInteger)index
{
	Clip *clip = [self.sortedClips objectAtIndex:index];
	
//	@try {
//		[self willChangeValueForKey:@"clips"];
//		[self.clips removeObject:clip];
//		[self didChangeValueForKey:@"clips"];
//	}
//	@catch (NSException *ex) {
//		return NO;
//	}
//
//	return YES;
	
	return [self removeClip:clip];
}

- (BOOL)removeClip:(Clip *)clip
{
	@try {
		[self willChangeValueForKey:@"clips"];
		[self.clips removeObject:clip];
		[self didChangeValueForKey:@"clips"];
	}
	@catch (NSException *ex) {
		return NO;
	}

	return YES;
}

- (void)copyStringToPasteboard:(NSString *)aString
{
	NSPasteboard *pboard = [NSPasteboard generalPasteboard];
	[pboard declareTypes:[NSArray arrayWithObject:NSStringPboardType] owner:self];
	[pboard setString:aString forType:NSStringPboardType];
}

- (void)copyClipToPasteboard:(Clip *)clip
{	
	NSArray *types = [clip types];

	NSPasteboard *pboard = [NSPasteboard generalPasteboard];
	[pboard declareTypes:types owner:self];
	
	for (NSString *pbType in types) {
		/* stringValue */
		if ([pbType isEqualToString:NSStringPboardType]) {
			NSString *pbString = ([clip stringValue]) ? [clip stringValue] : kEmptyString;
			[pboard setString:pbString forType:NSStringPboardType];
		}
		/* RTFD */
		else if ([pbType isEqualToString:NSRTFDPboardType]) {
//			NSData *rtfData = [clip RTFD];
			NSData *rtfData = [clip RTFData];
			[pboard setData:rtfData forType:NSRTFDPboardType];
		}
		/* RTF */
		else if ([pbType isEqualToString:NSRTFPboardType]) {
//			NSData *rtfData = [clip RTF];
			NSData *rtfData = [clip RTFData];
			[pboard setData:rtfData forType:NSRTFPboardType];
		}
		/* PDF */
		else if ([pbType isEqualToString:NSPDFPboardType]) {
			NSData *pdfData = [clip PDF];
			NSPDFImageRep *pdfRep = [NSPDFImageRep imageRepWithData:pdfData];
			[pboard setData:[pdfRep PDFRepresentation] forType:NSPDFPboardType];
		}
		/* filenames */
		else if ([pbType isEqualToString:NSFilenamesPboardType]) {
			NSArray *filenames = [clip filenames];
			[pboard setPropertyList:filenames forType:NSFilenamesPboardType];
		}
		/* URL */
		else if ([pbType isEqualToString:NSURLPboardType]) {
			NSArray *url = [clip URL];
			[pboard setPropertyList:url forType:NSURLPboardType];
		}
		/* image */
		else if ([pbType isEqualToString:NSTIFFPboardType] ||
				 [pbType isEqualToString:NSPICTPboardType]) {
			NSImage *image = [clip image];
			if (image) {
				[pboard setData:[image TIFFRepresentation] forType:NSTIFFPboardType];
			}
		}
	}
}

- (void)copyClipToPasteboardAtIndex:(NSUInteger)index
{
	Clip *clip = [self.sortedClips objectAtIndex:index];	
	[self copyClipToPasteboard:clip];
}

//- (void)startUpdate
//{
//	[self setIsHalted:NO];
//}
//
//- (void)restartUpdate
//{
//	[self copyClipToPasteboardAtIndex:0];
//	[self startUpdate];
//}
//
//- (void)haltUpdate
//{
//	[self setIsHalted:YES];
//}

#pragma mark -
#pragma mark Private

- (void)_updateClips:(id)sender
{
//	/* Check recording mode */
//	if (isHalted) {
//		return;
//	}
	
	/* Check changeCount */
	NSPasteboard *pboard = [NSPasteboard generalPasteboard];

//	NSLog(@"changeCount: %d", [pboard changeCount]);

	if ([pboard changeCount] == cachedChangeCount) {
		return;
	}
	
	self.cachedChangeCount = [pboard changeCount];
	
	/* Exclude apps */
	if ([self _frontProcessIsInExcludeList]) {
		return;
	}
	
	/* Make new clip */
	Clip *clip = [self _makeClipFromPasteboard:pboard];
	if (clip == nil) {
		return;
	}
	
	/* Make proxy */
	NSMutableSet *clipsProxy = [self mutableSetValueForKey:@"clips"];
		
	/* Check dupulication and re-order */
	if (0 < [clipsProxy count]) {		
		if ([clipsProxy containsObject:clip]) {
//			NSLog(@"The new clip is already a member: %u", [clip hash]);
		
			NSNumber *hashNumber = [NSNumber numberWithUnsignedInteger:[clip hash]];
			NSPredicate *predicate = [NSPredicate predicateWithFormat:@"hash == %@", hashNumber];
//			NSLog(@"filterd: %@", [clipsProxy filteredSetUsingPredicate:predicate]);
			
			Clip *existedClip = [[clipsProxy filteredSetUsingPredicate:predicate] anyObject];
			if (existedClip) {
				[self willChangeValueForKey:@"clips"];
				[existedClip setLastUsedDate:[NSDate date]];
				[self didChangeValueForKey:@"clips"];
			}
			
			return;
		}
	}		
	
	/* Add clip to clips */	
	[clipsProxy addObject:clip];
	
	/* Check clips size */
	[self _trimHistorySize];
	
	/* Updated time */
	NSDate *now = [[NSDate alloc] init];
	[self setLastClipsUpdated:now];
	[now release], now = nil;
}

- (Clip *)_makeClipFromPasteboard:(NSPasteboard *)pboard
{		
//	NSPasteboard *pboard = [NSPasteboard generalPasteboard];
//	
////	NSLog(@"changeCount: %d", [pboard changeCount]);
//	
//	/* Check changeCount */
//	if ([pboard changeCount] == cachedChangeCount) {
//		return nil;
//	}
//	[self setValue:[NSNumber numberWithInt:[pboard changeCount]] forKey:@"cachedChangeCount"];
	
	/* make new clip */
	Clip *clip = [[[Clip alloc] init] autorelease];
	
	/* types */
	NSArray *types = [self _makeTypesFromPasteboard:pboard];
//	NSLog(@"types:\r%@", types);
	
	if ([types count] == 0) {
//		NSLog(@"types count is %d. return nil.", [types count]);		
		return nil;
	}
		
	if (![[storeTypes allValues] containsObject:[NSNumber numberWithBool:YES]]) {
//		NSLog(@"storeTypes does not contain YES. return nil.");
		return nil;
	}
	
	[clip setValue:types forKey:@"types"];
	
	for (NSString *pbType in types) {
//		NSLog(@"available types: %d", [self _storeType:pbType]);

		/* stringValue */
		if ([pbType isEqualToString:NSStringPboardType]) {
			NSString *pbString = [pboard stringForType:NSStringPboardType];			
			[clip setValue:pbString forKey:@"stringValue"];
		}
		/*RTFD */
		else if ([pbType isEqualToString:NSRTFDPboardType]) {
			NSData *rtfData = [pboard dataForType:NSRTFDPboardType];
//			[clip setValue:rtfData forKey:@"RTFD"];
			[clip setValue:rtfData forKey:@"RTFData"];
		}
		/* RTF */
		else if ([pbType isEqualToString:NSRTFPboardType] && (clip.RTFData == nil)) {
			NSData *rtfData = [pboard dataForType:NSRTFPboardType];
//			[clip setValue:rtfData forKey:@"RTF"];
			[clip setValue:rtfData forKey:@"RTFData"];
		}
		/* PDF */
		else if ([pbType isEqualToString:NSPDFPboardType]) {
			NSData *pdfData = [pboard dataForType:NSPDFPboardType];
			[clip setValue:pdfData forKey:@"PDF"];
		}
		/* filenames */
		else if ([pbType isEqualToString:NSFilenamesPboardType]) {
			//		NSLog(@"filenames: %@", [pboard propertyListForType:NSFilenamesPboardType]);
			NSArray *filenames = [pboard propertyListForType:NSFilenamesPboardType];
			[clip setValue:filenames forKey:@"filenames"];
		}
		/* URL */
		else if ([pbType isEqualToString:NSURLPboardType]) {
			NSArray *url = [pboard propertyListForType:NSURLPboardType];
			[clip setValue:url forKey:@"URL"];
		}
		/* image */
		else if ([pbType isEqualToString:NSTIFFPboardType] || [pbType isEqualToString:NSPICTPboardType]) {
			if ([NSImage canInitWithPasteboard:pboard]) {
				NSImage *image = [[NSImage alloc] initWithPasteboard:pboard];
				[clip setValue:image forKey:@"image"];
				[image release], image = nil;
			}
		}
	}
	
	return clip;
}

- (NSArray *)_makeTypesFromPasteboard:(NSPasteboard *)pboard
{
	NSMutableArray *types = [NSMutableArray array];
	
	NSArray *pbTypes = [pboard types];	
//	NSLog(@"pbTypes: %@", pbTypes);
	
	for (NSString *dataType in pbTypes) {		
		if ([self _storeType:dataType] != YES) {
			continue;
		}
		
//		NSLog(@"type: %@, %d", dataType, [self _storeType:dataType]);
		
		if ([dataType isEqualToString:NSTIFFPboardType] ||
			[dataType isEqualToString:NSPICTPboardType]) {
			if ([types containsObject:NSTIFFPboardType]) {
				continue;
			}
			[types addObject:NSTIFFPboardType];
		}
		else {
			[types addObject:dataType];
		}
	}
	
//	NSLog(@"types: %@", types);
	
	return types;
}

- (BOOL)_storeType:(NSString *)type
{
	NSDictionary *typeDict = [Clip availableTypeDictionary];
	return [[storeTypes objectForKey:[typeDict objectForKey:type]] boolValue];
}

- (BOOL)_frontProcessIsInExcludeList
{	
//	NSLog(@"excludeIdentifiers: %@", self.excludeIdentifiers);

	BOOL result = NO;
	
	if ([self.excludeIdentifiers count] == 0) {
		return result;
	}
		
	ProcessSerialNumber psn;
	GetFrontProcess(&psn);
	NSDictionary *processInfo = (NSDictionary *)ProcessInformationCopyDictionary(&psn, kProcessDictionaryIncludeAllInformationMask);
	
	NSString *bundleIdentifier = [processInfo objectForKey:(NSString *)kCFBundleIdentifierKey];
	if (bundleIdentifier && [self.excludeIdentifiers containsObject:bundleIdentifier]) {
//		NSLog(@"processInfo: %@", processInfo);
		result = YES;
	}
	
	if (processInfo) {
		CFRelease(processInfo);
	}
		
	return result;
}

- (void)_trimHistorySize
{
	NSMutableSet *clipsProxy = [self mutableSetValueForKey:@"clips"];
	NSUInteger currentSize = [clipsProxy count];
	NSUInteger maxHistorySize = [[NSUserDefaults standardUserDefaults] integerForKey:CMPrefMaxHistorySizeKey];
	
	if (maxHistorySize < currentSize) {
		NSUInteger delta = currentSize - maxHistorySize;
		NSRange range = NSMakeRange(currentSize-delta, delta);
		NSIndexSet *indexSet = [[NSIndexSet alloc] initWithIndexesInRange:range]; 
		
		NSArray *removeObjects = [self.sortedClips objectsAtIndexes:indexSet];
		[indexSet release], indexSet = nil;
		
		for (Clip *removeObject in removeObjects) {
			[clipsProxy removeObject:removeObject];
		}
	}
}

- (void)_startPasteboardObservingTimer
{
	if (pboardObservingTimer) {
		[pboardObservingTimer invalidate];
	}
	
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	CGFloat timeInterval = [defaults floatForKey:CMPrefTimeIntervalKey];
	if (timeInterval > MAX_TIME_INTERVAL) {
		timeInterval = MAX_TIME_INTERVAL;
		[defaults setFloat:timeInterval forKey:CMPrefTimeIntervalKey];
	}
	
	pboardObservingTimer = [NSTimer scheduledTimerWithTimeInterval:timeInterval
															target:self
														  selector:@selector( _updateClips: )
														  userInfo:nil 
														   repeats:YES];
}

#pragma mark - Autosave -

- (void)_autosave
{
//	NSLog(@"_autosave | updated: %@ | saved: %@", self.lastClipsUpdated, self.lastSaved);
	
	if ([self.lastSaved compare:self.lastClipsUpdated] == NSOrderedDescending) {
		return;
	}
	
	[NSThread detachNewThreadSelector:@selector( _fireSaveClips )
							 toTarget:self
						   withObject:nil];
}

- (void)_fireSaveClips
{	
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	
//	NSLog(@"_autosave");

	BOOL result = [self saveClips];
		
	if (result == YES) {
		NSDate *now = [[NSDate alloc] init];
		[self setLastSaved:now];
		[now release], now = nil;
	}
	else {
		[self stopAutosaveTimer];
		
		[NSApp activateIgnoringOtherApps:YES];
		NSRunAlertPanel(NSLocalizedString(@"Error", nil),
						NSLocalizedString(@"Could not save your clipboard history to file.", nil),
						NSLocalizedString(@"OK", nil),
						nil,
						nil);
		
		[self startAutosaveTimer];
	}
	
	[pool release], pool = nil;
}

#pragma mark - Archiver -

- (NSString *)_saveFilePath
{
	return [[CMUtilities applicationSupportFolder] stringByAppendingPathComponent:kClipsSaveDataName];
}

@end
