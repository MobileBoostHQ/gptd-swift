#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString * const GPTDMultiTouchErrorDomain;

/// Whether the private XCTest event synthesizer is present in this runtime.
///
/// XCTest has no public API for moving several fingers along arbitrary paths:
/// `-[XCUIElement pinchWithScale:velocity:]` always pinches about the element's
/// centre. The synthesizer underneath it (the one WebDriverAgent uses) is reached
/// through the runtime, so it may be missing on a future Xcode. Keep a fallback.
FOUNDATION_EXPORT BOOL GPTDMultiTouchAvailable(void);

/// Injects one touch path per finger as a single gesture.
///
/// Each path is a list of waypoints in screen points. The synthesizer interpolates
/// between them and reaches waypoint `i` at `offsets[i]` seconds after the gesture
/// starts, so a pinch is two fingers with two waypoints each. Do not pre-sample paths:
/// events closer together than about a frame make the synthesizer replay the whole
/// path as one jump (Xcode 26.2: 30ms spacing works, 15ms collapses).
///
/// Blocks until the runner acknowledges the gesture. Call it off the main thread,
/// where the acknowledgement may be delivered.
///
/// @param paths    one array of NSValue-wrapped CGPoints per finger, at least two each
/// @param offsets  one array per finger, seconds from gesture start, ascending from 0
/// @param interfaceOrientation  UIInterfaceOrientation raw value
/// @param timeout  seconds to wait for the acknowledgement
FOUNDATION_EXPORT BOOL GPTDPerformMultiTouch(NSArray<NSArray<NSValue *> *> *paths,
                                             NSArray<NSArray<NSNumber *> *> *offsets,
                                             NSInteger interfaceOrientation,
                                             NSTimeInterval timeout,
                                             NSError * _Nullable * _Nullable error);

NS_ASSUME_NONNULL_END
