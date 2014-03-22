//
//  IndexedArrayController.m
//  ClipMenu
//
//  Created by naotaka on 08/10/30.
//  Copyright 2008 Naotaka Morimoto. All rights reserved.
//

#import "IndexedArrayController.h"
#import "constants.h"


@implementation IndexedArrayController

- (void)awakeFromNib
{
	[super awakeFromNib];
	
	NSSortDescriptor *descriptor = [[NSSortDescriptor alloc] initWithKey:kIndex ascending:YES];
	[super setSortDescriptors:[NSArray arrayWithObject:descriptor]];
	[descriptor release], descriptor = nil;
	
	[self setAutomaticallyPreparesContent:YES];
}

- (void)addObject:(id)object
{
	NSUInteger lastIndex = [[self arrangedObjects] count];
	[object setValue:[NSNumber numberWithUnsignedInteger:lastIndex] forKey:kIndex];
//	NSLog(@"addObject: %@", object);
	
	[super addObject:object];
}

- (void)addObjects:(NSArray *)objects
{
	for (id object in objects) {
		[self addObject:object];
	}
}

- (void)insertObject:(id)object atArrangedObjectIndex:(NSUInteger)index
{
//	NSLog(@"insertObject: %@, index: %d", object, index);
	
	[(NSManagedObject *)object setValue:[NSNumber numberWithUnsignedInteger:index] forKey:kIndex];
	
	[super insertObject:object atArrangedObjectIndex:index];
	[self renumber];
}

- (void)insertObjects:(NSArray *)objects atArrangedObjectIndexes:(NSIndexSet *)indexes
{
//	NSLog(@"insertObjects: %@", indexes);

	[super insertObjects:objects atArrangedObjectIndexes:indexes];
	[self renumber];
}

//- (void)removeObject:(id)object
//{
////	NSLog(@"removeObject");
//	
//	[super removeObject:object];
//	[self renumber];
//}

- (void)removeObjectAtArrangedObjectIndex:(NSUInteger)index
{
//	NSLog(@"removeObjectAtArrangedObjectIndex: %d", index);
	
	[super removeObjectAtArrangedObjectIndex:index];
	[self renumber];
}

- (void)removeObjectsAtArrangedObjectIndexes:(NSIndexSet *)indexes
{
//	NSLog(@"removeObjectsAtArrangedObjectIndexes: %@", indexes);
	
	[super removeObjectsAtArrangedObjectIndexes:indexes];
	[self renumber];
}

#pragma mark -

- (void)renumber
{
//	NSLog(@"renumber");
	
	NSUInteger i = 0;
	for (NSManagedObject *managedObject in [self arrangedObjects]) {
//		NSLog(@"managedObject: %@", managedObject);
		
		[managedObject setValue:[NSNumber numberWithUnsignedInteger:i] forKey:kIndex];
		i++;
		
//		NSLog(@"managedObject: %@", managedObject);
	}
}

@end
