// -*- Mode: objc -*-

#import <Cocoa/Cocoa.h>
#import "Sparkle/SUUpdater.h"
#import "StatusBar.h"
#import "UserClient_userspace.h"
#import "WorkSpaceData.h"
#include "bridge.h"

@interface KeyRemap4MacBook_serverAppDelegate : NSObject <NSApplicationDelegate> {
  NSWindow* window;

  // for IONotification
  IONotificationPortRef notifyport_;
  CFRunLoopSourceRef loopsource_;

  struct BridgeWorkSpaceData bridgeworkspacedata_;

  IBOutlet PreferencesManager* preferencesManager_;
  IBOutlet SUUpdater* suupdater_;
  IBOutlet StatusBar* statusbar_;
  IBOutlet StatusWindow* statusWindow_;
  IBOutlet UserClient_userspace* userClient_userspace;
  IBOutlet WorkSpaceData* workSpaceData_;
  IBOutlet XMLCompiler* xmlCompiler_;
}

@property (assign) IBOutlet NSWindow* window;
@property (assign) UserClient_userspace* userClient_userspace;

@end
