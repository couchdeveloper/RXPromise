//
//  RXPromise.m
//
//  If not otherwise noted, the content in this package is licensed
//  under the following license:
//
//  Copyright 2013 Andreas Grosam
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.


#if (!__has_feature(objc_arc))
#error this file requires arc enabled
#endif

#import "RXPromise.h"
#include <dispatch/dispatch.h>
//#define DEBUG_LOG_MIN 4   //enable this in order to log verbosely
#import "utility/DLog.h"
#include <assert.h>
#include <stdio.h>



#if TARGET_OS_IPHONE
// Compiling for iOS
#if __IPHONE_OS_VERSION_MIN_REQUIRED >= 60000
// >= iOS 6.0
#define RX_DISPATCH_RELEASE(__object) do {} while(0)
#define RX_DISPATCH_RETAIN(__object) do {} while(0)
#define RX_DISPATCH_BRIDGE_VOID_CAST(__object) do { (__bridge void*)__object; } while(0)
#else
// <= iOS 5.x
#define RX_DISPATCH_RELEASE(__object) do {dispatch_release(__object);} while(0)
#define RX_DISPATCH_RETAIN(__object) do { dispatch_retain(__object); } while(0)
#define RX_DISPATCH_BRIDGE_VOID_CAST(__object) __object
#endif
#elif TARGET_OS_MAC
// Compiling for Mac OS X
#if MAC_OS_X_VERSION_MIN_REQUIRED >= 1080
// >= Mac OS X 10.8
#define RX_DISPATCH_RELEASE(__object) do {} while(0)
#define RX_DISPATCH_RETAIN(__object) do {} while(0)
#define RX_DISPATCH_BRIDGE_VOID_CAST(__object) do { (__bridge void*)__object; } while(0)
#else
// <= Mac OS X 10.7.x
#define RX_DISPATCH_RELEASE(__object) do {dispatch_release(__object);} while(0)
#define RX_DISPATCH_RETAIN(__object) do { dispatch_retain(__object); } while(0)
#define RX_DISPATCH_BRIDGE_VOID_CAST(__object) __object
#endif
#endif


/**
 See <http://promises-aplus.github.io/promises-spec/>  for specification.
 */


@implementation NSObject (RXIntrospection)
- (BOOL) isNSBlock {
    return [self isKindOfClass:NSClassFromString(@"NSBlock")];
}
@end


@interface NSError (RXResolver)
- (void) rxp_resolvePromise:(RXPromise*)promise;
@end

@interface NSObject (RXResolver)
- (void) rxp_resolvePromise:(RXPromise*)promise;
@end

@interface RXPromise (RXResolver)
- (void) rxp_resolvePromise:(RXPromise*)promise;
@end



@interface RXPromise ()
@property (nonatomic, readwrite) BOOL isFulfilled;
@property (nonatomic, readwrite) BOOL isRejected;
@property (nonatomic, readwrite) BOOL isCancelled;
@property (nonatomic) NSMutableArray* progressHandlers;
@property (nonatomic) NSMutableArray* promises; // children - or "returned promises" (required only when implementing cancel)
@end




@implementation RXPromise
{
    dispatch_once_t         _once_result;
    id                      _result;
    dispatch_queue_t        _handler_queue;     // a serial queue, uses target queue: s_handler_queue_parent
    NSMutableArray*         _progressHandlers;
    NSMutableArray*         _promises;
    BOOL                    _isFulfilled;
    BOOL                    _isRejected;
    BOOL                    _isCancelled;
}
@synthesize progressHandlers = _progressHandlers;
@synthesize promises = _promises;


static dispatch_queue_t s_sync_queue;
static dispatch_queue_t s_handler_queue_parent;


// Designated Initializer
- (id)init
{
    static dispatch_once_t onceSharedSyncQueue;
    dispatch_once(&onceSharedSyncQueue, ^{
        s_sync_queue = dispatch_queue_create("s_sync_queue", NULL);
        dispatch_queue_set_specific(s_sync_queue, "sync_queue.id", RX_DISPATCH_BRIDGE_VOID_CAST(s_sync_queue), NULL);
    });
    DLogInfo(@"init: %p", (__bridge void*)self);
    return [super init];
}

- (void) dealloc {
    DLogInfo(@"dealloc: %p", (__bridge void*)self);
    if (_handler_queue) {
        DLogWarn(@"handler queue has not been resumed - probably the promise hasn't been signaled");
        dispatch_resume(_handler_queue);
        RX_DISPATCH_RELEASE(_handler_queue);
    }
}

#pragma mark -

// property then
- (then_t) then {
    return ^(completionHandler_t completionHandler, errorHandler_t errorHandler) {
        return [self then:completionHandler errorHandler:errorHandler progressHandler:NULL];
    };
}

- (NSMutableArray*) progressHandlers
{
    assert(dispatch_get_specific("sync_queue.id") == RX_DISPATCH_BRIDGE_VOID_CAST(s_sync_queue));
    if (_progressHandlers == nil) {
        _progressHandlers = [[NSMutableArray alloc] initWithCapacity:1];
    }
    return _progressHandlers;
}

- (NSMutableArray*) promises
{
    assert(dispatch_get_specific("sync_queue.id") == RX_DISPATCH_BRIDGE_VOID_CAST(s_sync_queue));
    if (_promises == nil) {
        _promises = [[NSMutableArray alloc] initWithCapacity:1];
    }
    return _promises;
}


- (BOOL) isPending {
    if (dispatch_get_specific("sync_queue.id") == RX_DISPATCH_BRIDGE_VOID_CAST(s_sync_queue)) {
        return !(_isFulfilled || _isRejected || _isCancelled);
    }
    else {
        __block BOOL result;
        dispatch_sync(s_sync_queue, ^{
            result = !(_isFulfilled || _isRejected || _isCancelled) ;
        });
        return result;
    }
}

- (BOOL) isFulfilled {
    if (dispatch_get_specific("sync_queue.id") == RX_DISPATCH_BRIDGE_VOID_CAST(s_sync_queue)) {
        return _isFulfilled;
    }
    else {
        __block BOOL result;
        dispatch_sync(s_sync_queue, ^{ result = _isFulfilled; });
        return result;
    }
}

- (BOOL) isRejected {
    if (dispatch_get_specific("sync_queue.id") == RX_DISPATCH_BRIDGE_VOID_CAST(s_sync_queue)) {
        return _isRejected;
    }
    else {
        __block BOOL result;
        dispatch_sync(s_sync_queue, ^{ result = _isRejected; });
        return result;
    }
}

- (BOOL) isCancelled {
    if (dispatch_get_specific("sync_queue.id") == RX_DISPATCH_BRIDGE_VOID_CAST(s_sync_queue)) {
        return _isCancelled;
    }
    else {
        __block BOOL result;
        dispatch_sync(s_sync_queue, ^{ result = _isCancelled; });
        return result;
    }
}


- (dispatch_queue_t) handlerQueue
{
    assert(dispatch_get_specific("sync_queue.id") == RX_DISPATCH_BRIDGE_VOID_CAST(s_sync_queue));
    if (!_handler_queue) {
        char buffer[64];
        snprintf(buffer, sizeof(buffer),"RXPromise_handler_queue-%p", (__bridge void*)self);
        _handler_queue = dispatch_queue_create(buffer, DISPATCH_QUEUE_SERIAL);
        assert(_handler_queue);
        dispatch_set_target_queue(_handler_queue, s_handler_queue_parent);
        dispatch_suspend(_handler_queue);
    }
    return _handler_queue;
}

#pragma mark - Resolver

- (void) fulfillWithValue:(id)result {
    assert(![result isKindOfClass:[NSError class]]);
    dispatch_once(&_once_result, ^{
        assert(s_sync_queue);
        // dispatch a fulfill signal on the sync queue:
        dispatch_async(s_sync_queue, ^{
            DLogInfo(@"self: %@, exec on sync_queue: `fulfillWithValue:`%@", self, result);
            _result = result;
            self.isFulfilled = YES;
            if (_handler_queue) {
                dispatch_resume(_handler_queue);
                RX_DISPATCH_RELEASE(_handler_queue);
                _handler_queue = NULL;
            }
        });
    });
}

- (void) rejectWithReason:(id)reason {
    if (![reason isKindOfClass:[NSError class]]) {
        reason = [[NSError alloc] initWithDomain:@"RXPromise" code:-1000 userInfo:@{@"reason": reason}];
    }
    dispatch_once(&_once_result, ^{
        assert(s_sync_queue);
        // dispatch a rejected signal on the sync queue:
        dispatch_async(s_sync_queue, ^{
            DLogInfo(@"self: %@, exec on sync_queue: `rejectWithReason:`%@", self, reason);
            _result = reason;
            self.isRejected = YES;
            if (_handler_queue) {
                dispatch_resume(_handler_queue);
                RX_DISPATCH_RELEASE(_handler_queue);
                _handler_queue = NULL;
            }
        });
    });
}

- (void) cancelWithReason:(id)reason {
    if (![reason isKindOfClass:[NSError class]]) {
        reason = [[NSError alloc] initWithDomain:@"RXPromise" code:-1 userInfo:@{@"reason": reason}];
    }
    dispatch_once(&_once_result, ^{
        assert(s_sync_queue);
        // dispatch a cancel signal on the sync queue:
        dispatch_async(s_sync_queue, ^{
            DLogInfo(@"self: %@, exec on sync_queue: `cancelWithReason:`%@", self, reason);
            _result = reason;
            self.isCancelled = YES;
            self.isRejected = YES;
            if (_handler_queue) {
                dispatch_resume(_handler_queue);
                RX_DISPATCH_RELEASE(_handler_queue);
                _handler_queue = NULL;
            }
        });
    });
    dispatch_async(s_sync_queue, ^{
        if (!_isCancelled) {
            // We cancelled the promise at a time as it already was resolved.
            // That means, the _handler_queue is gone and we cannot forward the
            // cancellation event anymore.
            // In order to cancel the possibly already resolved children promises,
            // we need to send cancel to each promise in the children list:
            for (RXPromise* promise in _promises) {
                [promise cancel];
            }
        }
    });
}


- (void) setProgress:(id)progress {
    dispatch_async(s_sync_queue, ^{
        for (progressHandler_t block in _progressHandlers) {
            // The sync queue should not become contended, thus dispatch progress blocks
            // to a concurrent queue (caveat: may spawn many threads):
            dispatch_async(dispatch_get_global_queue(0, 0), ^{
                block(progress);
            });
        }
    });
}




#pragma mark -


- (void) resolveReturnedPromise:(RXPromise*)returnedPromise
                     completion:(id(^)(id result))completionHandler
                          error:(id(^)(NSError* error))errorHandler
{
    assert(dispatch_get_specific("sync_queue.id") == RX_DISPATCH_BRIDGE_VOID_CAST(s_sync_queue));
    assert(_isFulfilled || _isRejected);
    DLogInfo(@"returned promise: %@", returnedPromise);
    
    id new_result;
    if (_isFulfilled) {
        new_result = completionHandler ? completionHandler(_result) : _result;
    } else if (_isRejected) {
        if (!errorHandler) {
            DLogInfo(@"error signal with reason %@ not handled by the promise %@", _result, self);
        }
        new_result = errorHandler ? errorHandler(_result) : _result;
    }
    if (new_result == returnedPromise) {
        NSError* error = [NSError errorWithDomain:@"RXPromise" code:-2 userInfo:@{NSLocalizedDescriptionKey: @"TypeError"}];
        [returnedPromise rejectWithReason:error];
        return;
    }
    if (_isCancelled) {
        [returnedPromise cancelWithReason:new_result];
        return;
    }
    if (new_result != nil) {
        [new_result rxp_resolvePromise:returnedPromise];
    }
    else {
        [returnedPromise fulfillWithValue:nil]; // fulfill with `nil`
    }
}

#pragma mark -

- (RXPromise*) then:(id(^)(id result))completionHandler
       errorHandler:(id(^)(NSError* error))errorHandler
    progressHandler:(void(^)(id progress))progressHandler
{
    DLogInfo(@"Invoking `then`. self: %@", self);
    
    RXPromise* promise = [[RXPromise alloc] init];
    dispatch_async(s_sync_queue, ^{
        [self.promises addObject:promise];
        // handlers will be queued in the sync queue behind "us".
        if (!(_isFulfilled || _isRejected)) {
            DLogInfo(@"exec on sync_queue: queueing handler on handler queue. self: %@", self);
            dispatch_async(self.handlerQueue, ^{
                DLogInfo(@"exec on handler_queue: dispatch handler on sync queue. self: %@", self);
                assert(self.isFulfilled || self.isRejected);
                dispatch_async(s_sync_queue, ^{
                    DLogInfo(@"exec on sync_queue: self: %@, returned promise: %@ ...", self, promise);
                    [self resolveReturnedPromise:promise completion:completionHandler error:errorHandler];
                });
            });
        }
        else {
            DLogInfo(@"exec on sync_queue: dispatch handler on sync queue. self: %@", self);
            dispatch_async(s_sync_queue, ^{
                DLogInfo(@"exec on sync_queue: self: %@, returned promise: %@ ...", self, promise);
                [self resolveReturnedPromise:promise completion:completionHandler error:errorHandler];
            });
        }
        if (progressHandler) {
            [self.progressHandlers addObject:progressHandler];
        }
    });
    DLogInfo(@"Returning from `then`. self: %@", self);
    return promise;
}


- (RXPromise*) then:(id(^)(id result))completionHandler
       errorHandler:(id(^)(NSError* error))errorHandler
{
    return [self then:completionHandler errorHandler:errorHandler progressHandler:nil];
}

- (RXPromise*) then:(id(^)(id result))completionHandler {
    return [self then:completionHandler errorHandler:nil progressHandler:nil ];
}


#pragma mark -



- (void) cancel {
    [self cancelWithReason:@"cancelled"];
}


- (id) get
{
    assert(dispatch_get_specific("sync_queue.id") != RX_DISPATCH_BRIDGE_VOID_CAST(s_sync_queue)); // Must not execute on the private sync queue!
    
    __block id result;
    __block dispatch_queue_t handler_queue = NULL;
    dispatch_sync(s_sync_queue, ^{
        if (_isFulfilled || _isRejected) {
            result = _result;
            return;
        }
        handler_queue = self.handlerQueue;
        RX_DISPATCH_RETAIN(handler_queue);
    });
    if (handler_queue) {
        // result was not yet availbale: queue a handler
        dispatch_sync(handler_queue, ^{  // block until handler_queue will be resumed ...
            dispatch_sync(s_sync_queue, ^{  // safely retrieve _result
                result = _result;
            });
        });
        RX_DISPATCH_RELEASE(handler_queue);
    }
    return _result;
}

- (void) wait {
    [self get];
}


#pragma mark -

- (NSString*) description {
    return [self rxp_descriptionLevel:0];
}


- (NSString*) rxp_descriptionLevel:(int)level {
    NSString* indent = [NSString stringWithFormat:@"%*s",4*level+4,""];
    NSMutableString* desc = [[NSMutableString alloc] initWithFormat:@"%@<%@:%p> { State: %@ }",
                             indent,
                             NSStringFromClass([self class]), (__bridge void*)self,
                             (_isFulfilled?[NSString stringWithFormat:@"fulfilled with value: %@", _result]:
                              _isRejected?[NSString stringWithFormat:@"rejected with reason: %@", _result]
                              :@"pending")
                             ];
    if (_promises) {
        [desc appendString:[NSString stringWithFormat:@", children (%d): [\n", (int)_promises.count]];
        for (RXPromise* p in _promises) {
            [desc appendString:[p rxp_descriptionLevel:level+1]];
            [desc appendString:@"\n"];
        }
        [desc appendString:[NSString stringWithFormat:@"%@]", indent]];
    }
    return desc;
}


@end


@implementation RXPromise (RXResolver)
- (void) rxp_resolvePromise:(RXPromise*)promise {
    [self then:^id(id result) {
        [promise fulfillWithValue:result];  // §2.2: if self is fulfilled, fulfill promise with the same value
        return nil;
    }
  errorHandler:^id(NSError* error) {
      [promise rejectWithReason:error];  // §2.3: if self is rejected, reject promise with the same value.
      return nil;
  }];
}
@end

@implementation NSObject (RXResolver)
- (void) rxp_resolvePromise:(RXPromise*)promise {
#if defined (HANDLE_THENABLE)
    if ([self respondsToSelector:@selector(then:errorHandler:)]) {
        [self then:^id(id y) {
            if (self == y) {
                [promise fulfillWithValue:self];
            }
            else {
                [self resolveReturnedPromise:promise withResult:y];
            }
            return nil;
        }
      errorHandler:^id(NSError *error) {
          [promise rejectWithReason:error];
          return nil;
      }];
    }
    else {
        // We should reach here if value is either `nil`, is an `NSError`, or
        // does not respond to a then:errorHandler: message.
        [promise fulfillWithValue:self]; // forward result
    }
#else
    // This is not strict according the spec:
    // If value is an object we require it to be a `thenable` or we must
    // reject the promise with an appropriate error.
    // However this API supports only objects, that is, our value is always
    // an `id` and not a struct or other primitive C type or a C++ class, etc.
    // We also do not support `thenables`.
    // So, we handle values which are not RXPromises and not NSErrors as if
    // they were non-objects and simply fulfill the promise with this value.
    [promise fulfillWithValue:self]; // forward result
#endif
}

@end

@implementation NSError (RXResolver)

- (void) rxp_resolvePromise:(RXPromise*)promise {
    [promise rejectWithReason:self];
}

@end




