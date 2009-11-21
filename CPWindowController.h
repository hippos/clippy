//
//  CPWindowController.h
//  clippy
//
//  Created by hippos on 08/08/15.
//  Copyright 2008 hippos-lab.com. All rights reserved.
//

#import <Carbon/Carbon.h>
#import <Cocoa/Cocoa.h>

@class PTKeyCombo;
@class UKKQueue;

typedef struct
{
  int     d_windowNumber;
  NSMenu *clippyBaseMenu;
} _clippy_info;

@interface CPWindowController : NSWindowController
{
  NSString       *pathToDataText;
  NSDate         *lastModificationDate;
  NSString       *lastClipboardText;
  NSPasteboard   *pboard;
  NSMenu         *historyMenu;
  NSMutableArray *history;
  NSNumber       *max_history;
  /** BT-00076 */
  NSNumber       *menuMaxTag;
  _clippy_info   clippy_info;
  /** BT-00082 */
	NSMutableDictionary* aliasDictionary;
  NSTimer        *checkpboard_t;
  UKKQueue       *kqueue;
}

@property (nonatomic, retain) NSTimer *checkpboard_t;

- (void)     applicationDidFinishLaunching:(NSNotification *)aNotification;
- (void)     applicationWillTerminate:(NSNotification *)notification;
- (void)     createMenuItems:(NSArray *)items;
- (void)     addClippyMenuItems;
- (NSMenu *) createMenuItem:(NSString *)itemString subMenu:(NSMenu *)subMenu tag:(int)tag;
- (NSArray *)readLinesToArray:(NSURL *)fileURL;
- (void)     editTextHandler:(NSNotification *)notification;
- (IBAction) reloadText:(id)sender;
- (void)     rebuildHistory;
- (void)     createMailMessage:(NSString *)mailto;
- (void)     regHotKey:(PTKeyCombo *)keyCombo update:(BOOL)update;
- (void)     removeAllMenuItems:(NSMenu *)inMenu;

- (IBAction) copyMenuString:(id)sender;
- (IBAction) editTextData:(id)sender;
- (IBAction) setHotKey:(id)sender;
/** BT-00076 */
- (IBAction) clearHistory:(id)sender;
- (void)preferenceNotification:(NSNotification *)myNotification;
- (void)changeMaxHistory:(NSNumber*)maxHistory;
- (void)changeTextData:(NSNumber*)useClippyText textPath:(NSString*)textPath;

OSStatus cpHotKeyHandler(EventHandlerCallRef nextHandler, EventRef theEvent, void *userData);
@end
