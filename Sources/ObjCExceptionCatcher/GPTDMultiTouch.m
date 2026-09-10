#import "GPTDMultiTouch.h"
#import <objc/runtime.h>

NSString * const GPTDMultiTouchErrorDomain = @"io.mobileboost.gptdriver.multitouch";

static NSString * const kEventName = @"GPTDriver multi-touch";

#pragma mark - Private XCTest surface

// Declared, never linked. Every class below is reached through NSClassFromString, so nothing here
// references a private symbol at link time: an Xcode that renames or drops one of them leaves the
// SDK with a working fallback instead of a test bundle that will not build.
//
// Declaring the methods rather than casting objc_msgSend keeps ARC in charge of the objects, and
// keeps the call sites readable.

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

@interface XCTRunnerDaemonSession : NSObject
+ (instancetype)sharedSession;
- (void)synthesizeEvent:(id)event completion:(void (^)(NSError * _Nullable))completion;
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

/// One finger's path: down at the first sample, a move at every sample after it, then up.
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

/// The record every finger is added to. Xcode has spelled its initialiser both ways over the years,
/// so both are tried before giving up.
static XCSynthesizedEventRecord *GPTDBuildEventRecord(NSInteger interfaceOrientation) {
    Class recordClass = NSClassFromString(@"XCSynthesizedEventRecord");
    if (recordClass == Nil) {
        return nil;
    }

    // Asked of the class, not of a half-built instance, so alloc and init stay in one expression.
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
                           NSArray<NSNumber *> *offsets,
                           NSInteger interfaceOrientation,
                           NSTimeInterval timeout,
                           NSError * _Nullable * _Nullable error) {
    if (paths.count < 2) {
        if (error) { *error = GPTDError(1, @"A multi-touch gesture needs at least two paths"); }
        return NO;
    }

    if (offsets.count < 2) {
        if (error) { *error = GPTDError(2, @"A multi-touch gesture needs at least two samples"); }
        return NO;
    }

    for (NSArray<NSValue *> *points in paths) {
        if (points.count != offsets.count) {
            if (error) {
                *error = GPTDError(3, @"Every path must carry one point per sample offset");
            }
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

    for (NSArray<NSValue *> *points in paths) {
        XCPointerEventPath *path = GPTDBuildPointerEventPath(points, offsets);
        if (path == nil) {
            if (error) { *error = GPTDError(6, @"Could not create a pointer event path"); }
            return NO;
        }
        [record addPointerEventPath:path];
    }

    Class sessionClass = NSClassFromString(@"XCTRunnerDaemonSession");
    XCTRunnerDaemonSession *session = [sessionClass sharedSession];
    if (session == nil) {
        if (error) { *error = GPTDError(7, @"The XCTest runner session is unavailable"); }
        return NO;
    }

    __block NSError *dispatchError = nil;
    dispatch_semaphore_t finished = dispatch_semaphore_create(0);

    @try {
        [session synthesizeEvent:record completion:^(NSError * _Nullable completionError) {
            dispatchError = completionError;
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
