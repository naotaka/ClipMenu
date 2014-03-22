//
//  ClipsController.h
//  ClipMenu
//
//  Created by Naotaka Morimoto on 07/12/02.
//  Copyright 2007 Naotaka Morimoto. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@class Clip;

@interface ClipsController : NSObject 
{
	NSMutableSet *clips;			// use "mutableArrayValueForKey" to access
	NSDictionary *storeTypes;
	NSSet *excludeIdentifiers;
	NSUInteger maxClipsSize;
	NSUInteger cachedChangeCount;
	
	NSDate *lastClipsUpdated;
	NSDate *lastSaved;
	
	NSTimer *pboardObservingTimer;
	NSTimer *autosaveTimer;
	
//	BOOL isHalted;
}
@property (nonatomic, copy) NSMutableSet *clips;
@property (nonatomic, retain) NSDictionary *storeTypes;
@property (nonatomic, retain) NSSet *excludeIdentifiers;
@property (nonatomic, assign) NSUInteger maxClipsSize;
@property (nonatomic, assign) NSUInteger cachedChangeCount;
@property (nonatomic, retain) NSDate *lastClipsUpdated;
@property (nonatomic, retain) NSDate *lastSaved;
//@property (nonatomic, assign) BOOL isHalted;
@property (readonly) NSArray *sortedClips;

+ (ClipsController *)sharedInstance;

- (void)startAutosaveTimer;
- (void)stopAutosaveTimer;

- (BOOL)saveClips;
- (void)loadClips;
- (void)removeClips;

- (BOOL)exportHistoryStringsAsSingleFile:(NSString *)path;
- (BOOL)exportHistoryStringsAsMultipleFiles:(NSString *)path;

- (void)clearAll;
- (Clip *)clipAtIndex:(NSUInteger)index;
- (BOOL)removeClipAtIndex:(NSUInteger)index;
- (BOOL)removeClip:(Clip *)clip;
- (void)copyStringToPasteboard:(NSString *)aString;
- (void)copyClipToPasteboard:(Clip *)clip;
- (void)copyClipToPasteboardAtIndex:(NSUInteger)index;

//- (void)startUpdate;
//- (void)restartUpdate;
//- (void)haltUpdate;

@end
