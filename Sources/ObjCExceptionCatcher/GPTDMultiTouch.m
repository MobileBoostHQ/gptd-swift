#import "GPTDMultiTouch.h"
#import <UIKit/UIKit.h> // NSValue.CGPointValue
#import <objc/runtime.h>

NSString * const GPTDMultiTouchErrorDomain = @"io.mobileboost.gptdriver.multitouch";

static NSString * const kEventName = @"GPTDriver multi-touch";

#pragma mark - Private XCTest API

// Declared here and resolved with NSClassFromString, so nothing private is referenced
// at link time. If Xcode renames one of these we lose the feature, not the build.

@interface XCPointerEventPath : NSObject
- (instancetype)initForTouchAtPoint:(CGPoint)point offset:(NSTimeInterval)offset;
- (void)moveToPoint:(CGPoint)point atOffset:(NSTimeInterval)offset;
- (void)liftUpAtOffset:(NSTimeInterval)offset;
@end

@interface XCSynthesizedEventRecord : NSObject
- (instancetype)initWithName:(NSString *)name interfaceOrientation:(NSInteger)interfaceOrientation;
- (instancetype)initWithName:(NSString *)name;
- (void)addPointerEventPath:(XCPointerEventPath *)path;
@end

// Implemented by XCUIDevice's eventSynthesizer, which is the XCTRunnerDaemonSession.
// The completion takes (BOOL, NSError *). Some class-dumped headers declare a single
// NSError argument; that receives the BOOL as a pointer and crashes the runner.
@protocol GPTDEventSynthesizing <NSObject>
- (void)synthesizeEvent:(id)event completion:(void (^)(BOOL succeeded, NSError * _Nullable error))completion;
@end

@interface XCTRunnerDaemonSession : NSObject
+ (instancetype)sharedSession;
@end

@protocol GPTDDeviceSynthesizerSource <NSObject>
+ (id)sharedDevice;
- (id)eventSynthesizer;
@end

#pragma mark - Helpers

static NSError *GPTDError(NSInteger code, NSString *description) {
    return [NSError errorWithDomain:GPTDMultiTouchErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: description}];
}

BOOL GPTDMultiTouchAvailable(void) {
    Class pathClass = NSClassFromString(@"XCPointerEventPath");
    Class recordClass = NSClassFromString(@"XCSynthesizedEventRecord");
    Class sessionClass = NSClassFromString(@"XCTRunnerDaemonSession");
    if (pathClass == Nil || recordClass == Nil || sessionClass == Nil) {
        return NO;
    }

    if (![pathClass instancesRespondToSelector:@selector(initForTouchAtPoint:offset:)] ||
        ![pathClass instancesRespondToSelector:@selector(moveToPoint:atOffset:)] ||
        ![pathClass instancesRespondToSelector:@selector(liftUpAtOffset:)]) {
        return NO;
    }

    if (![recordClass instancesRespondToSelector:@selector(addPointerEventPath:)]) {
        return NO;
    }

    return [sessionClass respondsToSelector:@selector(sharedSession)] &&
           [sessionClass instancesRespondToSelector:@selector(synthesizeEvent:completion:)];
}

// Same lookup as WebDriverAgent: XCUIDevice's synthesizer, else the daemon session.
static id<GPTDEventSynthesizing> GPTDEventSynthesizer(void) {
    Class<GPTDDeviceSynthesizerSource> deviceClass = NSClassFromString(@"XCUIDevice");
    if (deviceClass != Nil && [(Class)deviceClass respondsToSelector:@selector(sharedDevice)]) {
        id device = [deviceClass sharedDevice];
        if ([device respondsToSelector:@selector(eventSynthesizer)]) {
            id synthesizer = [(id<GPTDDeviceSynthesizerSource>)device eventSynthesizer];
            if ([synthesizer respondsToSelector:@selector(synthesizeEvent:completion:)]) {
                return synthesizer;
            }
        }
    }

    Class sessionClass = NSClassFromString(@"XCTRunnerDaemonSession");
    id session = [sessionClass sharedSession];
    return [session respondsToSelector:@selector(synthesizeEvent:completion:)] ? session : nil;
}

// Touch down at the first point, move through the rest, lift at the last.
static XCPointerEventPath *GPTDBuildPointerEventPath(NSArray<NSValue *> *points,
                                                     NSArray<NSNumber *> *offsets) {
    Class pathClass = NSClassFromString(@"XCPointerEventPath");
    if (pathClass == Nil || points.count == 0 || points.count != offsets.count) {
        return nil;
    }

    XCPointerEventPath *path = [[pathClass alloc] initForTouchAtPoint:points.firstObject.CGPointValue
                                                               offset:offsets.firstObject.doubleValue];
    if (path == nil) {
        return nil;
    }

    for (NSUInteger index = 1; index < points.count; index++) {
        [path moveToPoint:points[index].CGPointValue atOffset:offsets[index].doubleValue];
    }
    [path liftUpAtOffset:offsets.lastObject.doubleValue];

    return path;
}

// The initialiser has had both spellings across Xcode versions.
static XCSynthesizedEventRecord *GPTDBuildEventRecord(NSInteger interfaceOrientation) {
    Class recordClass = NSClassFromString(@"XCSynthesizedEventRecord");
    if (recordClass == Nil) {
        return nil;
    }

    if ([recordClass instancesRespondToSelector:@selector(initWithName:interfaceOrientation:)]) {
        return [[recordClass alloc] initWithName:kEventName
                            interfaceOrientation:interfaceOrientation];
    }
    if ([recordClass instancesRespondToSelector:@selector(initWithName:)]) {
        return [[recordClass alloc] initWithName:kEventName];
    }
    return nil;
}

#pragma mark - Public entry point

BOOL GPTDPerformMultiTouch(NSArray<NSArray<NSValue *> *> *paths,
                           NSArray<NSArray<NSNumber *> *> *offsets,
                           NSInteger interfaceOrientation,
                           NSTimeInterval timeout,
                           NSError * _Nullable * _Nullable error) {
    if (paths.count < 2) {
        if (error) { *error = GPTDError(1, @"A multi-touch gesture needs at least two paths"); }
        return NO;
    }

    if (offsets.count != paths.count) {
        if (error) { *error = GPTDError(2, @"Every path needs its own list of offsets"); }
        return NO;
    }

    for (NSUInteger index = 0; index < paths.count; index++) {
        if (paths[index].count < 2) {
            if (error) { *error = GPTDError(3, @"Every path needs at least a start and an end"); }
            return NO;
        }
        if (paths[index].count != offsets[index].count) {
            if (error) { *error = GPTDError(3, @"Every path must carry one offset per waypoint"); }
            return NO;
        }
    }

    if (!GPTDMultiTouchAvailable()) {
        if (error) {
            *error = GPTDError(4, @"This XCTest runtime does not expose the event synthesizer");
        }
        return NO;
    }

    XCSynthesizedEventRecord *record = GPTDBuildEventRecord(interfaceOrientation);
    if (record == nil) {
        if (error) { *error = GPTDError(5, @"Could not create the synthesized event record"); }
        return NO;
    }

    for (NSUInteger index = 0; index < paths.count; index++) {
        XCPointerEventPath *path = GPTDBuildPointerEventPath(paths[index], offsets[index]);
        if (path == nil) {
            if (error) { *error = GPTDError(6, @"Could not create a pointer event path"); }
            return NO;
        }
        [record addPointerEventPath:path];
    }

    id<GPTDEventSynthesizing> synthesizer = GPTDEventSynthesizer();
    if (synthesizer == nil) {
        if (error) { *error = GPTDError(7, @"The XCTest event synthesizer is unavailable"); }
        return NO;
    }

    __block NSError *dispatchError = nil;
    dispatch_semaphore_t finished = dispatch_semaphore_create(0);

    @try {
        [synthesizer synthesizeEvent:record completion:^(BOOL succeeded, NSError * _Nullable completionError) {
            if (!succeeded && completionError == nil) {
                dispatchError = GPTDError(10, @"The runner reported failure without an error");
            } else {
                dispatchError = completionError;
            }
            dispatch_semaphore_signal(finished);
        }];
    } @catch (NSException *exception) {
        if (error) {
            *error = GPTDError(8, [NSString stringWithFormat:@"Dispatching the gesture threw %@: %@",
                                                             exception.name, exception.reason]);
        }
        return NO;
    }

    dispatch_time_t deadline = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(timeout * NSEC_PER_SEC));
    if (dispatch_semaphore_wait(finished, deadline) != 0) {
        if (error) {
            *error = GPTDError(9, @"Timed out waiting for the gesture to be acknowledged");
        }
        return NO;
    }

    if (dispatchError != nil) {
        if (error) { *error = dispatchError; }
        return NO;
    }

    return YES;
}
