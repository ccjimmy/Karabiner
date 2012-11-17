#import <Carbon/Carbon.h>
#import "KeyRemap4MacBook_serverAppDelegate.h"
#import "KeyRemap4MacBookKeys.h"
#import "KeyRemap4MacBookNSDistributedNotificationCenter.h"
#import "StatusWindow.h"
#include <stdlib.h>

@implementation KeyRemap4MacBook_serverAppDelegate

@synthesize window;
@synthesize userClient_userspace;

// ----------------------------------------
- (void) statusBarItemSelected:(id)sender {
  [statusbar_ statusBarItemSelected:sender];
}

// ------------------------------------------------------------
- (void) send_workspacedata_to_kext {
  struct BridgeUserClientStruct bridgestruct;
  bridgestruct.type   = BRIDGE_USERCLIENT_TYPE_SET_WORKSPACEDATA;
  bridgestruct.option = 0;
  bridgestruct.data   = (uintptr_t)(&bridgeworkspacedata_);
  bridgestruct.size   = sizeof(bridgeworkspacedata_);

  [userClient_userspace synchronized_communication:&bridgestruct];
}

- (void) observer_NSWorkspaceDidActivateApplicationNotification:(NSNotification*)notification
{
  NSString* name = [WorkSpaceData getActiveApplicationName];
  if (name) {
    // We ignore our investigation application.
    if (! [name isEqualToString:@"org.pqrs.KeyRemap4MacBook.EventViewer"]) {
      bridgeworkspacedata_.applicationtype = [workSpaceData_ getApplicationType:name];
      [self send_workspacedata_to_kext];

      NSDictionary* userInfo = [NSDictionary dictionaryWithObject:name forKey:@"name"];

      [org_pqrs_KeyRemap4MacBook_NSDistributedNotificationCenter postNotificationName:kKeyRemap4MacBookApplicationChangedNotification userInfo:userInfo];
    }
  }
}

- (void) distributedObserver_kTISNotifyEnabledKeyboardInputSourcesChanged:(NSNotification*)notification
{
  // [NSAutoreleasePool drain] is never called from NSDistributedNotificationCenter.
  // Therefore, we need to make own NSAutoreleasePool.
  NSAutoreleasePool* pool = [NSAutoreleasePool new];
  {
    [WorkSpaceData refreshEnabledInputSources];
  }
  [pool drain];
}

- (void) distributedObserver_kTISNotifySelectedKeyboardInputSourceChanged:(NSNotification*)notification
{
  // [NSAutoreleasePool drain] is never called from NSDistributedNotificationCenter.
  // Therefore, we need to make own NSAutoreleasePool.
  NSAutoreleasePool* pool = [NSAutoreleasePool new];
  {
    InputSource* inputSource = [WorkSpaceData getCurrentInputSource];
    [workSpaceData_ getInputSourceID:inputSource
                  output_inputSource:(&(bridgeworkspacedata_.inputsource))
            output_inputSourceDetail:(&(bridgeworkspacedata_.inputsourcedetail))];
    [self send_workspacedata_to_kext];

    NSMutableDictionary* userInfo = [[NSMutableDictionary new] autorelease];
    if ([inputSource languagecode]) {
      [userInfo setObject:[inputSource languagecode] forKey:@"languageCode"];
    }
    if ([inputSource inputSourceID]) {
      [userInfo setObject:[inputSource inputSourceID] forKey:@"inputSourceID"];
    }
    if ([inputSource inputModeID]) {
      [userInfo setObject:[inputSource inputModeID] forKey:@"inputModeID"];
    }
    [org_pqrs_KeyRemap4MacBook_NSDistributedNotificationCenter postNotificationName:kKeyRemap4MacBookInputSourceChangedNotification userInfo:userInfo];
  }
  [pool drain];
}

// ------------------------------------------------------------
- (void) send_remapclasses_initialize_vector_to_kext {
  const uint32_t* p = [xmlCompiler_ remapclasses_initialize_vector_data];
  size_t size = [xmlCompiler_ remapclasses_initialize_vector_size] * sizeof(uint32_t);

  // --------------------
  struct BridgeUserClientStruct bridgestruct;
  bridgestruct.type   = BRIDGE_USERCLIENT_TYPE_SET_REMAPCLASSES_INITIALIZE_VECTOR;
  bridgestruct.option = 0;
  bridgestruct.data   = (uintptr_t)(p);
  bridgestruct.size   = size;

  [userClient_userspace synchronized_communication:&bridgestruct];
}

- (void) send_config_to_kext {
  NSArray* essential_config = [preferencesManager_ essential_config];
  if (! essential_config) {
    NSLog(@"[WARNING] essential_config == nil.");
    return;
  }

  // ------------------------------------------------------------
  NSUInteger essential_config_count = [essential_config count];
  NSUInteger remapclasses_count     = [xmlCompiler_ remapclasses_initialize_vector_config_count];
  size_t size = (essential_config_count + remapclasses_count) * sizeof(int32_t);
  int32_t* data = (int32_t*)(malloc(size));
  if (! data) {
    NSLog(@"[WARNING] malloc failed.");
    return;

  } else {
    int32_t* p = data;

    // --------------------
    // essential_config
    for (NSNumber* number in essential_config) {
      *p++ = [number intValue];
    }

    // --------------------
    // remapclasses config
    for (NSUInteger i = 0; i < remapclasses_count; ++i) {
      NSString* name = [xmlCompiler_ identifier:(int)(i)];
      if (! name) {
        NSLog(@"[WARNING] %s name == nil. private.xml has error?", __FUNCTION__);
        *p++ = 0;
      } else {
        *p++ = [preferencesManager_ value:name];
      }
    }

    // --------------------
    struct BridgeUserClientStruct bridgestruct;
    bridgestruct.type   = BRIDGE_USERCLIENT_TYPE_SET_CONFIG;
    bridgestruct.option = 0;
    bridgestruct.data   = (uintptr_t)(data);
    bridgestruct.size   = size;

    [userClient_userspace synchronized_communication:&bridgestruct];

    free(data);
  }
}

// ------------------------------------------------------------
static void observer_IONotification(void* refcon, io_iterator_t iterator) {
  NSLog(@"observer_IONotification");

  KeyRemap4MacBook_serverAppDelegate* self = refcon;
  if (! self) {
    NSLog(@"[ERROR] observer_IONotification refcon == nil\n");
    return;
  }

  for (;;) {
    io_object_t obj = IOIteratorNext(iterator);
    if (! obj) break;

    IOObjectRelease(obj);
  }
  // Do not release iterator.

  // = Documentation of IOKit =
  // - Introduction to Accessing Hardware From Applications
  //   - Finding and Accessing Devices
  //
  // In the case of IOServiceAddMatchingNotification, make sure you release the iterator only if you’re also ready to stop receiving notifications:
  // When you release the iterator you receive from IOServiceAddMatchingNotification, you also disable the notification.

  // ------------------------------------------------------------
  // [UserClient_userspace refresh_connection] may fail by kIOReturnExclusiveAccess
  // when NSWorkspaceSessionDidBecomeActiveNotification.
  // So, we retry the connection some times.
  for (int retrycount = 0; retrycount < 10; ++retrycount) {
    [[self userClient_userspace] refresh_connection];
    if ([[self userClient_userspace] connected]) break;

    [NSThread sleepForTimeInterval:0.5];
  }

  [self send_remapclasses_initialize_vector_to_kext];
  [self send_config_to_kext];
  [self send_workspacedata_to_kext];
}

- (void) unregisterIONotification {
  if (notifyport_) {
    if (loopsource_) {
      CFRunLoopSourceInvalidate(loopsource_);
      loopsource_ = nil;
    }
    IONotificationPortDestroy(notifyport_);
    notifyport_ = nil;
  }
}

- (void) registerIONotification {
  [self unregisterIONotification];

  notifyport_ = IONotificationPortCreate(kIOMasterPortDefault);
  if (! notifyport_) {
    NSLog(@"[ERROR] IONotificationPortCreate failed\n");
    return;
  }

  // ----------------------------------------------------------------------
  io_iterator_t it;
  kern_return_t kernResult;

  kernResult = IOServiceAddMatchingNotification(notifyport_,
                                                kIOMatchedNotification,
                                                IOServiceNameMatching("org_pqrs_driver_KeyRemap4MacBook"),
                                                &observer_IONotification,
                                                self,
                                                &it);
  if (kernResult != kIOReturnSuccess) {
    NSLog(@"[ERROR] IOServiceAddMatchingNotification failed");
    return;
  }
  observer_IONotification(self, it);

  // ----------------------------------------------------------------------
  loopsource_ = IONotificationPortGetRunLoopSource(notifyport_);
  if (! loopsource_) {
    NSLog(@"[ERROR] IONotificationPortGetRunLoopSource failed");
    return;
  }
  CFRunLoopAddSource(CFRunLoopGetCurrent(), loopsource_, kCFRunLoopDefaultMode);
}

// ------------------------------------------------------------
- (void) distributedObserver_ConfigXMLReloaded:(NSNotification*)notification {
  // [NSAutoreleasePool drain] is never called from NSDistributedNotificationCenter.
  // Therefore, we need to make own NSAutoreleasePool.
  NSAutoreleasePool* pool = [NSAutoreleasePool new];
  {
    [self send_remapclasses_initialize_vector_to_kext];
    [self send_config_to_kext];
  }
  [pool drain];
}

- (void) observer_ConfigListChanged:(NSNotification*)notification {
  [statusbar_ refresh];
}

- (void) distributedObserver_PreferencesChanged:(NSNotification*)notification {
  // [NSAutoreleasePool drain] is never called from NSDistributedNotificationCenter.
  // Therefore, we need to make own NSAutoreleasePool.
  NSAutoreleasePool* pool = [NSAutoreleasePool new];
  {
    [self send_config_to_kext];
  }
  [pool drain];
}

// ------------------------------------------------------------
- (void) observer_NSWorkspaceSessionDidBecomeActiveNotification:(NSNotification*)notification
{
  NSLog(@"observer_NSWorkspaceSessionDidBecomeActiveNotification");

  [statusWindow_ resetStatusMessage];

  [self registerIONotification];
}

- (void) observer_NSWorkspaceSessionDidResignActiveNotification:(NSNotification*)notification
{
  NSLog(@"observer_NSWorkspaceSessionDidResignActiveNotification");

  [statusWindow_ resetStatusMessage];

  [self unregisterIONotification];
  [userClient_userspace disconnect_from_kext];
}

// ------------------------------------------------------------
- (void) applicationDidFinishLaunching:(NSNotification*)aNotification {
  [statusWindow_ resetStatusMessage];

  [statusbar_ refresh];

  [self registerIONotification];

  // ------------------------------------------------------------
  [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver:self
                                                         selector:@selector(observer_NSWorkspaceDidActivateApplicationNotification:)
                                                             name:NSWorkspaceDidActivateApplicationNotification
                                                           object:nil];

  [org_pqrs_KeyRemap4MacBook_NSDistributedNotificationCenter addObserver:self
                                                                selector:@selector(distributedObserver_kTISNotifyEnabledKeyboardInputSourcesChanged:)
                                                                    name:(NSString*)(kTISNotifyEnabledKeyboardInputSourcesChanged)
                                                                  object:nil];

  [org_pqrs_KeyRemap4MacBook_NSDistributedNotificationCenter addObserver:self
                                                                selector:@selector(distributedObserver_kTISNotifySelectedKeyboardInputSourceChanged:)
                                                                    name:(NSString*)(kTISNotifySelectedKeyboardInputSourceChanged)
                                                                  object:nil];

  // ------------------------------
  [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver:self
                                                         selector:@selector(observer_NSWorkspaceSessionDidBecomeActiveNotification:)
                                                             name:NSWorkspaceSessionDidBecomeActiveNotification
                                                           object:nil];

  [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver:self
                                                         selector:@selector(observer_NSWorkspaceSessionDidResignActiveNotification:)
                                                             name:NSWorkspaceSessionDidResignActiveNotification
                                                           object:nil];

  // ------------------------------
  [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(observer_ConfigListChanged:) name:@"ConfigListChanged" object:nil];

  [org_pqrs_KeyRemap4MacBook_NSDistributedNotificationCenter addObserver:self
                                                                selector:@selector(distributedObserver_ConfigXMLReloaded:)
                                                                    name:kKeyRemap4MacBookConfigXMLReloadedNotification];

  [org_pqrs_KeyRemap4MacBook_NSDistributedNotificationCenter addObserver:self
                                                                selector:@selector(distributedObserver_PreferencesChanged:)
                                                                    name:kKeyRemap4MacBookPreferencesChangedNotification];

  // ------------------------------------------------------------
  [self observer_NSWorkspaceDidActivateApplicationNotification:nil];
  [self distributedObserver_kTISNotifyEnabledKeyboardInputSourcesChanged:nil];
  [self distributedObserver_kTISNotifySelectedKeyboardInputSourceChanged:nil];
  [updater_ checkForUpdatesInBackground:nil];

  // ------------------------------------------------------------
  [org_pqrs_KeyRemap4MacBook_NSDistributedNotificationCenter postNotificationName:kKeyRemap4MacBookServerLaunchedNotification userInfo:nil];
}

- (void) dealloc
{
  [org_pqrs_KeyRemap4MacBook_NSDistributedNotificationCenter removeObserver:self];
  [[NSNotificationCenter defaultCenter] removeObserver:self];

  [super dealloc];
}

@end
