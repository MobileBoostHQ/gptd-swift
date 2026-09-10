#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

/// Error domain for failures reported by ``GPTDPerformMultiTouch``.
FOUNDATION_EXPORT NSString * const GPTDMultiTouchErrorDomain;

/// Whether the XCTest event synthesizer this file drives is present in the running runtime.
///
/// XCTest exposes no public way to move two fingers along paths of the caller's choosing:
/// `-[XCUIElement pinchWithScale:velocity:]` pinches about the centre of an element, which is
/// exactly the gesture that cannot zoom content the element does not centre on. The synthesizer
/// underneath it can, and is what Appium's WebDriverAgent has driven for years, so the SDK reaches
/// for it through the runtime rather than linking it. Being private, it may be absent or renamed in
/// a future Xcode, and callers are expected to keep a fallback for when this returns NO.
FOUNDATION_EXPORT BOOL GPTDMultiTouchAvailable(void);

/// Injects several touch paths as ONE gesture, every finger moving at the same time.
///
/// Running the paths one after another would perform two drags rather than a pinch: real input, the
/// wrong gesture, and nothing anywhere to say so. They are dispatched as a single synthesized event
/// so the app under test receives them the way it receives a person's fingers.
///
/// @param paths one array of NSValue-wrapped CGPoints per finger, in screen points, already sampled
///   onto the shared clock given by @c offsets. Every path must hold exactly as many points as
///   @c offsets, so that sample @c i of each finger happens at the same moment.
/// @param offsets seconds since the start of the gesture, one per sample, ascending from 0.
/// @param interfaceOrientation UIInterfaceOrientation raw value the event is recorded in.
/// @param timeout seconds to wait for the runner to acknowledge the gesture.
/// @param error set when the gesture could not be built, dispatched, or acknowledged in time.
/// @return YES if the event was dispatched and acknowledged.
///
/// @note Blocks the calling thread until the gesture completes, so call it off the main thread:
///   the acknowledgement may be delivered there.
FOUNDATION_EXPORT BOOL GPTDPerformMultiTouch(NSArray<NSArray<NSValue *> *> *paths,
                                             NSArray<NSNumber *> *offsets,
                                             NSInteger interfaceOrientation,
                                             NSTimeInterval timeout,
                                             NSError * _Nullable * _Nullable error);

NS_ASSUME_NONNULL_END
