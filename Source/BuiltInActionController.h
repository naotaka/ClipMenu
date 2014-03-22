//
//  BuiltInActionController.h
//  ClipMenu
//
//  Created by Naotaka Morimoto on 08/03/06.
//  Copyright 2008 Naotaka Morimoto. All rights reserved.
//

#import <Cocoa/Cocoa.h>


extern NSString *const CMBuiltInActionRemove;
extern NSString *const CMBuiltInActionPasteAsPlainText;
extern NSString *const CMBuiltInActionPasteAsFilePath;
extern NSString *const CMBuiltInActionPasteAsHFSFilePath;
//extern NSString *const CMBuiltInActionSpeak;


@class Clip;

@interface BuiltInActionController : NSObject
{	
	NSDictionary *actions;
	NSDictionary *toolTips;
	
	NSArray *availableTypes;
}
@property (nonatomic, retain) NSDictionary *actions;
@property (nonatomic, retain) NSDictionary *toolTips;
@property (nonatomic, retain) NSArray *availableTypes;

//- (void)remove:(Clip *)clip;
//- (void)pasteAsPlainText:(Clip *)clip;

@end
