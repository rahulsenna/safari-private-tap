#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <CoreGraphics/CoreGraphics.h>

// ==============================================================================
// 1. REVERSE-ENGINEERED MULTITOUCH HEADERS
// ==============================================================================
typedef struct { float x, y; } MTPoint;
typedef struct { float x, y; } MTVector;

typedef struct
{
  int frame;
  double timestamp;
  int identifier, state, foo3, foo4;
  MTPoint normalizedPosition;
  float size;
  int zero1, angle, majorAxis, minorAxis;
  MTVector velocity;
  float zDensity;
  int zero2;
} MTContact;

typedef void* MTDeviceRef;
typedef void (*MTContactCallbackFunction)(MTDeviceRef, MTContact*, int, double, int);

MTDeviceRef MTDeviceCreateDefault(void);
void MTRegisterContactFrameCallback(MTDeviceRef, MTContactCallbackFunction);
void MTDeviceStart(MTDeviceRef, int);

// Global state for Safari tracking
static BOOL isSafariActive = NO;

// ==============================================================================
// 2. CORE GRAPHICS EVENT SYNTHESIS
// ==============================================================================
void triggerSafariPrivateWindow()
{
  CGEventSourceRef source = CGEventSourceCreate(kCGEventSourceStateHIDSystemState);
  CGEventRef mouseEvent = CGEventCreate(source);
  CGPoint cursorLoc = CGEventGetLocation(mouseEvent);
  CFRelease(mouseEvent);

  // 1. Right Click (Opens Context Menu)
  CGEventRef rightDown = CGEventCreateMouseEvent(source, kCGEventRightMouseDown, cursorLoc, kCGMouseButtonRight);
  CGEventRef rightUp = CGEventCreateMouseEvent(source, kCGEventRightMouseUp, cursorLoc, kCGMouseButtonRight);
  CGEventPost(kCGHIDEventTap, rightDown);
  CGEventPost(kCGHIDEventTap, rightUp);
  CFRelease(rightDown);
  CFRelease(rightUp);

  [NSThread sleepForTimeInterval : 0.05] ;

  // 2. Down Arrow (Twice)
  CGEventRef downArrowDown = CGEventCreateKeyboardEvent(source, 125, true);
  CGEventRef downArrowUp = CGEventCreateKeyboardEvent(source, 125, false);

  CGEventPost(kCGHIDEventTap, downArrowDown);
  CGEventPost(kCGHIDEventTap, downArrowUp);
  CGEventPost(kCGHIDEventTap, downArrowDown);
  CGEventPost(kCGHIDEventTap, downArrowUp);

  CFRelease(downArrowDown);
  CFRelease(downArrowUp);

  // 3. Hold Option, Press Enter, Release Option
  CGEventRef optDown = CGEventCreateKeyboardEvent(source, 58, true);
  CGEventRef optUp = CGEventCreateKeyboardEvent(source, 58, false);
  CGEventRef enterDown = CGEventCreateKeyboardEvent(source, 36, true);
  CGEventRef enterUp = CGEventCreateKeyboardEvent(source, 36, false);

  CGEventSetFlags(enterDown, kCGEventFlagMaskAlternate);

  CGEventPost(kCGHIDEventTap, optDown);
  [NSThread sleepForTimeInterval : 0.15] ;        // Delay for UI swap
  CGEventPost(kCGHIDEventTap, enterDown);
  CGEventPost(kCGHIDEventTap, enterUp);
  CGEventPost(kCGHIDEventTap, optUp);

  CFRelease(enterDown);
  CFRelease(enterUp);
  CFRelease(optDown);
  CFRelease(optUp);
  CFRelease(source);
}

// ==============================================================================
// 3. PURE C CALLBACK FUNCTION (STRICT TAP)
// ==============================================================================
static double initialTapTime = 0;
static double lastFireTime = 0;
static double liftStartTime = 0;
static BOOL isTrackingTap = NO;
static BOOL didMoveTooFar = NO;
static float initialCentroidX = 0;
static float initialCentroidY = 0;

void trackpadCallback(MTDeviceRef device, MTContact* contacts, int numContacts, double timestamp, int frame)
{

  // ZERO OVERHEAD EARLY EXIT: If Safari isn't the front window, ignore trackpad completely
  if (!isSafariActive) return;

  if (numContacts == 3)
  {
    liftStartTime = 0; // Reset the lift timer
    float sumX = 0, sumY = 0;
    for (int i = 0; i < 3; i++)
    {
      sumX += contacts[i].normalizedPosition.x;
      sumY += contacts[i].normalizedPosition.y;
    }
    float centroidX = sumX / 3.0f;
    float centroidY = sumY / 3.0f;

    if (!isTrackingTap)
    {
      isTrackingTap = YES;
      didMoveTooFar = NO;
      initialTapTime = timestamp;
      initialCentroidX = centroidX;
      initialCentroidY = centroidY;
    } else
    {
      float dx = fabs(centroidX - initialCentroidX);
      float dy = fabs(centroidY - initialCentroidY);
      if (dx > 0.02f || dy > 0.02f)
      {
        didMoveTooFar = YES;
      }
    }
  }
  // STATE 2: THE CASCADE (1 or 2 fingers)
  else if (numContacts == 1 || numContacts == 2)
  {
    if (isTrackingTap)
    {
      // Start the timer the moment the first finger lifts
      if (liftStartTime == 0) liftStartTime = timestamp;

      // If we linger in this state for more than 100ms, it's a sustained 
      // scroll, not a quick lift-off. Kill the tap.
      if (timestamp - liftStartTime > 0.1)
      {
        isTrackingTap = NO;
      }
    }
  }
  // STATE 3: CLEAN LIFT (0 FINGERS)
  else if (numContacts == 0)
  {
    if (isTrackingTap)
    {
      double tapDuration = timestamp - initialTapTime;
      if (!didMoveTooFar && tapDuration < 0.4 && (timestamp - lastFireTime > 0.5))
      {
        lastFireTime = timestamp;
        dispatch_async(dispatch_get_main_queue(), ^ {
            triggerSafariPrivateWindow();
          });
      }
      isTrackingTap = NO;
    }
    liftStartTime = 0; // Clean up
  }
  // STATE 4: KILL SWITCH (4+ fingers / Palms)
  else if (numContacts > 3)
  {
    isTrackingTap = NO;
    liftStartTime = 0;
  }
}
// ==============================================================================
// 4. MAIN LOOP WITH WORKSPACE OBSERVER
// ==============================================================================
int main(int argc, const char* argv[])
{
  @autoreleasepool
  {
    // 1. Initial State Check
    NSString * frontApp = [[[NSWorkspace sharedWorkspace]frontmostApplication] bundleIdentifier];
    isSafariActive = [frontApp isEqualToString : @"com.apple.Safari"];

    // 2. Setup Background OS Observer
    [[[NSWorkspace sharedWorkspace]notificationCenter] addObserverForName:NSWorkspaceDidActivateApplicationNotification object : nil queue : [NSOperationQueue mainQueue] usingBlock : ^ (NSNotification * note)
    {
      NSRunningApplication* app = note.userInfo[NSWorkspaceApplicationKey];
      isSafariActive = [app.bundleIdentifier isEqualToString : @"com.apple.Safari"];
    }];

    // 3. Initialize Trackpad Device
    MTDeviceRef dev = MTDeviceCreateDefault();
    if (!dev) return 1;

    MTRegisterContactFrameCallback(dev, trackpadCallback);
    MTDeviceStart(dev, 0);

    // Keep process alive processing notifications and events
    [[NSRunLoop currentRunLoop]run];
  }
  return 0;
}