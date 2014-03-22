/*
 *  constants.h
 *  ClipMenu
 *
 *  Created by naotaka on 08/10/18.
 *  Copyright 2008 Naotaka Morimoto. All rights reserved.
 *
 */

// Appication
#define kApplicationName @"ClipMenu"

/* Hot Keys */
//#define kHotKeyForClipMenu @"HotKeyForClipMenu"

//typedef enum {
//	CMHotKeyForClipMenu = 0,
//	CMHotKeyForHistory,
//	CMHotKeyForSnippets
//} CMHotKey;

#define kClipMenuIdentifier @"ClipMenu"
#define kHistoryMenuIdentifier @"HistoryMenu"
#define kSnippetsMenuIdentifier @"SnippetsMenu"
#define kActionMenuIdentifier @"ActionMenu"

#define kSelector @"selector"
#define kBehavior @"behavior"

#define kEmptyString @""
#define kSingleSpace @" "
#define kNewLine @"\n"
#define kCarriageReturnAndNewLine @"\r\n"
#define kCarriageReturn @"\r"
#define kTab @"\t"

#define kPopUpActionMenu @"popUpActionMenu"

#define kOldKey @"old"
#define kNewKey @"new"

/* Paths */
#define kScriptDirectory @"script"
#define kLibraryScriptDirectory @"lib"
#define kActionDirectory @"action"

/* Filenames */
#define kClipsSaveDataName @"clips.data"
#define kActionSaveDataName @"actionMenu.data"
#define kJavaScriptExtension @"js"

#define kStoreName @"Snippets.xml"

/* Preferences window */
#define kIconSizeInTableView 16
#define kImageAndTextCellColumn @"ImageAndTextCellColumn"
#define kDraggedDataType @"DraggedDataType"

/* Exclude Apps */
#define kCMBundleIdentifierKey @"bundleIdentifier"
#define kCMNameKey @"name"

/* Model */
#define kFolderEntity @"Folder"
#define kSnippetEntity @"Snippet"

#define kEnabled @"enabled"
#define kIndex @"index"
#define kTitle @"title"
#define kFolder @"folder"
#define kSnippets @"snippets"
#define kContent @"content"
#define kDefaultSnippetName @"untitled snippet"

/* Folder Node */
#define GROUP_NAME @"GROUPS"

/* XML */
#define kXMLFileType @"xml"

#define kType @"type"

#define kRootElement @"folders"
#define kFolderElement @"folder"
#define kSnippetElement @"snippet"
#define kTitleElement @"title"
#define kSnippetsElement @"snippets"
#define kContentElement @"content"
