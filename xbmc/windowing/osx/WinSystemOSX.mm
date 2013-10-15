/*
 *      Copyright (C) 2005-2013 Team XBMC
 *      http://xbmc.org
 *
 *  This Program is free software; you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation; either version 2, or (at your option)
 *  any later version.
 *
 *  This Program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with XBMC; see the file COPYING.  If not, see
 *  <http://www.gnu.org/licenses/>.
 *
 */

#if defined(TARGET_DARWIN_OSX)

//hack around problem with xbmc's typedef int BOOL
// and obj-c's typedef unsigned char BOOL
#define BOOL XBMC_BOOL
#include "WinSystemOSX.h"
#include "WinEventsOSX.h"
#include "Application.h"
#include "guilib/DispResource.h"
#include "guilib/GUIWindowManager.h"
#include "settings/DisplaySettings.h"
#include "settings/Settings.h"
#include "settings/DisplaySettings.h"
#include "input/KeyboardStat.h"
#include "threads/SingleLock.h"
#include "utils/log.h"
#include "osx/XBMCHelper.h"
#include "osx/CocoaInterface.h"
#include "osx/DarwinUtils.h"
#include "utils/SystemInfo.h"
#include "windowing/WindowingFactory.h"
#undef BOOL

#import "osx/OSXTextInputResponder.h"

#import <Cocoa/Cocoa.h>
#import <QuartzCore/QuartzCore.h>
#import <IOKit/pwr_mgt/IOPMLib.h>
#import <IOKit/graphics/IOGraphicsLib.h>
#import <Foundation/Foundation.h>

// turn off deprecated warning spew.
#pragma GCC diagnostic ignored "-Wdeprecated-declarations"

@class WindowListener;

typedef struct WindowData {
  bool             created;
  NSWindow        *nswindow;
  WindowListener  *listener;
  NSOpenGLContext *glcontext;
} WindowData;


@interface WindowListener : NSResponder <NSWindowDelegate>
{
  WindowData *m_windowData;
  BOOL observingVisible;
  BOOL wasVisible;
}

-(void) listen:(WindowData *) windowData;
-(void) pauseVisibleObservation;
-(void) resumeVisibleObservation;
-(void) close;

-(BOOL) windowShouldClose:(id) sender;
-(void) windowDidExpose:(NSNotification *) aNotification;
-(void) windowDidMove:(NSNotification *) aNotification;
-(void) windowDidResize:(NSNotification *) aNotification;
-(void) windowDidMiniaturize:(NSNotification *) aNotification;
-(void) windowDidDeminiaturize:(NSNotification *) aNotification;
-(void) windowDidBecomeKey:(NSNotification *) aNotification;
-(void) windowDidResignKey:(NSNotification *) aNotification;

/* Window event handling */
/*
-(void) mouseDown:(NSEvent *) theEvent;
-(void) rightMouseDown:(NSEvent *) theEvent;
-(void) otherMouseDown:(NSEvent *) theEvent;
-(void) mouseUp:(NSEvent *) theEvent;
-(void) rightMouseUp:(NSEvent *) theEvent;
-(void) otherMouseUp:(NSEvent *) theEvent;

-(void) mouseMoved:(NSEvent *) theEvent;

-(void) mouseDragged:(NSEvent *) theEvent;
-(void) rightMouseDragged:(NSEvent *) theEvent;
-(void) otherMouseDragged:(NSEvent *) theEvent;
-(void) scrollWheel:(NSEvent *) theEvent;
-(void) touchesBeganWithEvent:(NSEvent *) theEvent;
-(void) touchesMovedWithEvent:(NSEvent *) theEvent;
-(void) touchesEndedWithEvent:(NSEvent *) theEvent;
-(void) touchesCancelledWithEvent:(NSEvent *) theEvent;
*/

@end

@implementation WindowListener

- (void)listen:(WindowData *)windowData
{
  NSLog(@"listen");
  NSNotificationCenter *center;
  NSWindow *window = windowData->nswindow;
  NSView *view = [window contentView];
  
  m_windowData = windowData;
  observingVisible = YES;
  wasVisible = [window isVisible];
  
  center = [NSNotificationCenter defaultCenter];
  
  if ([window delegate] != nil)
  {
    NSLog(@"listen no delegate");

    [center addObserver:self selector:@selector(windowDidExpose:) name:NSWindowDidExposeNotification object:window];
    [center addObserver:self selector:@selector(windowDidMove:) name:NSWindowDidMoveNotification object:window];
    [center addObserver:self selector:@selector(windowDidResize:) name:NSWindowDidResizeNotification object:window];
    [center addObserver:self selector:@selector(windowDidMiniaturize:) name:NSWindowDidMiniaturizeNotification object:window];
    [center addObserver:self selector:@selector(windowDidDeminiaturize:) name:NSWindowDidDeminiaturizeNotification object:window];
    [center addObserver:self selector:@selector(windowDidBecomeKey:) name:NSWindowDidBecomeKeyNotification object:window];
    [center addObserver:self selector:@selector(windowDidResignKey:) name:NSWindowDidResignKeyNotification object:window];
  }
  else
  {
    NSLog(@"listen delegate");
    [window setDelegate:self];
  }
  
  /* Haven't found a delegate / notification that triggers when the window is
   * ordered out (is not visible any more). You can be ordered out without
   * minimizing, so DidMiniaturize doesn't work. (e.g. -[NSWindow orderOut:])
   */
  [window addObserver:self
           forKeyPath:@"visible"
              options:NSKeyValueObservingOptionNew
              context:NULL];

  [window setNextResponder:self];
  [window setAcceptsMouseMovedEvents:YES];
  
  [view setNextResponder:self];
  
  if ([view respondsToSelector:@selector(setAcceptsTouchEvents:)])
  {
    [view setAcceptsTouchEvents:YES];
  }  
}

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary *)change
                       context:(void *)context
{
  NSLog(@"observeValueForKeyPath");
  if (!observingVisible) {
    return;
  }

  if (object == m_windowData->nswindow && [keyPath isEqualToString:@"visible"]) {
    int newVisibility = [[change objectForKey:@"new"] intValue];
    if (newVisibility) {
      //SDL_SendWindowEvent(_data->window, SDL_WINDOWEVENT_SHOWN, 0, 0);
    } else {
      //SDL_SendWindowEvent(_data->window, SDL_WINDOWEVENT_HIDDEN, 0, 0);
    }
  }
}

-(void) pauseVisibleObservation
{
  NSLog(@"pauseVisibleObservation");
  observingVisible = NO;
  wasVisible = [m_windowData->nswindow isVisible];
}

-(void) resumeVisibleObservation
{
  NSLog(@"resumeVisibleObservation");
  BOOL isVisible = [m_windowData->nswindow isVisible];
  observingVisible = YES;
  if (wasVisible != isVisible)
  {
    if (isVisible)
    {
      //SDL_SendWindowEvent(_data->window, SDL_WINDOWEVENT_SHOWN, 0, 0);
    }
    else
    {
      //SDL_SendWindowEvent(_data->window, SDL_WINDOWEVENT_HIDDEN, 0, 0);
    }
    
    wasVisible = isVisible;
  }
}

- (void)close
{
  NSLog(@"close");
  NSNotificationCenter *center;
  NSWindow *window = m_windowData->nswindow;
  NSView *view = [window contentView];
  NSArray *windows = nil;
  
  center = [NSNotificationCenter defaultCenter];
  
  if ([window delegate] != self) {
    [center removeObserver:self name:NSWindowDidExposeNotification object:window];
    [center removeObserver:self name:NSWindowDidMoveNotification object:window];
    [center removeObserver:self name:NSWindowDidResizeNotification object:window];
    [center removeObserver:self name:NSWindowDidMiniaturizeNotification object:window];
    [center removeObserver:self name:NSWindowDidDeminiaturizeNotification object:window];
    [center removeObserver:self name:NSWindowDidBecomeKeyNotification object:window];
    [center removeObserver:self name:NSWindowDidResignKeyNotification object:window];
  } else {
    [window setDelegate:nil];
  }
  
  [window removeObserver:self
              forKeyPath:@"visible"];
  
  if ([window nextResponder] == self) {
    [window setNextResponder:nil];
  }
  if ([view nextResponder] == self) {
    [view setNextResponder:nil];
  }
  
  /* Make the next window in the z-order Key. If we weren't the foreground
   when closed, this is a no-op.
   !!! FIXME: Note that this is a hack, and there are corner cases where
   !!! FIXME:  this fails (such as the About box). The typical nib+RunLoop
   !!! FIXME:  handles this for Cocoa apps, but we bypass all that in SDL.
   !!! FIXME:  We should remove this code when we find a better way to
   !!! FIXME:  have the system do this for us. See discussion in
   !!! FIXME:   http://bugzilla.libsdl.org/show_bug.cgi?id=1825
   */
  windows = [NSApp orderedWindows];
  if ([windows count] > 0) {
    NSWindow *win = (NSWindow *) [windows objectAtIndex:0];
    [win makeKeyAndOrderFront:self];
  }
}

- (BOOL)windowShouldClose:(id)sender
{
  NSLog(@"windowShouldClose");
  //SDL_SendWindowEvent(_data->window, SDL_WINDOWEVENT_CLOSE, 0, 0);
  return NO;
}

- (void)windowDidExpose:(NSNotification *)aNotification
{
  NSLog(@"windowDidExpose");
  //SDL_SendWindowEvent(_data->window, SDL_WINDOWEVENT_EXPOSED, 0, 0);
}

- (void)windowDidMove:(NSNotification *)aNotification
{
  NSLog(@"windowDidMove");
  NSWindow *nswindow = m_windowData->nswindow;
  NSRect rect = [nswindow contentRectForFrameRect:[nswindow frame]];
  //ConvertNSRect(&rect);
  
  //int x = (int)rect.origin.x;
  //int y = (int)rect.origin.y;
  
 // [(NSOpenGLContext *)_data->glcontext scheduleUpdate];
  //ScheduleContextUpdates(_data);
  
  //SDL_SendWindowEvent(window, SDL_WINDOWEVENT_MOVED, x, y);
}

- (void)windowDidResize:(NSNotification *)aNotification
{
  NSLog(@"windowDidResize");
  NSWindow *nswindow = m_windowData->nswindow;
  NSRect rect = [nswindow contentRectForFrameRect:[nswindow frame]];

  /*
  ConvertNSRect(&rect);
  int x = (int)rect.origin.x;
  int y = (int)rect.origin.y;
  int w = (int)rect.size.width;
  int h = (int)rect.size.height;
  if (SDL_IsShapedWindow(_data->window))
    Cocoa_ResizeWindowShape(_data->window);
  */
  
  //[(NSOpenGLContext *)m_windowData->glcontext scheduleUpdate];
  //ScheduleContextUpdates(_data);
  
  /* The window can move during a resize event, such as when maximizing
   or resizing from a corner */
  /*
  SDL_SendWindowEvent(_data->window, SDL_WINDOWEVENT_MOVED, x, y);
  SDL_SendWindowEvent(_data->window, SDL_WINDOWEVENT_RESIZED, w, h);
  
  const BOOL zoomed = [_data->nswindow isZoomed];
  if (!zoomed) {
    SDL_SendWindowEvent(_data->window, SDL_WINDOWEVENT_RESTORED, 0, 0);
  } else if (zoomed) {
    SDL_SendWindowEvent(_data->window, SDL_WINDOWEVENT_MAXIMIZED, 0, 0);
  }
  */
}

- (void)windowDidMiniaturize:(NSNotification *)aNotification
{
  NSLog(@"windowDidMiniaturize");
  //SDL_SendWindowEvent(_data->window, SDL_WINDOWEVENT_MINIMIZED, 0, 0);
}

- (void)windowDidDeminiaturize:(NSNotification *)aNotification
{
  NSLog(@"windowDidDeminiaturize");
  //SDL_SendWindowEvent(_data->window, SDL_WINDOWEVENT_RESTORED, 0, 0);
}

- (void)windowDidBecomeKey:(NSNotification *)aNotification
{
  NSLog(@"windowDidMiniaturize");
  //SDL_Window *window = _data->window;
  //SDL_Mouse *mouse = SDL_GetMouse();
  
  /* We're going to get keyboard events, since we're key. */
  //SDL_SetKeyboardFocus(window);
  
  /* If we just gained focus we need the updated mouse position */
  /*
  if (!mouse->relative_mode) {
    NSPoint point;
    int x, y;
    
    point = [_data->nswindow mouseLocationOutsideOfEventStream];
    x = (int)point.x;
    y = (int)(window->h - point.y);
    
    if (x >= 0 && x < window->w && y >= 0 && y < window->h) {
      SDL_SendMouseMotion(window, 0, 0, x, y);
    }
  }
  */
  
  /* Check to see if someone updated the clipboard */
  //Cocoa_CheckClipboardUpdate(_data->videodata);
}

- (void)windowDidResignKey:(NSNotification *)aNotification
{
  NSLog(@"windowDidResignKey");
  /* Some other window will get mouse events, since we're not key. */
  //if (SDL_GetMouseFocus() == _data->window) {
  //  SDL_SetMouseFocus(NULL);
  //}
  
  /* Some other window will get keyboard events, since we're not key. */
  //if (SDL_GetKeyboardFocus() == _data->window) {
  //  SDL_SetKeyboardFocus(NULL);
  //}
}

/*- (void)mouseMoved:(NSEvent *)theEvent
{
  NSLog(@"mouseMoved");
}*/

@end

//------------------------------------------------------------------------------------------
// special object-c class for handling the inhibit display NSTimer callback.
@interface windowInhibitScreenSaverClass : NSObject
- (void) updateSystemActivity: (NSTimer*)timer;
@end

@implementation windowInhibitScreenSaverClass
-(void) updateSystemActivity: (NSTimer*)timer
{
  UpdateSystemActivity(UsrActivity);
}
@end

//------------------------------------------------------------------------------------------
// special object-c class for handling the NSWindowDidMoveNotification callback.
@interface windowDidMoveNoteClass : NSObject
{
  void *m_userdata;
}
+ initWith: (void*) userdata;
-  (void) windowDidMoveNotification:(NSNotification*) note;
@end

@implementation windowDidMoveNoteClass
+ initWith: (void*) userdata;
{
    windowDidMoveNoteClass *windowDidMove = [windowDidMoveNoteClass new];
    windowDidMove->m_userdata = userdata;
    return [windowDidMove autorelease];
}
-  (void) windowDidMoveNotification:(NSNotification*) note;
{
  CWinSystemOSX *winsys = (CWinSystemOSX*)m_userdata;
	if (!winsys)
    return;

  NSOpenGLContext* context = [NSOpenGLContext currentContext];
  if (context)
  {
    if ([context view])
    {
      NSPoint window_origin = [[[context view] window] frame].origin;
      XBMC_Event newEvent;
      memset(&newEvent, 0, sizeof(newEvent));
      newEvent.type = XBMC_VIDEOMOVE;
      newEvent.move.x = window_origin.x;
      newEvent.move.y = window_origin.y;
      g_application.OnEvent(newEvent);
    }
  }
}
@end
//------------------------------------------------------------------------------------------
// special object-c class for handling the NSWindowDidReSizeNotification callback.
@interface windowDidReSizeNoteClass : NSObject
{
  void *m_userdata;
}
+ initWith: (void*) userdata;
- (void) windowDidReSizeNotification:(NSNotification*) note;
@end
@implementation windowDidReSizeNoteClass
+ initWith: (void*) userdata;
{
    windowDidReSizeNoteClass *windowDidReSize = [windowDidReSizeNoteClass new];
    windowDidReSize->m_userdata = userdata;
    return [windowDidReSize autorelease];
}
- (void) windowDidReSizeNotification:(NSNotification*) note;
{
  CWinSystemOSX *winsys = (CWinSystemOSX*)m_userdata;
	if (!winsys)
    return;
  /* placeholder, do not uncomment or you will SDL recurse into death
  NSOpenGLContext* context = [NSOpenGLContext currentContext];
  if (context)
  {
    if ([context view])
    {
      NSSize view_size = [[context view] frame].size;
      XBMC_Event newEvent;
      memset(&newEvent, 0, sizeof(newEvent));
      newEvent.type = XBMC_VIDEORESIZE;
      newEvent.resize.w = view_size.width;
      newEvent.resize.h = view_size.height;
      if (newEvent.resize.w * newEvent.resize.h)
      {
        g_application.OnEvent(newEvent);
        g_windowManager.MarkDirty();
      }
    }
  }
  */
}
@end
//------------------------------------------------------------------------------------------


#define MAX_DISPLAYS 32
static NSWindow* blankingWindows[MAX_DISPLAYS];

//------------------------------------------------------------------------------------------
CRect CGRectToCRect(CGRect cgrect)
{
  CRect crect = CRect(
    cgrect.origin.x,
    cgrect.origin.y,
    cgrect.origin.x + cgrect.size.width,
    cgrect.origin.y + cgrect.size.height);
  return crect;
}

//------------------------------------------------------------------------------------------
Boolean GetDictionaryBoolean(CFDictionaryRef theDict, const void* key)
{
        // get a boolean from the dictionary
        Boolean value = false;
        CFBooleanRef boolRef;
        boolRef = (CFBooleanRef)CFDictionaryGetValue(theDict, key);
        if (boolRef != NULL)
                value = CFBooleanGetValue(boolRef);
        return value;
}
//------------------------------------------------------------------------------------------
long GetDictionaryLong(CFDictionaryRef theDict, const void* key)
{
        // get a long from the dictionary
        long value = 0;
        CFNumberRef numRef;
        numRef = (CFNumberRef)CFDictionaryGetValue(theDict, key);
        if (numRef != NULL)
                CFNumberGetValue(numRef, kCFNumberLongType, &value);
        return value;
}
//------------------------------------------------------------------------------------------
int GetDictionaryInt(CFDictionaryRef theDict, const void* key)
{
        // get a long from the dictionary
        int value = 0;
        CFNumberRef numRef;
        numRef = (CFNumberRef)CFDictionaryGetValue(theDict, key);
        if (numRef != NULL)
                CFNumberGetValue(numRef, kCFNumberIntType, &value);
        return value;
}
//------------------------------------------------------------------------------------------
float GetDictionaryFloat(CFDictionaryRef theDict, const void* key)
{
        // get a long from the dictionary
        int value = 0;
        CFNumberRef numRef;
        numRef = (CFNumberRef)CFDictionaryGetValue(theDict, key);
        if (numRef != NULL)
                CFNumberGetValue(numRef, kCFNumberFloatType, &value);
        return value;
}
//------------------------------------------------------------------------------------------
double GetDictionaryDouble(CFDictionaryRef theDict, const void* key)
{
        // get a long from the dictionary
        double value = 0.0;
        CFNumberRef numRef;
        numRef = (CFNumberRef)CFDictionaryGetValue(theDict, key);
        if (numRef != NULL)
                CFNumberGetValue(numRef, kCFNumberDoubleType, &value);
        return value;
}

//---------------------------------------------------------------------------------
void SetMenuBarVisible(bool visible)
{
  if(visible)
  {
    [[NSApplication sharedApplication]
      setPresentationOptions:   NSApplicationPresentationDefault];
  }
  else
  {
    [[NSApplication sharedApplication]
      setPresentationOptions:   NSApplicationPresentationHideMenuBar |
                                NSApplicationPresentationHideDock];
  }
}
//---------------------------------------------------------------------------------
CGDirectDisplayID GetDisplayID(int screen_index)
{
  CGDirectDisplayID displayArray[MAX_DISPLAYS];
  CGDisplayCount    numDisplays;

  // Get the list of displays.
  CGGetActiveDisplayList(MAX_DISPLAYS, displayArray, &numDisplays);
  return(displayArray[screen_index]);
}

CGDirectDisplayID GetDisplayIDFromScreen(NSScreen *screen)
{
  NSDictionary* screenInfo = [screen deviceDescription];
  NSNumber* screenID = [screenInfo objectForKey:@"NSScreenNumber"];

  return (CGDirectDisplayID)[screenID longValue];
}

int GetDisplayIndex(CGDirectDisplayID display)
{
  CGDirectDisplayID displayArray[MAX_DISPLAYS];
  CGDisplayCount    numDisplays;

  // Get the list of displays.
  CGGetActiveDisplayList(MAX_DISPLAYS, displayArray, &numDisplays);
  while (numDisplays > 0)
  {
    if (display == displayArray[--numDisplays])
	  return numDisplays;
  }
  return -1;
}

void BlankOtherDisplays(int screen_index)
{
  int i;
  int numDisplays = [[NSScreen screens] count];

  // zero out blankingWindows for debugging
  for (i=0; i<MAX_DISPLAYS; i++)
  {
    blankingWindows[i] = 0;
  }

  // Blank.
  for (i=0; i<numDisplays; i++)
  {
    if (i != screen_index)
    {
      // Get the size.
      NSScreen* pScreen = [[NSScreen screens] objectAtIndex:i];
      NSRect    screenRect = [pScreen frame];

      // Build a blanking window.
      screenRect.origin = NSZeroPoint;
      blankingWindows[i] = [[NSWindow alloc] initWithContentRect:screenRect
        styleMask:NSBorderlessWindowMask
        backing:NSBackingStoreBuffered
        defer:NO
        screen:pScreen];

      [blankingWindows[i] setBackgroundColor:[NSColor blackColor]];
      [blankingWindows[i] setLevel:CGShieldingWindowLevel()];
      [blankingWindows[i] makeKeyAndOrderFront:nil];
    }
  }
}

void UnblankDisplays(void)
{
  int numDisplays = [[NSScreen screens] count];
  int i = 0;

  for (i=0; i<numDisplays; i++)
  {
    if (blankingWindows[i] != 0)
    {
      // Get rid of the blanking windows we created.
      [blankingWindows[i] close];
      if ([blankingWindows[i] isReleasedWhenClosed] == NO)
        [blankingWindows[i] release];
      blankingWindows[i] = 0;
    }
  }
}

CGDisplayFadeReservationToken DisplayFadeToBlack(bool fade)
{
  // Fade to black to hide resolution-switching flicker and garbage.
  CGDisplayFadeReservationToken fade_token = kCGDisplayFadeReservationInvalidToken;
  if (CGAcquireDisplayFadeReservation (5, &fade_token) == kCGErrorSuccess && fade)
    CGDisplayFade(fade_token, 0.3, kCGDisplayBlendNormal, kCGDisplayBlendSolidColor, 0.0, 0.0, 0.0, TRUE);

  return(fade_token);
}

void DisplayFadeFromBlack(CGDisplayFadeReservationToken fade_token, bool fade)
{
  if (fade_token != kCGDisplayFadeReservationInvalidToken)
  {
    if (fade)
      CGDisplayFade(fade_token, 0.5, kCGDisplayBlendSolidColor, kCGDisplayBlendNormal, 0.0, 0.0, 0.0, FALSE);
    CGReleaseDisplayFadeReservation(fade_token);
  }
}

NSString* screenNameForDisplay(CGDirectDisplayID displayID)
{
  NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];

  NSString *screenName = nil;

  NSDictionary *deviceInfo = (NSDictionary *)IODisplayCreateInfoDictionary(CGDisplayIOServicePort(displayID), kIODisplayOnlyPreferredName);
  NSDictionary *localizedNames = [deviceInfo objectForKey:[NSString stringWithUTF8String:kDisplayProductName]];

  if ([localizedNames count] > 0) {
      screenName = [[localizedNames objectForKey:[[localizedNames allKeys] objectAtIndex:0]] retain];
  }

  [deviceInfo release];
  [pool release];

  return [screenName autorelease];
}

void ShowHideNSWindow(WindowData *windowData, bool show)
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  NSWindow *nswindow = windowData->nswindow;
  
  if ( show )
  {
    [windowData->listener pauseVisibleObservation];
    [nswindow makeKeyAndOrderFront:nil];
    [windowData->listener resumeVisibleObservation];
  }
  else
  {
    [windowData->listener pauseVisibleObservation];
    [nswindow orderOut:nil];
    [windowData->listener resumeVisibleObservation];
  }
  [pool release];

  /*
  if (show)
    [wind orderFront:nil];
  else
    [wind orderOut:nil];
  */
}

static NSWindow *curtainWindow;
void fadeInDisplay(NSScreen *theScreen, double fadeTime)
{
  int     fadeSteps     = 100;
  double  fadeInterval  = (fadeTime / (double) fadeSteps);

  if (curtainWindow != nil)
  {
    for (int step = 0; step < fadeSteps; step++)
    {
      double fade = 1.0 - (step * fadeInterval);
      [curtainWindow setAlphaValue:fade];

      NSDate *nextDate = [NSDate dateWithTimeIntervalSinceNow:fadeInterval];
      [[NSRunLoop currentRunLoop] runUntilDate:nextDate];
    }
  }
  [curtainWindow close];
  curtainWindow = nil;

  [NSCursor unhide];
}

void fadeOutDisplay(NSScreen *theScreen, double fadeTime)
{
  int     fadeSteps     = 100;
  double  fadeInterval  = (fadeTime / (double) fadeSteps);

  [NSCursor hide];

  curtainWindow = [[NSWindow alloc]
    initWithContentRect:[theScreen frame]
    styleMask:NSBorderlessWindowMask
    backing:NSBackingStoreBuffered
    defer:YES
    screen:theScreen];

  [curtainWindow setAlphaValue:0.0];
  [curtainWindow setBackgroundColor:[NSColor blackColor]];
  [curtainWindow setLevel:NSScreenSaverWindowLevel];

  [curtainWindow makeKeyAndOrderFront:nil];
  [curtainWindow setFrame:[curtainWindow
    frameRectForContentRect:[theScreen frame]]
    display:YES
    animate:NO];

  for (int step = 0; step < fadeSteps; step++)
  {
    double fade = step * fadeInterval;
    [curtainWindow setAlphaValue:fade];

    NSDate *nextDate = [NSDate dateWithTimeIntervalSinceNow:fadeInterval];
    [[NSRunLoop currentRunLoop] runUntilDate:nextDate];
  }
}

// try to find mode that matches the desired size, refreshrate
// non interlaced, nonstretched, safe for hardware
CFDictionaryRef GetMode(int width, int height, double refreshrate, int screenIdx)
{
  if ( screenIdx >= (signed)[[NSScreen screens] count])
    return NULL;

  Boolean stretched;
  Boolean interlaced;
  Boolean safeForHardware;
  Boolean televisionoutput;
  int w, h, bitsperpixel;
  double rate;
  RESOLUTION_INFO res;

  CLog::Log(LOGDEBUG, "GetMode looking for suitable mode with %d x %d @ %f Hz on display %d\n", width, height, refreshrate, screenIdx);

  CFArrayRef displayModes = CGDisplayAvailableModes(GetDisplayID(screenIdx));

  if (NULL == displayModes)
  {
    CLog::Log(LOGERROR, "GetMode - no displaymodes found!");
    return NULL;
  }

  for (int i=0; i < CFArrayGetCount(displayModes); ++i)
  {
    CFDictionaryRef displayMode = (CFDictionaryRef)CFArrayGetValueAtIndex(displayModes, i);

    stretched = GetDictionaryBoolean(displayMode, kCGDisplayModeIsStretched);
    interlaced = GetDictionaryBoolean(displayMode, kCGDisplayModeIsInterlaced);
    bitsperpixel = GetDictionaryInt(displayMode, kCGDisplayBitsPerPixel);
    safeForHardware = GetDictionaryBoolean(displayMode, kCGDisplayModeIsSafeForHardware);
    televisionoutput = GetDictionaryBoolean(displayMode, kCGDisplayModeIsTelevisionOutput);
    w = GetDictionaryInt(displayMode, kCGDisplayWidth);
    h = GetDictionaryInt(displayMode, kCGDisplayHeight);
    rate = GetDictionaryDouble(displayMode, kCGDisplayRefreshRate);


    if ((bitsperpixel == 32)      &&
        (safeForHardware == YES)  &&
        (stretched == NO)         &&
        (interlaced == NO)        &&
        (w == width)              &&
        (h == height)             &&
        (rate == refreshrate || rate == 0))
    {
      CLog::Log(LOGDEBUG, "GetMode found a match!");
      return displayMode;
    }
  }
  CLog::Log(LOGERROR, "GetMode - no match found!");
  return NULL;
}

//---------------------------------------------------------------------------------
static void DisplayReconfigured(CGDirectDisplayID display,
  CGDisplayChangeSummaryFlags flags, void* userData)
{
  CWinSystemOSX *winsys = (CWinSystemOSX*)userData;
	if (!winsys)
    return;

  if (flags & kCGDisplaySetModeFlag || flags & kCGDisplayBeginConfigurationFlag)
  {
    // pre/post-reconfiguration changes
    RESOLUTION res = g_graphicsContext.GetVideoResolution();
    if (res == RES_INVALID)
      return;

    NSScreen* pScreen = nil;
    unsigned int screenIdx = CDisplaySettings::Get().GetResolutionInfo(res).iScreen;

    if ( screenIdx < [[NSScreen screens] count] )
    {
        pScreen = [[NSScreen screens] objectAtIndex:screenIdx];
    }

    if (pScreen)
    {
      CGDirectDisplayID xbmc_display = GetDisplayIDFromScreen(pScreen);
      if (xbmc_display == display)
      {
        // we only respond to changes on the display we are running on.
        CLog::Log(LOGDEBUG, "CWinSystemOSX::DisplayReconfigured");
        winsys->CheckDisplayChanging(flags);
      }
    }
  }
}

//---------------------------------------------------------------------------------
//---------------------------------------------------------------------------------
CWinSystemOSX::CWinSystemOSX() : CWinSystemBase()
{
  m_eWindowSystem = WINDOW_SYSTEM_OSX;
  m_glContext = 0;
  m_osx_events = NULL;
  m_obscured   = false;
  m_windowData = NULL;
  m_obscured_timecheck = XbmcThreads::SystemClockMillis() + 1000;
  m_use_system_screensaver = true;
  // check runtime, we only allow this on 10.5+
  m_can_display_switch = (floor(NSAppKitVersionNumber) >= 949);
}

CWinSystemOSX::~CWinSystemOSX()
{
};

bool CWinSystemOSX::InitWindowSystem()
{
  if (!CWinSystemBase::InitWindowSystem())
    return false;

  m_osx_events = new CWinEventsOSX();
  m_osx_events->EnableInput();

  if (m_can_display_switch)
    CGDisplayRegisterReconfigurationCallback(DisplayReconfigured, (void*)this);

  /*
  NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
  windowDidMoveNoteClass *windowDidMove;
  windowDidMove = [windowDidMoveNoteClass initWith: this];
  [center addObserver:windowDidMove
    selector:@selector(windowDidMoveNotification:)
    name:NSWindowDidMoveNotification object:nil];
  m_windowDidMove = windowDidMove;


  windowDidReSizeNoteClass *windowDidReSize;
  windowDidReSize = [windowDidReSizeNoteClass initWith: this];
  [center addObserver:windowDidReSize
    selector:@selector(windowDidReSizeNotification:)
    name:NSWindowDidResizeNotification object:nil];
  m_windowDidReSize = windowDidReSize;
  */
  
  return true;
}

bool CWinSystemOSX::DestroyWindowSystem()
{
  /*
  NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
  [center removeObserver:(windowDidMoveNoteClass*)m_windowDidMove name:NSWindowDidMoveNotification object:nil];
  [center removeObserver:(windowDidReSizeNoteClass*)m_windowDidReSize name:NSWindowDidResizeNotification object:nil];
  */
  
  if (m_can_display_switch)
    CGDisplayRemoveReconfigurationCallback(DisplayReconfigured, (void*)this);

  delete m_osx_events;
  m_osx_events = NULL;

  UnblankDisplays();
  if (m_glContext)
  {
    NSOpenGLContext* oldContext = (NSOpenGLContext*)m_glContext;
    [oldContext release];
    m_glContext = NULL;
  }
  return true;
}

bool CWinSystemOSX::CreateNewWindow(const CStdString& name, bool fullScreen, RESOLUTION_INFO& res, PHANDLE_EVENT_FUNC userFunction)
{
  printf("CreateNewWindow\n");
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  
  m_nWidth  = res.iWidth;
  m_nHeight = res.iHeight;
  m_bFullScreen = fullScreen;

  m_windowData = (WindowData *)calloc(1, sizeof(WindowData));

  
  NSUInteger windowStyleMask = NSTitledWindowMask|NSResizableWindowMask|NSClosableWindowMask|NSMiniaturizableWindowMask;
  NSWindow *appWindow = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0,
                            m_nWidth, m_nHeight) styleMask:windowStyleMask backing:NSBackingStoreBuffered defer:NO];
  appWindow.backgroundColor = [NSColor blackColor];
  appWindow.title = @"XBMC Media Center";
  [appWindow makeKeyAndOrderFront:nil];
  [appWindow setOneShot:NO];
  
  // create new content view
  NSRect rect = [appWindow contentRectForFrameRect:[appWindow frame]];
  NSView *contentView = [[NSView alloc] initWithFrame:rect];

  // associate with current window
  [appWindow setContentView: contentView];
  [contentView release];
  
  // create a new gl context
  m_glContext = (NSOpenGLContext*)CreateWindowedContext(nil);

  // associate with current view
  [(NSOpenGLContext *)m_glContext setView:[appWindow contentView]];
  [(NSOpenGLContext *)m_glContext makeCurrentContext];

  m_bWindowCreated = true;
  
  m_windowData = (WindowData *)calloc(1, sizeof(WindowData));
  
  m_windowData->created = m_bWindowCreated;
  m_windowData->nswindow  = appWindow;
  m_windowData->glcontext = (NSOpenGLContext*)m_glContext;
  m_windowData->listener  = [[WindowListener alloc] init];
  [m_windowData->listener listen:m_windowData];
  
  [pool release];
  
  return true;
}

bool CWinSystemOSX::DestroyWindow()
{
  printf("DestroyWindow\n");
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  
  if(m_windowData)
  {
    [m_windowData->listener close];
    [m_windowData->listener release];
    
    // release the context
    if ( m_glContext )
    {
      [ NSOpenGLContext clearCurrentContext ];
      [ (NSOpenGLContext *)m_glContext clearDrawable ];
      [ (NSOpenGLContext *)m_glContext release ];
      m_glContext = NULL;
    }
    
    if (m_windowData->created)
    {
      [(NSWindow *)m_windowData->nswindow close];
    }

    free(m_windowData);
    m_windowData = NULL;
  }
  
  [pool release];
  return true;
}

//extern "C" void SDL_SetWidthHeight(int w, int h);
bool CWinSystemOSX::ResizeWindow(int newWidth, int newHeight, int newLeft, int newTop)
{
  if (!m_glContext)
    return false;

  NSOpenGLContext* context = [NSOpenGLContext currentContext];
  NSView* view;
  NSWindow* window;

  view = [context view];
  if (view && (newWidth > 0) && (newHeight > 0))
  {
    window = [view window];
    if (window)
    {
      [window setContentSize:NSMakeSize(newWidth, newHeight)];
      [window update];
      [view setFrameSize:NSMakeSize(newWidth, newHeight)];
      [context update];
    }
  }

  // HACK: resize SDL's view manually so that mouse bounds are correctly updated.
  // there are two parts to this, the internal SDL (current_video->screen) and
  // the cocoa view ( handled in SetFullScreen).
  //SDL_SetWidthHeight(newWidth, newHeight);

  [context makeCurrentContext];

  m_nWidth = newWidth;
  m_nHeight = newHeight;
  m_glContext = context;

  return true;
}

static bool needtoshowme = true;

bool CWinSystemOSX::SetFullScreen(bool fullScreen, RESOLUTION_INFO& res, bool blankOtherDisplays)
{
  printf("CWinSystemOSX::SetFullScreen\n");
  static NSWindow* windowedFullScreenwindow = NULL;
  static NSScreen* last_window_screen = NULL;
  static NSPoint last_window_origin;
  static NSView* last_view = NULL;
  static NSSize last_view_size;
  static NSPoint last_view_origin;
  static NSInteger last_window_level = NSNormalWindowLevel;
  bool was_fullscreen = m_bFullScreen;
  static int lastDisplayNr = res.iScreen;
  NSOpenGLContext* cur_context;

  // Fade to black to hide resolution-switching flicker and garbage.
  CGDisplayFadeReservationToken fade_token = DisplayFadeToBlack(needtoshowme);

  // If we're already fullscreen then we must be moving to a different display.
  // or if we are still on the same display - it might be only a refreshrate/resolution
  // change request.
  // Recurse to reset fullscreen mode and then continue.
  if (was_fullscreen && fullScreen)
  {
    needtoshowme = false;
    ShowHideNSWindow(m_windowData, needtoshowme);
    RESOLUTION_INFO& window = CDisplaySettings::Get().GetResolutionInfo(RES_WINDOW);
    CWinSystemOSX::SetFullScreen(false, window, blankOtherDisplays);
    needtoshowme = true;
  }

  m_nWidth      = res.iWidth;
  m_nHeight     = res.iHeight;
  m_bFullScreen = fullScreen;

  cur_context = [NSOpenGLContext currentContext];
  
  //handle resolution/refreshrate switching early here
  if (m_bFullScreen)
  {
    if (m_can_display_switch)
    {
      // send pre-configuration change now and do not
      //  wait for switch videomode callback. This gives just
      //  a little more advanced notice of the display pre-change.
      if (CSettings::Get().GetInt("videoplayer.adjustrefreshrate") != ADJUST_REFRESHRATE_OFF)
        CheckDisplayChanging(kCGDisplayBeginConfigurationFlag);

      // switch videomode
      SwitchToVideoMode(res.iWidth, res.iHeight, res.fRefreshRate, res.iScreen);
      lastDisplayNr = res.iScreen;
    }
  }

  //no context? done.
  if (!cur_context)
  {
    DisplayFadeFromBlack(fade_token, needtoshowme);
    return false;
  }

  if (windowedFullScreenwindow != NULL)
  {
    [windowedFullScreenwindow close];
    if ([windowedFullScreenwindow isReleasedWhenClosed] == NO)
      [windowedFullScreenwindow release];
    windowedFullScreenwindow = NULL;
  }

  if (m_bFullScreen)
  {
    // FullScreen Mode
    NSOpenGLContext* newContext = NULL;

    // Save info about the windowed context so we can restore it when returning to windowed.
    last_view = [cur_context view];
    last_view_size = [last_view frame].size;
    last_view_origin = [last_view frame].origin;
    last_window_screen = [[last_view window] screen];
    last_window_origin = [[last_view window] frame].origin;
    last_window_level = [[last_view window] level];

    if (CSettings::Get().GetBool("videoscreen.fakefullscreen"))
    {
      // This is Cocca Windowed FullScreen Mode
      // Get the screen rect of our current display
      NSScreen* pScreen = [[NSScreen screens] objectAtIndex:res.iScreen];
      NSRect    screenRect = [pScreen frame];

      // remove frame origin offset of orginal display
      screenRect.origin = NSZeroPoint;

      // make a new window to act as the windowedFullScreen
      windowedFullScreenwindow = [[NSWindow alloc] initWithContentRect:screenRect
        styleMask:NSBorderlessWindowMask
        backing:NSBackingStoreBuffered
        defer:NO
        screen:pScreen];

      [windowedFullScreenwindow setBackgroundColor:[NSColor blackColor]];
      [windowedFullScreenwindow makeKeyAndOrderFront:nil];

      // make our window the same level as the rest to enable cmd+tab switching
      [windowedFullScreenwindow setLevel:NSNormalWindowLevel];
      // this will make our window topmost and hide all system messages
      //[windowedFullScreenwindow setLevel:CGShieldingWindowLevel()];

      // ...and the original one beneath it and on the same screen.
      [[last_view window] setLevel:NSNormalWindowLevel-1];
      [[last_view window] setFrameOrigin:[pScreen frame].origin];
      // expand the mouse bounds in SDL view to fullscreen
      [ last_view setFrameOrigin:NSMakePoint(0.0, 0.0)];
      [ last_view setFrameSize:NSMakeSize(m_nWidth, m_nHeight) ];

      NSView* blankView = [[NSView alloc] init];
      [windowedFullScreenwindow setContentView:blankView];
      [windowedFullScreenwindow setContentSize:NSMakeSize(m_nWidth, m_nHeight)];
      [windowedFullScreenwindow update];
      [blankView setFrameSize:NSMakeSize(m_nWidth, m_nHeight)];

      // Obtain windowed pixel format and create a new context.
      newContext = (NSOpenGLContext*)CreateWindowedContext((void* )cur_context);
      [newContext setView:blankView];

      // Hide the menu bar.
      if (GetDisplayID(res.iScreen) == kCGDirectMainDisplay)
        SetMenuBarVisible(false);

      // Blank other displays if requested.
      if (blankOtherDisplays)
        BlankOtherDisplays(res.iScreen);
    }
    else
    {
      // hide the window
      [[last_view window] setFrameOrigin:[last_window_screen frame].origin];
      // expand the mouse bounds in SDL view to fullscreen
      [ last_view setFrameOrigin:NSMakePoint(0.0, 0.0)];
      [ last_view setFrameSize:NSMakeSize(m_nWidth, m_nHeight) ];

      // This is OpenGL FullScreen Mode
      // create our new context (sharing with the current one)
      newContext = (NSOpenGLContext*)CreateFullScreenContext(res.iScreen, (void*)cur_context);
      if (!newContext)
        return false;

      // clear the current context
      [NSOpenGLContext clearCurrentContext];

      // set fullscreen
      [newContext setFullScreen];

      // Capture the display before going fullscreen.
      if (blankOtherDisplays == true)
        CGCaptureAllDisplays();
      else
        CGDisplayCapture(GetDisplayID(res.iScreen));

      // If we don't hide menu bar, it will get events and interrupt the program.
      if (GetDisplayID(res.iScreen) == kCGDirectMainDisplay)
        SetMenuBarVisible(false);
    }

    // Hide the mouse.
    [NSCursor hide];

    // Release old context if we created it.
    if (m_glContext == cur_context)
    {
      [ NSOpenGLContext clearCurrentContext ];
      [ cur_context clearDrawable ];
      [ cur_context release ];
    }

    // activate context
    [newContext makeCurrentContext];
    m_glContext = newContext;
  }
  else
  {
    // Windowed Mode
    // exit fullscreen
    [cur_context clearDrawable];

    [NSCursor unhide];

    // Show menubar.
    if (GetDisplayID(res.iScreen) == kCGDirectMainDisplay)
      SetMenuBarVisible(true);

    if (CSettings::Get().GetBool("videoscreen.fakefullscreen"))
    {
      // restore the windowed window level
      [[last_view window] setLevel:last_window_level];

      // Get rid of the new window we created.
      if (windowedFullScreenwindow != NULL)
      {
        [windowedFullScreenwindow close];
        if ([windowedFullScreenwindow isReleasedWhenClosed] == NO)
          [windowedFullScreenwindow release];
        windowedFullScreenwindow = NULL;
      }

      // Unblank.
      // Force the unblank when returning from fullscreen, we get called with blankOtherDisplays set false.
      //if (blankOtherDisplays)
        UnblankDisplays();
    }
    else
    {
      // release displays
      CGReleaseAllDisplays();
    }

    // create our new context (sharing with the current one)
    NSOpenGLContext* newContext = (NSOpenGLContext*)CreateWindowedContext((void* )cur_context);
    if (!newContext)
      return false;

    // Assign view from old context, move back to original screen.
    [newContext setView:last_view];
    [[last_view window] setFrameOrigin:last_window_origin];
    // return the mouse bounds in SDL view to prevous size
    [ last_view setFrameSize:last_view_size ];
    [ last_view setFrameOrigin:last_view_origin ];
    // done with restoring windowed window, don't set last_view to NULL as we can lose it under dual displays.
    //last_window_screen = NULL;

    // Release the fullscreen context.
    if (m_glContext == cur_context)
    {
      [ NSOpenGLContext clearCurrentContext ];
      [ cur_context clearDrawable ];
      [ cur_context release ];
    }

    // Activate context.
    [newContext makeCurrentContext];
    m_glContext = newContext;
  }

  DisplayFadeFromBlack(fade_token, needtoshowme);

  ShowHideNSWindow(m_windowData, needtoshowme);
  // need to make sure SDL tracks any window size changes
  ResizeWindow(m_nWidth, m_nHeight, -1, -1);

  return true;
}

void CWinSystemOSX::UpdateResolutions()
{
  CWinSystemBase::UpdateResolutions();

  // Add desktop resolution
  int w, h;
  double fps;

  // first screen goes into the current desktop mode
  GetScreenResolution(&w, &h, &fps, 0);
  UpdateDesktopResolution(CDisplaySettings::Get().GetResolutionInfo(RES_DESKTOP), 0, w, h, fps);

  // see resolution.h enum RESOLUTION for how the resolutions
  // have to appear in the resolution info vector in CDisplaySettings
  // add the desktop resolutions of the other screens
  for(int i = 1; i < GetNumScreens(); i++)
  {
    RESOLUTION_INFO res;
    // get current resolution of screen i
    GetScreenResolution(&w, &h, &fps, i);
    UpdateDesktopResolution(res, i, w, h, fps);
    CDisplaySettings::Get().AddResolutionInfo(res);
  }

  if (m_can_display_switch)
  {
    // now just fill in the possible reolutions for the attached screens
    // and push to the resolution info vector
    FillInVideoModes();
  }
}

void* CWinSystemOSX::CreateWindowedContext(void* shareCtx)
{
  NSOpenGLContext* newContext = NULL;
  GLint swapInterval = 1;

  
  NSOpenGLPixelFormatAttribute wattrs[] =
  {
    NSOpenGLPFADoubleBuffer,
    NSOpenGLPFAWindow,
    NSOpenGLPFANoRecovery,
    NSOpenGLPFAAccelerated,
    NSOpenGLPFADepthSize,
   (NSOpenGLPixelFormatAttribute)8,
   (NSOpenGLPixelFormatAttribute)0
  };

  NSOpenGLPixelFormat* pixFmt = [[NSOpenGLPixelFormat alloc] initWithAttributes:wattrs];

  newContext = [[NSOpenGLContext alloc] initWithFormat:(NSOpenGLPixelFormat*)pixFmt
    shareContext:(NSOpenGLContext*)shareCtx];
  [pixFmt release];

  if (!newContext)
  {
    // bah, try again for non-accelerated renderer
    NSOpenGLPixelFormatAttribute wattrs2[] =
    {
      NSOpenGLPFADoubleBuffer,
      NSOpenGLPFAWindow,
      NSOpenGLPFANoRecovery,
      NSOpenGLPFADepthSize,
     (NSOpenGLPixelFormatAttribute)8,
     (NSOpenGLPixelFormatAttribute)0
    };
    NSOpenGLPixelFormat* pixFmt = [[NSOpenGLPixelFormat alloc] initWithAttributes:wattrs2];

    newContext = [[NSOpenGLContext alloc] initWithFormat:(NSOpenGLPixelFormat*)pixFmt
      shareContext:(NSOpenGLContext*)shareCtx];
    [pixFmt release];
  }
  
  [newContext setValues:&swapInterval forParameter:NSOpenGLCPSwapInterval];

  return newContext;
}

void* CWinSystemOSX::CreateFullScreenContext(int screen_index, void* shareCtx)
{
  CGDirectDisplayID displayArray[MAX_DISPLAYS];
  CGDisplayCount    numDisplays;
  CGDirectDisplayID displayID;

  // Get the list of displays.
  CGGetActiveDisplayList(MAX_DISPLAYS, displayArray, &numDisplays);
  displayID = displayArray[screen_index];

  NSOpenGLPixelFormatAttribute fsattrs[] =
  {
    NSOpenGLPFADoubleBuffer,
    NSOpenGLPFAFullScreen,
    NSOpenGLPFANoRecovery,
    NSOpenGLPFAAccelerated,
    NSOpenGLPFADepthSize,  (NSOpenGLPixelFormatAttribute)8,
    NSOpenGLPFAScreenMask, (NSOpenGLPixelFormatAttribute)CGDisplayIDToOpenGLDisplayMask(displayID),
   (NSOpenGLPixelFormatAttribute)0
  };

  NSOpenGLPixelFormat* pixFmt = [[NSOpenGLPixelFormat alloc] initWithAttributes:fsattrs];
  if (!pixFmt)
    return nil;

  NSOpenGLContext* newContext = [[NSOpenGLContext alloc] initWithFormat:(NSOpenGLPixelFormat*)pixFmt
    shareContext:(NSOpenGLContext*)shareCtx];
  [pixFmt release];

  return newContext;
}

void CWinSystemOSX::GetScreenResolution(int* w, int* h, double* fps, int screenIdx)
{
  // Figure out the screen size. (default to main screen)
  if (screenIdx >= GetNumScreens())
    return;

  CGDirectDisplayID display_id = (CGDirectDisplayID)GetDisplayID(screenIdx);

  NSOpenGLContext* context = [NSOpenGLContext currentContext];
  if (context)
  {
    NSView* view;

    view = [context view];
    if (view)
    {
      NSWindow* window;
      window = [view window];
      if (window)
        display_id = GetDisplayIDFromScreen( [window screen] );
    }
  }
  CGDisplayModeRef mode  = CGDisplayCopyDisplayMode(display_id);
  *w = CGDisplayModeGetWidth(mode);
  *h = CGDisplayModeGetHeight(mode);
  *fps = CGDisplayModeGetRefreshRate(mode);
  CGDisplayModeRelease(mode);
  if ((int)*fps == 0)
  {
    // NOTE: The refresh rate will be REPORTED AS 0 for many DVI and notebook displays.
    *fps = 60.0;
  }
}

void CWinSystemOSX::EnableVSync(bool enable)
{
  // OpenGL Flush synchronised with vertical retrace
  GLint swapInterval = enable ? 1 : 0;
  [[NSOpenGLContext currentContext] setValues:&swapInterval forParameter:NSOpenGLCPSwapInterval];
}

bool CWinSystemOSX::SwitchToVideoMode(int width, int height, double refreshrate, int screenIdx)
{
  // SwitchToVideoMode will not return until the display has actually switched over.
  // This can take several seconds.
  if( screenIdx >= GetNumScreens())
    return false;

  boolean_t match = false;
  CFDictionaryRef dispMode = NULL;
  // Figure out the screen size. (default to main screen)
  CGDirectDisplayID display_id = GetDisplayID(screenIdx);

  // find mode that matches the desired size, refreshrate
  // non interlaced, nonstretched, safe for hardware
  dispMode = GetMode(width, height, refreshrate, screenIdx);

  //not found - fallback to bestemdeforparameters
  if (!dispMode)
  {
    dispMode = CGDisplayBestModeForParameters(display_id, 32, width, height, &match);

    if (!match)
      dispMode = CGDisplayBestModeForParameters(display_id, 16, width, height, &match);

    if (!match)
      return false;
  }

  // switch mode and return success
  CGDisplayCapture(display_id);
  CGDisplayConfigRef cfg;
  CGBeginDisplayConfiguration(&cfg);
  // we don't need to do this, we are already faded.
  //CGConfigureDisplayFadeEffect(cfg, 0.3f, 0.5f, 0, 0, 0);
  CGConfigureDisplayMode(cfg, display_id, dispMode);
  CGError err = CGCompleteDisplayConfiguration(cfg, kCGConfigureForAppOnly);
  CGDisplayRelease(display_id);

  Cocoa_CVDisplayLinkUpdate();

  return (err == kCGErrorSuccess);
}

void CWinSystemOSX::FillInVideoModes()
{
  // Add full screen settings for additional monitors
  int numDisplays = [[NSScreen screens] count];

  for (int disp = 0; disp < numDisplays; disp++)
  {
    Boolean stretched;
    Boolean interlaced;
    Boolean safeForHardware;
    Boolean televisionoutput;
    int w, h, bitsperpixel;
    double refreshrate;
    RESOLUTION_INFO res;

    CFArrayRef displayModes = CGDisplayAvailableModes(GetDisplayID(disp));
    NSString *dispName = screenNameForDisplay(GetDisplayID(disp));
    CLog::Log(LOGNOTICE, "Display %i has name %s", disp, [dispName UTF8String]);

    if (NULL == displayModes)
      continue;

    for (int i=0; i < CFArrayGetCount(displayModes); ++i)
    {
      CFDictionaryRef displayMode = (CFDictionaryRef)CFArrayGetValueAtIndex(displayModes, i);

      stretched = GetDictionaryBoolean(displayMode, kCGDisplayModeIsStretched);
      interlaced = GetDictionaryBoolean(displayMode, kCGDisplayModeIsInterlaced);
      bitsperpixel = GetDictionaryInt(displayMode, kCGDisplayBitsPerPixel);
      safeForHardware = GetDictionaryBoolean(displayMode, kCGDisplayModeIsSafeForHardware);
      televisionoutput = GetDictionaryBoolean(displayMode, kCGDisplayModeIsTelevisionOutput);

      if ((bitsperpixel == 32)      &&
          (safeForHardware == YES)  &&
          (stretched == NO)         &&
          (interlaced == NO))
      {
        w = GetDictionaryInt(displayMode, kCGDisplayWidth);
        h = GetDictionaryInt(displayMode, kCGDisplayHeight);
        refreshrate = GetDictionaryDouble(displayMode, kCGDisplayRefreshRate);
        if ((int)refreshrate == 0)  // LCD display?
        {
          // NOTE: The refresh rate will be REPORTED AS 0 for many DVI and notebook displays.
          refreshrate = 60.0;
        }
        CLog::Log(LOGNOTICE, "Found possible resolution for display %d with %d x %d @ %f Hz\n", disp, w, h, refreshrate);

        UpdateDesktopResolution(res, disp, w, h, refreshrate);

        // overwrite the mode str because  UpdateDesktopResolution adds a
        // "Full Screen". Since the current resolution is there twice
        // this would lead to 2 identical resolution entrys in the guisettings.xml.
        // That would cause problems with saving screen overscan calibration
        // because the wrong entry is picked on load.
        // So we just use UpdateDesktopResolutions for the current DESKTOP_RESOLUTIONS
        // in UpdateResolutions. And on all othere resolutions make a unique
        // mode str by doing it without appending "Full Screen".
        // this is what linux does - though it feels that there shouldn't be
        // the same resolution twice... - thats why i add a FIXME here.
        res.strMode.Format("%dx%d @ %.2f", w, h, refreshrate);
        g_graphicsContext.ResetOverscan(res);
        CDisplaySettings::Get().AddResolutionInfo(res);
      }
    }
  }
}

bool CWinSystemOSX::FlushBuffer(void)
{
  [ (NSOpenGLContext*)m_glContext flushBuffer ];

  return true;
}

bool CWinSystemOSX::IsObscured(void)
{
  // check once a second if we are obscured.
  unsigned int now_time = XbmcThreads::SystemClockMillis();
  if (m_obscured_timecheck > now_time)
    return m_obscured;
  else
    m_obscured_timecheck = now_time + 1000;

  NSOpenGLContext* cur_context = [NSOpenGLContext currentContext];
  NSView* view = [cur_context view];
  if (!view)
  {
    // sanity check, we should always have a view
    m_obscured = true;
    return m_obscured;
  }

  NSWindow *window = [view window];
  if (!window)
  {
    // sanity check, we should always have a window
    m_obscured = true;
    return m_obscured;
  }

  if ([window isVisible] == NO)
  {
    // not visable means the window is not showing.
    // this should never really happen as we are always visable
    // even when minimized in dock.
    m_obscured = true;
    return m_obscured;
  }

  // check if we are minimized (to an icon in the Dock).
  if ([window isMiniaturized] == YES)
  {
    m_obscured = true;
    return m_obscured;
  }

  // check if we are showing on the active workspace.
  if ([window isOnActiveSpace] == NO)
  {
    m_obscured = true;
    return m_obscured;
  }

  // default to false before we start parsing though the windows.
  // if we are are obscured by any windows, then set true.
  m_obscured = false;
  static bool obscureLogged = false;

  CGWindowListOption opts;
  opts = kCGWindowListOptionOnScreenAboveWindow | kCGWindowListExcludeDesktopElements;
  CFArrayRef windowIDs =CGWindowListCreate(opts, (CGWindowID)[window windowNumber]);  

  if (!windowIDs)
    return m_obscured;

  CFArrayRef windowDescs = CGWindowListCreateDescriptionFromArray(windowIDs);
  if (!windowDescs)
  {
    CFRelease(windowIDs);
    return m_obscured;
  }

  CGRect bounds = NSRectToCGRect([window frame]);
  // kCGWindowBounds measures the origin as the top-left corner of the rectangle
  //  relative to the top-left corner of the screen.
  // NSWindow’s frame property measures the origin as the bottom-left corner
  //  of the rectangle relative to the bottom-left corner of the screen.
  // convert bounds from NSWindow to CGWindowBounds here.
  bounds.origin.y = [[window screen] frame].size.height - bounds.origin.y - bounds.size.height;

  std::vector<CRect> partialOverlaps;
  CRect ourBounds = CGRectToCRect(bounds);

  for (CFIndex idx=0; idx < CFArrayGetCount(windowDescs); idx++)
  {
    // walk the window list of windows that are above us and are not desktop elements
    CFDictionaryRef windowDictionary = (CFDictionaryRef)CFArrayGetValueAtIndex(windowDescs, idx);

    // skip the Dock window, it actually covers the entire screen.
    CFStringRef ownerName = (CFStringRef)CFDictionaryGetValue(windowDictionary, kCGWindowOwnerName);
    if (CFStringCompare(ownerName, CFSTR("Dock"), 0) == kCFCompareEqualTo)
      continue;

    // Ignore known brightness tools for dimming the screen. They claim to cover
    // the whole XBMC window and therefore would make the framerate limiter
    // kicking in. Unfortunatly even the alpha of these windows is 1.0 so
    // we have to check the ownerName.
    if (CFStringCompare(ownerName, CFSTR("Shades"), 0)            == kCFCompareEqualTo ||
        CFStringCompare(ownerName, CFSTR("SmartSaver"), 0)        == kCFCompareEqualTo ||
        CFStringCompare(ownerName, CFSTR("Brightness Slider"), 0) == kCFCompareEqualTo ||
        CFStringCompare(ownerName, CFSTR("Displaperture"), 0)     == kCFCompareEqualTo ||
        CFStringCompare(ownerName, CFSTR("Dreamweaver"), 0)       == kCFCompareEqualTo)
      continue;

    CFDictionaryRef rectDictionary = (CFDictionaryRef)CFDictionaryGetValue(windowDictionary, kCGWindowBounds);
    if (!rectDictionary)
      continue;

    CGRect windowBounds;
    if (CGRectMakeWithDictionaryRepresentation(rectDictionary, &windowBounds))
    {
      if (CGRectContainsRect(windowBounds, bounds))
      {
        // if the windowBounds completely encloses our bounds, we are obscured.
        if (!obscureLogged)
        {
          std::string appName;
          if (DarwinCFStringRefToUTF8String(ownerName, appName))
            CLog::Log(LOGDEBUG, "WinSystemOSX: Fullscreen window %s obscures XBMC!", appName.c_str());
          obscureLogged = true;
        }
        m_obscured = true;
        break;
      }

      // handle overlaping windows above us that combine
      // to obscure by collecting any partial overlaps,
      // then subtract them from our bounds and check
      // for any remaining area.
      CRect intersection = CGRectToCRect(windowBounds);
      intersection.Intersect(ourBounds);
      if (!intersection.IsEmpty())
        partialOverlaps.push_back(intersection);
    }
  }

  if (!m_obscured)
  {
    // if we are here we are not obscured by any fullscreen window - reset flag
    // for allowing the logmessage above to show again if this changes.
    if (obscureLogged)
      obscureLogged = false;
    std::vector<CRect> rects = ourBounds.SubtractRects(partialOverlaps);
    // they got us covered
    if (rects.size() == 0)
      m_obscured = true;
  }

  CFRelease(windowDescs);
  CFRelease(windowIDs);

  return m_obscured;
}

void CWinSystemOSX::NotifyAppFocusChange(bool bGaining)
{
  printf("CWinSystemOSX::NotifyAppFocusChange\n");
  NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];

  if (m_bFullScreen && bGaining)
  {
    // find the window
    NSOpenGLContext* context = [NSOpenGLContext currentContext];
    if (context)
    {
      NSView* view;

      view = [context view];
      if (view)
      {
        NSWindow* window;
        window = [view window];
        if (window)
        {
          // find the screenID
          NSDictionary* screenInfo = [[window screen] deviceDescription];
          NSNumber* screenID = [screenInfo objectForKey:@"NSScreenNumber"];
          if ((CGDirectDisplayID)[screenID longValue] == kCGDirectMainDisplay)
          {
            SetMenuBarVisible(false);
          }
          [window orderFront:nil];
        }
      }
    }
  }
  [pool release];
}

void CWinSystemOSX::ShowOSMouse(bool show)
{
  //SDL_ShowCursor(show ? 1 : 0);
}

bool CWinSystemOSX::Minimize()
{
  NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];

  [[NSApplication sharedApplication] miniaturizeAll:nil];

  [pool release];
  return true;
}

bool CWinSystemOSX::Restore()
{
  NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];

  [[NSApplication sharedApplication] unhide:nil];

  [pool release];
  return true;
}

bool CWinSystemOSX::Hide()
{
  NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];

  [[NSApplication sharedApplication] hide:nil];

  [pool release];
  return true;
}

void CWinSystemOSX::OnMove(int x, int y)
{
  Cocoa_CVDisplayLinkUpdate();
}

void CWinSystemOSX::EnableSystemScreenSaver(bool bEnable)
{
  // see Technical Q&A QA1340
  static IOPMAssertionID assertionID = 0;

  if (!bEnable)
  {
    if (assertionID == 0)
    {
      CFStringRef reasonForActivity= CFSTR("XBMC requested disable system screen saver");
      IOPMAssertionCreateWithName(kIOPMAssertionTypeNoDisplaySleep,
        kIOPMAssertionLevelOn, reasonForActivity, &assertionID);
    }
    UpdateSystemActivity(UsrActivity);
  }
  else if (assertionID != 0)
  {
    IOPMAssertionRelease(assertionID);
    assertionID = 0;
  }

  m_use_system_screensaver = bEnable;
}

bool CWinSystemOSX::IsSystemScreenSaverEnabled()
{
  return m_use_system_screensaver;
}

void CWinSystemOSX::ResetOSScreensaver()
{
  // allow os screensaver only if we are fullscreen
  EnableSystemScreenSaver(!m_bFullScreen);
}

bool CWinSystemOSX::EnableFrameLimiter()
{
  return IsObscured();
}

void CWinSystemOSX::EnableTextInput(bool bEnable)
{
  if (bEnable)
    StartTextInput();
  else
    StopTextInput();
}

OSXTextInputResponder *g_textInputResponder = nil;

bool CWinSystemOSX::IsTextInputEnabled()
{
  return g_textInputResponder != nil && [[g_textInputResponder superview] isEqual: [[NSApp keyWindow] contentView]];
}

void CWinSystemOSX::StartTextInput()
{
  NSView *parentView = [[NSApp keyWindow] contentView];

  /* We only keep one field editor per process, since only the front most
   * window can receive text input events, so it make no sense to keep more
   * than one copy. When we switched to another window and requesting for
   * text input, simply remove the field editor from its superview then add
   * it to the front most window's content view */
  if (!g_textInputResponder) {
    g_textInputResponder =
    [[OSXTextInputResponder alloc] initWithFrame: NSMakeRect(0.0, 0.0, 0.0, 0.0)];
  }

  if (![[g_textInputResponder superview] isEqual: parentView])
  {
//    DLOG(@"add fieldEdit to window contentView");
    [g_textInputResponder removeFromSuperview];
    [parentView addSubview: g_textInputResponder];
    [[NSApp keyWindow] makeFirstResponder: g_textInputResponder];
  }
}
void CWinSystemOSX::StopTextInput()
{
  if (g_textInputResponder) {
    [g_textInputResponder removeFromSuperview];
    [g_textInputResponder release];
    g_textInputResponder = nil;
  }
}

void CWinSystemOSX::Register(IDispResource *resource)
{
  CSingleLock lock(m_resourceSection);
  m_resources.push_back(resource);
}

void CWinSystemOSX::Unregister(IDispResource* resource)
{
  CSingleLock lock(m_resourceSection);
  std::vector<IDispResource*>::iterator i = find(m_resources.begin(), m_resources.end(), resource);
  if (i != m_resources.end())
    m_resources.erase(i);
}

bool CWinSystemOSX::Show(bool raise)
{
  NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];

  if (raise)
  {
    [[NSApplication sharedApplication] unhide:nil];
    [[NSApplication sharedApplication] activateIgnoringOtherApps: YES];
    [[NSApplication sharedApplication] arrangeInFront:nil];
  }
  else
  {
    [[NSApplication sharedApplication] unhideWithoutActivation];
  }

  [pool release];
  return true;
}

int CWinSystemOSX::GetNumScreens()
{
  int numDisplays = [[NSScreen screens] count];
  return(numDisplays);
}

void CWinSystemOSX::CheckDisplayChanging(u_int32_t flags)
{
  if (flags)
  {
    CSingleLock lock(m_resourceSection);
    // tell any shared resources
    if (flags & kCGDisplayBeginConfigurationFlag)
    {
      CLog::Log(LOGDEBUG, "CWinSystemOSX::CheckDisplayChanging:OnLostDevice");
      for (std::vector<IDispResource *>::iterator i = m_resources.begin(); i != m_resources.end(); i++)
        (*i)->OnLostDevice();
    }
    if (flags & kCGDisplaySetModeFlag)
    {
      CLog::Log(LOGDEBUG, "CWinSystemOSX::CheckDisplayChanging:OnResetDevice");
      for (std::vector<IDispResource *>::iterator i = m_resources.begin(); i != m_resources.end(); i++)
        (*i)->OnResetDevice();
    }
  }
}

void* CWinSystemOSX::GetCGLContextObj()
{
  return [(NSOpenGLContext*)m_glContext CGLContextObj];
}

CWinEventsOSX* CWinSystemOSX::GetEvents()
{
  return m_osx_events;
}

std::string CWinSystemOSX::GetClipboardText(void)
{
  std::string utf8_text;

  const char *szStr = Cocoa_Paste();
  if (szStr)
    utf8_text = szStr;

  return utf8_text;
}

float CWinSystemOSX::FlipY(float y)
{
  // TODO hook height and width up to resize events of window and cache them as member
  if (m_windowData && m_windowData->nswindow)
  {
    NSWindow *win = (NSWindow *)m_windowData->nswindow;
    NSRect frame = [[win contentView] frame];
    y = frame.size.height - y;
  }
  return y;
}

#endif
