//
//  SnippetsController.m
//  ClipMenu
//
//  Created by naotaka on 08/10/30.
//  Copyright 2008 Naotaka Morimoto. All rights reserved.
//

#import "SnippetsController.h"
#import "constants.h"
#import "CMUtilities.h"


#pragma mark Static variables
static SnippetsController *sharedInstance = nil;


@interface SnippetsController ()
- (id)_init;
@end


@implementation SnippetsController

#pragma mark Initialize

+ (void)initialize
{
	if (sharedInstance == nil) {
		sharedInstance = [[self alloc] _init];
	}
}

+ (SnippetsController *)sharedInstance
{
	return [[sharedInstance retain] autorelease];
}

+ (NSArray *)sortDescriptors
{
	NSSortDescriptor *descriptor = [[[NSSortDescriptor alloc] initWithKey:kIndex ascending:YES] autorelease];
	return [NSArray arrayWithObject:descriptor];
}

- (id)_init
{
	self = [super init];
	return self;
}

- (id)init
{
	NSAssert(self != sharedInstance, @"Should never send init to the singleton instance");
	
	[self release];
	[sharedInstance retain];
	return sharedInstance;
}

- (void)dealloc
{
	[managedObjectContext release], managedObjectContext = nil;
	[persistentStoreCoordinator release], persistentStoreCoordinator = nil;
	[managedObjectModel release], managedObjectModel = nil;
	[super dealloc];
}

- (NSPersistentStoreCoordinator *)persistentStoreCoordinator
{
	if (persistentStoreCoordinator) {
		return persistentStoreCoordinator;
	}
	
	NSString *path = [CMUtilities applicationSupportFolder];
	NSFileManager *fileManager = [NSFileManager defaultManager];
	if (![fileManager fileExistsAtPath:path isDirectory:NULL]) {		
		[fileManager createDirectoryAtPath:path
			   withIntermediateDirectories:YES
								attributes:nil
									 error:NULL];
	}
	
	NSString *storePath = [path stringByAppendingPathComponent:kStoreName];
	NSURL *storeURL = [NSURL fileURLWithPath:storePath];
	NSError *error = nil;

	persistentStoreCoordinator = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:[self managedObjectModel]];
	if (![persistentStoreCoordinator addPersistentStoreWithType:NSXMLStoreType 
												  configuration:nil
															URL:storeURL
														options:nil
														  error:&error]) {
		[NSApp presentError:error];
	}
	
	return persistentStoreCoordinator;
}

- (NSManagedObjectModel *)managedObjectModel
{
	if (managedObjectModel) {
		return managedObjectModel;
	}
	
	managedObjectModel = [[NSManagedObjectModel mergedModelFromBundles:nil] retain];
	return managedObjectModel;
}

- (NSManagedObjectContext *)managedObjectContext
{
	if (managedObjectContext) {
		return managedObjectContext;
	}
	
	NSPersistentStoreCoordinator *coordinator = [self persistentStoreCoordinator];
	if (coordinator) {
		managedObjectContext = [[NSManagedObjectContext alloc] init];
		[managedObjectContext setPersistentStoreCoordinator:coordinator];
	}
	
	return managedObjectContext;
}

#pragma mark -

- (BOOL)saveStoreFile
{
//	NSLog(@"saveStoreFile");
	
	NSError *error = nil;
	BOOL reply = YES;
	
	if (managedObjectContext) {
		if ([managedObjectContext commitEditing]) {
			if ([managedObjectContext hasChanges] && ![managedObjectContext save:&error]) {
				BOOL errorResult = [NSApp presentError:error];
				if (errorResult == YES) {
					reply = NO;
				}
				else {
					NSInteger alertReturn = NSRunAlertPanel(nil, 
													  NSLocalizedString(@"Could not save changes while quitting. Quit anyway?", nil), 
													  NSLocalizedString(@"Quit anyway", nil), 
													  NSLocalizedString(@"Cancel", nil), 
													  nil);
					if (alertReturn == NSAlertAlternateReturn) {
						reply = NO;
					}
				}
			}
		}
		else {
			reply = NO;
		}
	}
	
	return reply;
}

- (BOOL)removeSnippet:(NSManagedObject *)snippet
{
	NSError *error = nil;
//		NSLog(@"its a snippet: %@", snippet);
	
	[managedObjectContext deleteObject:snippet];
	
	if ([managedObjectContext commitEditing]) {
		if ([managedObjectContext hasChanges] && ![managedObjectContext save:&error]) {
			[NSApp presentError:error];
			return NO;
		}
	}
	
//	// temp!!!
//	for (NSManagedObject *folder in [self folders]) {
//		NSLog(@"folder: %@", folder);
//	}
	
	return YES;
}

- (NSArray *)folders
{
	NSEntityDescription *entity = [NSEntityDescription entityForName:kFolderEntity
											  inManagedObjectContext:self.managedObjectContext];
	NSFetchRequest *request = [[[NSFetchRequest alloc] init] autorelease];
	[request setEntity:entity];
	
//	NSSortDescriptor *descriptor = [[NSSortDescriptor alloc] initWithKey:kIndex ascending:YES];
//	[request setSortDescriptors:[NSArray arrayWithObject:descriptor]];
//	[descriptor release], descriptor = nil;
	
	[request setSortDescriptors:[[self class] sortDescriptors]];
	
	NSError *error = nil;
	NSArray *fetchResluts = [self.managedObjectContext executeFetchRequest:request
																	 error:&error];
	if (fetchResluts && [fetchResluts count] > 0) {
		return fetchResluts;
	}
	
	return nil;
}

//- (NSArray *)snippets
//{
//	NSSet *registeredObjects = [[self managedObjectContext] registeredObjects];
//	if (registeredObjects && [registeredObjects count] > 0) {
//		return [registeredObjects  allObjects];
//	}
//	
//	return nil;
//}

//- (NSArray *)snippetsInFolder:(NSManagedObject *)aFolder
//{
//	NSEntityDescription *entity = [NSEntityDescription entityForName:kSnippetEntity
//											  inManagedObjectContext:[self managedObjectContext]];
//	NSFetchRequest *request = [[[NSFetchRequest alloc] init] autorelease];
//	[request setEntity:entity];
//	
//	NSPredicate *predicate = [NSPredicate predicateWithFormat:@"title == %@", @"Google"];
//	[request setPredicate:predicate];
//	
//	NSError *error = nil;
//	NSArray *fetchResluts = [[self managedObjectContext] executeFetchRequest:request
//																	   error:&error];
//	if (fetchResluts && [fetchResluts count] > 0) {
//		return fetchResluts;
//	}
//	
//	return nil;
//}

@end
