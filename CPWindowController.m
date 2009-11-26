//
//  CPWindowController.m
//  clippy
//
//  Created by hippos on 08/08/15.
//  Copyright 2008 hippos-lab.com. All rights reserved.
//

#import "CPWindowController.h"
#import "UKKQueue/UKKQueue.h"
#import "SEGlue/SEGlue.h"
#import "PTHotKey/PTHotKey.h"
#import "PTHotKey/PTHotKeyCenter.h"
#import "PTHotKey/PTKeyComboPanel.h"
#import "MLGlue/MLGlue.h"
#import "RegexKitLite/RegexKitLite.h"

#define MENUITEM_BASE_TAG         10
#define MAX_HISTORY               10

EventHotKeyRef hot_key_ref;


@implementation CPWindowController

@synthesize checkpboard_t;

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
  /** BT-00076 */
  menuMaxTag = [NSNumber numberWithInt:0];
  
  /** BT-00082 **/
	aliasDictionary = [[NSMutableDictionary alloc] init];

  /* dummy window size (full screen) */
  NSRect visibleDisplay = [[[self window] screen] visibleFrame];
  NSRect myRect         = NSMakeRect(0, 0, visibleDisplay.size.width, visibleDisplay.size.height);
  [[self window] setFrame:myRect display:NO];
  clippy_info.d_windowNumber = [[self window] windowNumber];
  
  /* clippy base menu */
  clippy_info.clippyBaseMenu = [[NSMenu allocWithZone:[NSMenu menuZone]] initWithTitle:@""];
  [clippy_info.clippyBaseMenu setAutoenablesItems:NO];

  /* create a menu bar icon */
  NSStatusItem *statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
  NSImage      *sbImage    = [[NSImage alloc]
                              initByReferencingFile:[[NSBundle mainBundle] pathForResource:@"Pencil" ofType:@"png"]];
  [statusItem retain];
  [statusItem setTitle:@""];
  [statusItem setImage:sbImage];
  [statusItem setToolTip:@"clippy"];
  [statusItem setHighlightMode:(BOOL)YES];
  [statusItem setMenu:clippy_info.clippyBaseMenu];
  [sbImage release];

  /* data text */
  NSNumber* useClippyText = [[NSUserDefaults standardUserDefaults] objectForKey:@"useClippyText"];
  pathToDataText = [[NSUserDefaults standardUserDefaults] objectForKey:@"clippyTextPath"];  
  if (([useClippyText boolValue] == YES) || (pathToDataText == nil))
  {
    pathToDataText = [[NSBundle mainBundle] pathForResource:@"clippy" ofType:@"txt"];
  }
  [pathToDataText retain];
  NSArray *items = [self readLinesToArray:[NSURL fileURLWithPath:pathToDataText]];
  if (items != nil && [items count] > 0)
    {
      [self createMenuItems:items];
      [self addClippyMenuItems];
    }
  else
  { 
    [self addClippyMenuItems];
  }

  /* clip text data file last modification datetime */
  NSError      *error = nil;
  NSDictionary *attr = [[NSFileManager defaultManager] attributesOfItemAtPath:pathToDataText error:&error];
  NSDate       *tempDate = nil;
  if (error == nil)
  {
    tempDate = [attr objectForKey:NSFileModificationDate];
  }
  else
  {
    tempDate = [NSDate date];
  }
  lastModificationDate = [tempDate copyWithZone:nil];

  /* add observe path for Resource */
  NSNotificationCenter *swnc     = [[NSWorkspace sharedWorkspace] notificationCenter];
  kqueue = [UKKQueue sharedFileWatcher];
	[kqueue addPathToQueue:[pathToDataText stringByDeletingLastPathComponent] 
          notifyingAbout: UKKQueueNotifyAboutWrite]; 
  [swnc addObserver:self selector:@selector(editTextHandler:) name:UKFileWatcherWriteNotification object:nil];

  /* default hot key */
  id          keyComboPlist = [[NSUserDefaults standardUserDefaults] objectForKey: @"clippyKeyCombo"];
  PTKeyCombo *keyCombo      = nil;
  if (keyComboPlist == nil)
    {
      keyCombo = [[PTKeyCombo alloc] initWithKeyCode:8 modifiers:cmdKey + optionKey];
    }
  else
    {
      keyCombo = [[PTKeyCombo alloc] initWithPlistRepresentation: keyComboPlist];
    }
  [self regHotKey:keyCombo update:NO];
  [keyCombo release];

  /* default history count */
  NSNumber *mh = [[NSUserDefaults standardUserDefaults] objectForKey:@"clippyMaxHistory"];
  if ((mh != nil) && ([mh unsignedIntegerValue] > 0))
    {
      max_history = [NSNumber numberWithUnsignedInteger:[mh unsignedIntegerValue]];
    }
  else
    {
      max_history = [NSNumber numberWithUnsignedInteger:MAX_HISTORY];
    }

  /* pasteboard history */
  pboard  = [NSPasteboard generalPasteboard];
  history = [[NSMutableArray alloc] init];
  checkpboard_t = [NSTimer scheduledTimerWithTimeInterval:2.25 target:self selector:@selector(checkpboard:) userInfo:nil repeats:YES];

  NSString *observedObject = @"com.hippos-lab.clippy";
  NSDistributedNotificationCenter *center = [NSDistributedNotificationCenter defaultCenter];
  [center addObserver: self
             selector: @selector(preferenceNotification:)
                 name: @"clippyPref Notification"
               object: observedObject];
}

- (void)applicationWillTerminate:(NSNotification *)notification
{
  [pathToDataText release];
  [history release];
  [lastClipboardText release];
  [historyMenu release];
  /** BT-00076 */
  [menuMaxTag release];
  [clippy_info.clippyBaseMenu release];
  /** BT-00082 **/
  [aliasDictionary release];
  [checkpboard_t invalidate];
  self.checkpboard_t = nil;
}

- (NSArray *)readLinesToArray:(NSURL *)fileURL
{
  NSError  *err = nil;
  NSString *rdata = [NSString stringWithContentsOfFile:[fileURL path] encoding:NSUTF8StringEncoding error:&err];

  if ((!rdata) || (err != nil))
  {
    NSLog(@"[clippy]: can't read %@ %@",[fileURL path],[err localizedDescription]);
    return nil;
  }

  // read lines from data text
  NSArray *lines = [rdata componentsSeparatedByString:@"\n"];

  // check for
  NSMutableArray  *clippies     = [[[NSMutableArray alloc] init] autorelease];
  NSEnumerator    *enumerator   = [lines objectEnumerator];
  NSString        *tempString   = nil;
  NSMutableString *trimedString = nil;

  /** BT-00082 **/
  NSString *aliasRegex = @"^alias\\s*:\\s*(\\S+\\s*):\\s*((http|https|file):\\S+)";
  [aliasDictionary removeAllObjects];

  while ((tempString = [enumerator nextObject]) != nil)
  {
    NSMutableString *captureString = nil;
    if ([tempString length] == 0 || [tempString isMatchedByRegex:@"^$"])
    {
      continue;
    }
    trimedString = [NSMutableString stringWithString:tempString];
    [trimedString replaceOccurrencesOfRegex:@"^\\s+" withString:@""];
    NSArray *captures = [tempString captureComponentsMatchedByRegex:@"^\\s*([\\*#])"];
    if ([captures count] > 0)
    {
      captureString = [NSString stringWithString:[captures objectAtIndex:1]];
    }
    if (captureString != nil && ([captureString compare:@"#"] == NSOrderedSame))
    {
      continue;
    }
    if (captureString != nil && ([captureString compare:@"*"] == NSOrderedSame))
    {
      unsigned int i = 0;
      [trimedString replaceOccurrencesOfRegex:@"^\\*\\s+" withString:@""];
      for (i = 0; i <[trimedString length]; i++)
      {
        [clippies addObject:[NSString stringWithFormat:@"%C", [trimedString characterAtIndex:i]]];
      }
    }
    else
    {
      /** BT-00082 **/
      if ([trimedString isMatchedByRegex:aliasRegex])
      {
        NSError  *error      = nil;
        NSArray  *alcaptures = [trimedString captureComponentsMatchedByRegex:aliasRegex];
        NSString *contents   = [NSString stringWithContentsOfURL:
                                [NSURL URLWithString:[alcaptures objectAtIndex:2]]
                                encoding:NSUTF8StringEncoding error:&error];
        if (([alcaptures count] == 4) && (error == nil) && (contents != nil && [contents length] > 0))
        {
          [aliasDictionary setValue:contents forKey:[alcaptures objectAtIndex:1]];
          [clippies addObject:[alcaptures objectAtIndex:1]];
        }
        else
        {
          [clippies addObject:trimedString];
        }
      }
      else
      {
        [clippies addObject:trimedString];
      }
    }
  }
  return clippies;
}

- (void)createMenuItems:(NSArray *)items
{
  NSString       *itemString = nil;
  unsigned int    pos        = 0;
  int             tag        = 0;
  NSMutableArray *stack      = [[NSMutableArray alloc] init];
  NSMenu         *subMenu    = nil;


  for (pos = 0; pos < [items count]; pos++)
    {
      itemString = [items objectAtIndex:pos];
      if (([itemString length] == 1) && ([itemString characterAtIndex:0] == '<'))
        {
          if ([stack count] > 0)
            {
              [[stack lastObject] release];
              [stack removeLastObject];
            }
          continue;
        }

      // create a menuitem
      subMenu = [self createMenuItem:itemString subMenu:[stack lastObject] tag:tag]; tag++;

      if ((subMenu != nil) && (![stack containsObject:subMenu]))
        {
          [stack addObject:subMenu];
        }
    }

  [stack release];

  /** BT-00076 */
  [menuMaxTag release];
  menuMaxTag = [[NSNumber numberWithInt:tag - 1] copyWithZone:nil];
}

- (NSMenu *)createMenuItem:(NSString *)itemString subMenu:(NSMenu *)subMenu tag:(int)tag
{
  NSMenuItem   *menuItem = nil;
  unsigned char c        = [itemString characterAtIndex:0];

  if (c == '-')
    {
      subMenu != nil ? [subMenu addItem:[NSMenuItem separatorItem]] :[clippy_info.clippyBaseMenu addItem:[NSMenuItem separatorItem]];
      return subMenu;
    }

  if (c == '>')
    {
      menuItem =
        [[NSMenuItem allocWithZone:[NSMenu menuZone]] initWithTitle:[itemString substringFromIndex:1] action:nil keyEquivalent:@""];
    }
  else
    {
      menuItem = [[NSMenuItem allocWithZone:[NSMenu menuZone]] initWithTitle:itemString action:nil keyEquivalent:@""];
    }

  [menuItem setTag:MENUITEM_BASE_TAG + tag];
  [menuItem setTarget:self];
  [menuItem setEnabled:YES];
#ifdef _DEBUG_
  NSLog(@"%@:(%d)", [menuItem title], [menuItem tag]);
#endif

  if (c == '>')
    {
      NSMenu *newSubMenu = [[NSMenu allocWithZone:[NSMenu menuZone]] initWithTitle:[itemString substringFromIndex:1]];
      [menuItem setSubmenu:newSubMenu];
      subMenu ? [subMenu addItem:menuItem] : [clippy_info.clippyBaseMenu addItem:menuItem];
      return newSubMenu;
    }

  [menuItem setToolTip:[menuItem title]];
  [menuItem setAction:@selector(copyMenuString:)];
  subMenu ? [subMenu addItem:menuItem] : [clippy_info.clippyBaseMenu addItem:menuItem];
  return subMenu;
}

- (void)addClippyMenuItems
{
  int tags = MENUITEM_BASE_TAG - 1;
 
  [clippy_info.clippyBaseMenu addItem:[NSMenuItem separatorItem]];
  
  // history
  NSMenuItem *menuItem = [[NSMenuItem allocWithZone:[NSMenu menuZone]]
                          initWithTitle:NSLocalizedString(@"menuItem_History", "History") action:nil keyEquivalent:@""];
  [menuItem setTag:tags];
  [menuItem setTarget:self];
  /** BT-00077 */
  [menuItem setEnabled:NO];
  [clippy_info.clippyBaseMenu addItem:menuItem];
  [menuItem release];

  // Clear History
  menuItem = [[NSMenuItem allocWithZone:[NSMenu menuZone]]
              initWithTitle:NSLocalizedString(@"menuItem_ClearHistory", "ClearHistory") action:@selector(clearHistory:) keyEquivalent:@""];
  [menuItem setTag:--tags];
  [menuItem setTarget:self];
  [menuItem setEnabled:NO];
  [clippy_info.clippyBaseMenu addItem:menuItem];
  [menuItem release];
  [clippy_info.clippyBaseMenu addItem:[NSMenuItem separatorItem]];

  // Edit
  menuItem = [[NSMenuItem allocWithZone:[NSMenu menuZone]]
              initWithTitle:NSLocalizedString(@"menuItem_Edit", "Edit") action:@selector(editTextData:) keyEquivalent:@""];
  [menuItem setTag:--tags];
  [menuItem setTarget:self];
  [clippy_info.clippyBaseMenu addItem:menuItem];
  [menuItem release];

  // Quit Application
  [clippy_info.clippyBaseMenu addItem:[NSMenuItem separatorItem]];
  menuItem = [[NSMenuItem allocWithZone:[NSMenu menuZone]]
              initWithTitle:NSLocalizedString(@"menuItem_Quit", "Quit")  action:@selector(terminate:) keyEquivalent:@""];
  [menuItem setTarget:NSApp];
  [menuItem setTag:--tags];
  [clippy_info.clippyBaseMenu addItem:menuItem];
  [menuItem release];
  
  [self rebuildHistory];
}

- (void)editTextHandler:(NSNotification *)notification
{
  NSError      *error = nil;
  NSDictionary *attr  = [[NSFileManager defaultManager] attributesOfItemAtPath:pathToDataText error:&error];

  if (error == nil)
  {
    if ([lastModificationDate compare:[attr objectForKey:NSFileModificationDate]] == NSOrderedAscending)
    {
      [self reloadText:self];
      [lastModificationDate release];
      lastModificationDate = [[attr objectForKey:NSFileModificationDate] copyWithZone:nil];
    }
  }
}

- (IBAction)reloadText:(id)sender
{
  NSArray *items = [self readLinesToArray:[NSURL fileURLWithPath:pathToDataText]];
  if (items == nil || [items count] == 0)
    {
      return;
    }

  [self removeAllMenuItems:clippy_info.clippyBaseMenu];
  [clippy_info.clippyBaseMenu update];
  [self createMenuItems:items];
  [self addClippyMenuItems];

  /** BT-00076 **/
  [self rebuildHistory];

}

- (void)removeAllMenuItems:(NSMenu *)inMenu
{
  NSArray    *aItems = [inMenu itemArray];
  NSMenuItem *aMenuItem;
  int         i;

  for (i = ([aItems count] - 1); i >= 0; i--)
    {
      aMenuItem = [aItems objectAtIndex:i];
      if ((![aMenuItem isSeparatorItem]) && ([aMenuItem hasSubmenu]))
        {
          [self removeAllMenuItems:[aMenuItem submenu]];
        }
      [inMenu removeItem:aMenuItem];
    }
}

- (void)checkpboard:(NSTimer *)timer
{
  NSString *tempString = [pboard stringForType:NSStringPboardType];


  if ((tempString == nil) || ([history containsObject:tempString]))
    {
      return;
    }

  if ((lastClipboardText != nil) && ([tempString isEqualToString:lastClipboardText]))
    {
      return;
    }

  [lastClipboardText release];
  lastClipboardText = nil;

  if ([history count] >= [max_history unsignedIntegerValue])
    {
      [history removeLastObject];
    }

  [history insertObject:[NSString stringWithString:[pboard stringForType:NSStringPboardType]] atIndex:0];
  [self rebuildHistory];
}

- (void)rebuildHistory
{
  if ([history count] == 0) return;
  NSMenuItem   *menuItem   = nil;
  NSEnumerator *enumerator;
  if (historyMenu == nil)
    {
      historyMenu =
        [[NSMenu allocWithZone:[NSMenu menuZone]] initWithTitle:NSLocalizedString(@"menuItem_History", "History")];
    }
  else
    {
      menuItem   = nil;
      enumerator = [[historyMenu itemArray] objectEnumerator];
      while ((menuItem = [enumerator nextObject]) != nil)
        {
          [historyMenu removeItem:menuItem];
        }
    }

  enumerator = [history objectEnumerator];
  NSString *menuString;

  while ((menuString = [enumerator nextObject]))
    {
      menuItem = [[NSMenuItem alloc] initWithTitle:menuString action:@selector(copyMenuString:) keyEquivalent:@""];
      [menuItem setTarget:self];
      [menuItem setEnabled:YES];
      [menuItem setToolTip:[menuItem title]];
      [historyMenu addItem:menuItem];
      [menuItem release];
    }

  NSMenuItem *historyParent = [clippy_info.clippyBaseMenu itemWithTag:MENUITEM_BASE_TAG - 1];
  if (![historyParent hasSubmenu])
    {
      [historyParent setSubmenu:historyMenu];
    }
  /** BT-00077 **/
  [historyParent setEnabled:YES];
  [[clippy_info.clippyBaseMenu itemWithTag:MENUITEM_BASE_TAG - 2] setEnabled:YES];

  [clippy_info.clippyBaseMenu update];
}

- (void)regHotKey:(PTKeyCombo *)keyCombo update:(BOOL)update
{
  /* update hot key */
  if (update)
    {
      UnregisterEventHotKey(hot_key_ref);
    }
  /* install hot key */
  EventHotKeyID hot_key_id;
  hot_key_id.signature = 'clp1';
  hot_key_id.id        = 1;
  EventTypeSpec eventType[] =
  {
    { kEventClassKeyboard, kEventHotKeyPressed }
  };
  InstallApplicationEventHandler(&cpHotKeyHandler, 1, eventType, &clippy_info, NULL);
  RegisterEventHotKey([keyCombo keyCode], [keyCombo modifiers], hot_key_id, GetApplicationEventTarget(), 0, &hot_key_ref);
}

#pragma mark - IBAction

- (IBAction)copyMenuString:(id)sender
{
  NSPasteboard *generalPasteboard = [NSPasteboard generalPasteboard];
  NSMenuItem   *menuItem          = (NSMenuItem *)sender;
  NSString     *tempString        = nil;
  NSString     *URIRegex          = @"((http|https)\\://[a-zA-Z0-9\\-\\.]+\\.[a-zA-Z]{2,3}(:[a-zA-Z0-9]*)?/?([a-zA-Z0-9\\-\\._\\?\\,\\'/\\\\\\+&amp;%\\$#\\=~])*[^\\.\\,\\)\(\\s]$)";
  NSString     *MailRegex         = @"([0-9a-zA-Z][-.\\w]*[0-9a-zA-Z_]*@(([0-9a-zA-Z])+([-\\w]*[0-9a-zA-Z])*\\.)+[a-zA-Z]+)";

  if ([[menuItem title] isMatchedByRegex:@"(%\\d*[aAbBc-eFHIJmMpSwxXyYzZ])+"])
  {
    NSDateFormatter *dateFormatter =
      [[[NSDateFormatter alloc] initWithDateFormat:[menuItem title] allowNaturalLanguage:NO] autorelease];
    tempString = [dateFormatter stringFromDate:[NSDate date]];
  }
  else if ([[menuItem title] isMatchedByRegex:URIRegex])
  {
    tempString = [[menuItem title] stringByMatching:URIRegex capture:1L];
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:tempString]];
    tempString = [menuItem title];
  }
  else if ([[menuItem title] isMatchedByRegex:MailRegex])
  {
    if ([[menuItem title] isMatchedByRegex:@"^mailto\\s*:"])
    {
      tempString = [[menuItem title] stringByMatching:MailRegex capture:1L];
      [self createMailMessage:tempString];
      return;
    }
    tempString = [menuItem title];
  }
  else
  {
    NSString *alias_string = [aliasDictionary valueForKey:[menuItem title]];
    if (alias_string != nil && [alias_string length] > 0)
    {
      tempString = alias_string;
    }
    else
    {
      tempString = [menuItem title];
    }
  }

  [generalPasteboard declareTypes:[NSArray arrayWithObject:NSStringPboardType] owner:self];
  [generalPasteboard setString:tempString forType:NSStringPboardType];

  NSDictionary       *activeApp    = [[NSWorkspace sharedWorkspace] activeApplication];
  SEApplication      *systemEvents = [SEApplication applicationWithName:@"System Events"];
  SEReference        *ref          = [[systemEvents processes] byName:[activeApp valueForKey:@"NSApplicationName"]];
  SEKeystrokeCommand *cmd          = [[ref keystroke: @"v"] using: [SEConstant commandDown]];
  [cmd send];
}

- (IBAction)editTextData:(id)sender
{
  [[NSWorkspace sharedWorkspace] openFile:pathToDataText withApplication:@"TextEdit"];
}

- (IBAction)clearHistory:(id)sender
{
  [history removeAllObjects];
  NSMenuItem   *menuItem   = nil;
  NSEnumerator *enumerator = [[historyMenu itemArray] objectEnumerator];
  while ((menuItem = [enumerator nextObject]) != nil)
    {
      [historyMenu removeItem:menuItem];
    }

  if (lastClipboardText != nil)
    {
      [lastClipboardText release];
      lastClipboardText = nil;
    }

  lastClipboardText = [[NSString alloc] initWithString:[pboard stringForType:NSStringPboardType]];

  /** BT-00077 **/
  [[clippy_info.clippyBaseMenu itemWithTag:MENUITEM_BASE_TAG - 1] setEnabled:NO];
  [[clippy_info.clippyBaseMenu itemWithTag:MENUITEM_BASE_TAG - 2] setEnabled:NO];
  
}

#pragma mark - Carbon

OSStatus cpHotKeyHandler(EventHandlerCallRef nextHandler, EventRef theEvent, void *userData)
{
  _clippy_info* ci = (_clippy_info*)userData;
  EventHotKeyID hkCom;

  GetEventParameter(theEvent, kEventParamDirectObject, typeEventHotKeyID, NULL, sizeof(hkCom), NULL, &hkCom);
  if (hkCom.id == 1)
    {
      NSEvent *e =
        [NSEvent mouseEventWithType:NSLeftMouseDown location:[NSEvent mouseLocation] modifierFlags:NSControlKeyMask timestamp:GetCurrentEventTime() windowNumber:ci->d_windowNumber /* *((int *)userData)*/ context:[NSGraphicsContext currentContext] eventNumber:1 clickCount:1 pressure:0.0];
      [NSMenu popUpContextMenu:ci->clippyBaseMenu withEvent:e forView:nil];
    }
  return noErr;
}

#pragma mark - MailMessage

- (void)createMailMessage:(NSString *)mailto
{/*
  MailApplication     *mail    = [SBApplication applicationWithBundleIdentifier:@"com.apple.Mail"];

  MailOutgoingMessage *message =
    [[[mail classForScriptingClass:@"outgoing message"] alloc]
     initWithProperties:[NSDictionary dictionaryWithObjectsAndKeys:@"", @"subject", @"", @"content", @"", @"sender", nil]];

  [[mail outgoingMessages] addObject: message];
  message.visible = YES;

  MailToRecipient *recipi =
    [[[mail classForScriptingClass:@"to recipient"] alloc] initWithProperties:[NSDictionary dictionaryWithObjectsAndKeys:mailto, @"address", nil]];
  [message.toRecipients addObject: recipi];

  [mail activate];
 */
  
  MLApplication *mail    = [[MLApplication alloc] initWithBundleID: @"com.apple.mail"];
  MLMakeCommand *makeCmd = [[[mail make] new_: [MLConstant outgoingMessage]] withProperties:
                            [NSDictionary dictionaryWithObjectsAndKeys :@"",[MLConstant subject],@"",[MLConstant content],[NSNumber numberWithInt:1],[MLConstant visible],nil]];
  NSError     *error = nil;
  MLReference *msg   = [makeCmd sendWithError: &error];
  
  makeCmd = [[[[mail make] new_: [MLConstant toRecipient]]
              at: [[msg toRecipients] end]]
             withProperties: [NSDictionary dictionaryWithObject: mailto
                                                         forKey: [MLConstant address]]];
  [makeCmd sendWithError: &error];
  [[msg activate] send];
  [mail release];
  
}

- (void)preferenceNotification:(NSNotification *)myNotification
{
  NSDictionary* properties = [myNotification userInfo];
  if ([[properties allKeys] containsObject:@"clippyMaxHistory"] == YES)
  {
    [self changeMaxHistory:[properties objectForKey:@"clippyMaxHistory"]];
  }
  if (([[properties allKeys] containsObject:@"useClippyText"] == YES) ||
      ([[properties allKeys] containsObject:@"clippyTextPath"] == YES))
  {
    [self changeTextData:[properties objectForKey:@"useClippyText" ]
                textPath:[properties objectForKey:@"clippyTextPath"]];
  }
  if ([[properties allKeys] containsObject:@"clippyKeyCombo"] == YES)
  {
    [self changeKeyCombo:[properties objectForKey:@"clippyKeyCombo"]];
  }
}

- (void)changeMaxHistory:(NSNumber *)maxHistory
{
  if ([maxHistory unsignedIntegerValue] == 0)
  {
    [self clearHistory:self];
    if ([checkpboard_t isValid])
    {
      [checkpboard_t invalidate];
      self.checkpboard_t = nil;
    }
  }
  else
  {
    if ([max_history unsignedIntegerValue] > [maxHistory unsignedIntegerValue])
    {
      unsigned int remove_count = [max_history unsignedIntegerValue] - [maxHistory unsignedIntegerValue];
      while (remove_count > 0)
      {
        if ([history count] == 0)
        {
          break;
        }
        [history removeLastObject];
      }
      [self rebuildHistory];
    }
    if (![checkpboard_t isValid])
    {
      checkpboard_t = [NSTimer scheduledTimerWithTimeInterval:2.25 target:self selector:@selector(checkpboard:) userInfo:nil repeats:YES];
    }
  }
  max_history = maxHistory;
}

- (void)changeTextData:(NSNumber*)useClippyText textPath:(NSString*)textPath
{
  NSString* tempPath = [NSString stringWithString:pathToDataText];
  
  [pathToDataText release];
  if (textPath != nil)
  {
    pathToDataText = [NSString stringWithString:textPath]; 
  }
  if (([useClippyText boolValue] == YES) || (pathToDataText == nil))
  {
    pathToDataText = [[NSBundle mainBundle] pathForResource:@"clippy" ofType:@"txt"];
  }
  [pathToDataText retain];
  
  NSError      *error = nil;
  NSDictionary *attr = [[NSFileManager defaultManager] attributesOfItemAtPath:pathToDataText error:&error];
  NSDate       *tempDate = nil;
  if (error == nil)
  {
    tempDate = [attr objectForKey:NSFileModificationDate];
  }
  else
  {
    tempDate = [NSDate date];
  }

  lastModificationDate = [tempDate copyWithZone:nil];
  
  [kqueue removePathFromQueue:[tempPath stringByDeletingLastPathComponent]];
  [kqueue addPathToQueue:[pathToDataText stringByDeletingLastPathComponent]];
  [self reloadText:self];
}

- (void)changeKeyCombo:(id)keyComboDict
{
  if (keyComboDict == nil)
  {
    return;
  }
  PTKeyCombo *keyCombo = [[PTKeyCombo alloc] initWithPlistRepresentation: keyComboDict];
  [self regHotKey:keyCombo update:YES];
  [keyCombo release];
}
@end
