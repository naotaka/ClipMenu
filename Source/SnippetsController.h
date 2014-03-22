//
//  SnippetsController.h
//  ClipMenu
//
//  Created by naotaka on 08/10/30.
//  Copyright 2008 Naotaka Morimoto. All rights reserved.
//

#import <Cocoa/Cocoa.h>


@interface SnippetsController : NSObject
{
	NSPersistentStoreCoordinator *persistentStoreCoordinator;
	NSManagedObjectModel *managedObjectModel;
	NSManagedObjectContext *managedObjectContext;
}

+ (SnippetsController *)sharedInstance;

+ (NSArray *)sortDescriptors;

- (NSPersistentStoreCoordinator *)persistentStoreCoordinator;
- (NSManagedObjectModel *)managedObjectModel;
- (NSManagedObjectContext *)managedObjectContext;


- (BOOL)saveStoreFile;
- (BOOL)removeSnippet:(NSManagedObject *)snippet;
- (NSArray *)folders;
//- (NSArray *)snippets;
//- (NSArray *)snippetsInFolder:(NSManagedObject *)aFolder;

@end
