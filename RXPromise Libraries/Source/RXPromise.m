//
//  RXPromise.m
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
//#define DEBUG_LOG 4   //enable this in order to log verbosely
#if defined (DEBUG_LOG)
#undef DEBUG_LOG
#endif
#define DEBUG_LOG 2
#import "utility/DLog.h"
#include <assert.h>
#include <stdio.h>



#if TARGET_OS_IPHONE
// Compiling for iOS
    #if __IPHONE_OS_VERSION_MIN_REQUIRED >= 60000
        // >= iOS 6.0
        #define RX_DISPATCH_RELEASE(__object) do {} while(0)
        #define RX_DISPATCH_RETAIN(__object) do {} while(0)
        #define RX_DISPATCH_BRIDGE_VOID_CAST(__object) (__bridge void*)__object
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
        #define RX_DISPATCH_BRIDGE_VOID_CAST(__object) (__bridge void*)__object
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


/** RXPomise_State */
typedef enum RXPomise_StateT {
    Pending     = 0x0,      
    Fulfilled   = 0x01,     
    Rejected    = 0x02,     
    Cancelled   = 0x06      
} RXPomise_State;

@interface RXPromise ()
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
    short                   _state;
}
@synthesize progressHandlers = _progressHandlers;
@synthesize promises = _promises;


static dispatch_queue_t s_sync_queue;
static dispatch_queue_t s_handler_parent_queue;

const static char* KeySync = "sync";
const static char* KeyHandler = "handler";
const static char* KeyID = "id";


static inline void rx_dispatch_sync_queue(dispatch_block_t block)
{
    // If we're already on the s_sync_queue, just run the block:
    if (dispatch_get_specific(KeyID) == RX_DISPATCH_BRIDGE_VOID_CAST(s_sync_queue))
        block();
    // otherwise, dispatch to the s_sync_queue:
    else
        dispatch_sync(s_sync_queue, block);
}



// Designated Initializer
- (id)init
{
    static dispatch_once_t onceSharedQueues;
    dispatch_once(&onceSharedQueues, ^{
        s_sync_queue = dispatch_queue_create("s_sync_queue", NULL);
        dispatch_queue_set_specific(s_sync_queue, KeySync, RX_DISPATCH_BRIDGE_VOID_CAST(s_sync_queue), NULL);
        dispatch_queue_set_specific(s_sync_queue, KeyID, RX_DISPATCH_BRIDGE_VOID_CAST(s_sync_queue), NULL);
        s_handler_parent_queue = dispatch_queue_create("s_handler_parent_queue", NULL);
        dispatch_queue_set_specific(s_handler_parent_queue, KeyHandler, RX_DISPATCH_BRIDGE_VOID_CAST(s_handler_parent_queue), NULL);
        dispatch_queue_set_specific(s_handler_parent_queue, KeyID, RX_DISPATCH_BRIDGE_VOID_CAST(s_handler_parent_queue), NULL);
        //dispatch_set_target_queue(s_handler_parent_queue, s_sync_queue);
        assert(s_sync_queue);
        assert(s_handler_parent_queue);
        assert(dispatch_queue_get_specific(s_sync_queue, KeySync) == RX_DISPATCH_BRIDGE_VOID_CAST(s_sync_queue));
        assert(dispatch_queue_get_specific(s_handler_parent_queue, KeyHandler) == RX_DISPATCH_BRIDGE_VOID_CAST(s_handler_parent_queue));
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

#pragma mark - KVO

// KVO compatible 
- (void) _setState:(RXPomise_State)state {
    assert(dispatch_get_specific(KeyID) == RX_DISPATCH_BRIDGE_VOID_CAST(s_sync_queue));
    assert(state != Pending);
    
    switch (state) {
        case Pending: break;
        case Fulfilled: {
            _state = Fulfilled;
//            dispatch_async(s_handler_parent_queue, ^{
//                [self willChangeValueForKey:@"isPending"];
//                [self willChangeValueForKey:@"isFulfilled"];
//                [self didChangeValueForKey:@"isFulfilled"];
//                [self didChangeValueForKey:@"isPending"];
//            });
        }
            break;
            
        case Cancelled: {
            _state = Cancelled;
//            dispatch_async(s_handler_parent_queue, ^{
//                [self willChangeValueForKey:@"isPending"];
//                [self willChangeValueForKey:@"isCancelled"];
//                [self willChangeValueForKey:@"isRejected"];
//                [self didChangeValueForKey:@"isRejected"];
//                [self didChangeValueForKey:@"isCancelled"];
//                [self didChangeValueForKey:@"isPending"];
//            });
        }
            break;
            
        case Rejected: {
            _state = Rejected;
//            dispatch_async(s_handler_parent_queue, ^{
//                [self willChangeValueForKey:@"isPending"];
//                [self willChangeValueForKey:@"isRejected"];
//                [self didChangeValueForKey:@"isRejected"];
//                [self didChangeValueForKey:@"isPending"];
//            });
        }
            break;
    } // switch
}

- (BOOL) isPending {
    if (dispatch_get_specific(KeyID) == RX_DISPATCH_BRIDGE_VOID_CAST(s_sync_queue)) {
        return _state == Pending;
    }
    else {
        __block BOOL result;
        dispatch_sync(s_sync_queue, ^{
            result = _state == Pending ;
        });
        return result;
    }
}

- (BOOL) isFulfilled {
    if (dispatch_get_specific(KeyID) == RX_DISPATCH_BRIDGE_VOID_CAST(s_sync_queue)) {
        return _state == Fulfilled;
    }
    else {
        __block BOOL result;
        dispatch_sync(s_sync_queue, ^{ result = _state == Fulfilled; });
        return result;
    }
}

- (BOOL) isRejected {
    if (dispatch_get_specific(KeyID) == RX_DISPATCH_BRIDGE_VOID_CAST(s_sync_queue)) {
        return (_state & Rejected) != 0;
    }
    else {
        __block BOOL result;
        dispatch_sync(s_sync_queue, ^{ result = (_state & Rejected) != 0; });
        return result;
    }
}

- (BOOL) isCancelled {
    if (dispatch_get_specific(KeyID) == RX_DISPATCH_BRIDGE_VOID_CAST(s_sync_queue)) {
        return _state == Cancelled;
    }
    else {
        __block BOOL result;
        dispatch_sync(s_sync_queue, ^{ result = _state == Cancelled; });
        return result;
    }
}


- (id) result {
    if (dispatch_get_specific(KeyID) == RX_DISPATCH_BRIDGE_VOID_CAST(s_sync_queue)) {
        return _result;
    }
    else {
        __block id result;
        dispatch_sync(s_sync_queue, ^{
            result = _result;
        });
        return result;
    }
}

- (RXPomise_State) state {
    if (dispatch_get_specific(KeyID) == RX_DISPATCH_BRIDGE_VOID_CAST(s_sync_queue)) {
        return _state;
    }
    else {
        __block RXPomise_State state;
        dispatch_sync(s_sync_queue, ^{
            state = _state;
        });
        return state;
    }
}




#pragma mark -

// property then
- (then_t) then {
    __block RXPromise* blockSelf = self;
    return ^(completionHandler_t completionHandler, errorHandler_t errorHandler) {
        RXPromise* returnedPromise;
        [blockSelf registerCompletionHandler:completionHandler errorHandler:errorHandler progressHandler:NULL returnedPromise:&returnedPromise];
        blockSelf = nil;
        return returnedPromise;
    };
}



- (NSMutableArray*) progressHandlers
{
    assert(dispatch_get_specific(KeyID) == RX_DISPATCH_BRIDGE_VOID_CAST(s_sync_queue));
    if (_progressHandlers == nil) {
        _progressHandlers = [[NSMutableArray alloc] initWithCapacity:1];
    }
    return _progressHandlers;
}

- (NSMutableArray*) promises
{
    assert(dispatch_get_specific(KeyID) == RX_DISPATCH_BRIDGE_VOID_CAST(s_sync_queue));
    if (_promises == nil) {
        _promises = [[NSMutableArray alloc] initWithCapacity:1];
    }
    return _promises;
}


- (dispatch_queue_t) handlerQueue
{
    assert(dispatch_get_specific(KeyID) == RX_DISPATCH_BRIDGE_VOID_CAST(s_sync_queue));
    if (!_handler_queue) {
        char buffer[64];
        snprintf(buffer, sizeof(buffer),"RXPromise_handler_queue-%p", (__bridge void*)self);
        _handler_queue = dispatch_queue_create(buffer, DISPATCH_QUEUE_SERIAL);
        assert(_handler_queue);
        dispatch_set_target_queue(_handler_queue, s_handler_parent_queue);
        dispatch_suspend(_handler_queue);
    }
    return _handler_queue;
}

#pragma mark - Resolver

// Note: resolving actually uses a dispatch_sync in order to set the state
// and result.
// The resolver methods will be likely invoked from an execution context where
// a concurrent queue will be used. We should not block those queues, since this
// *may* cause GCD to spawn another thread if another task is to be executed on
// the same concurrent queue. If the sync_queue is not contended, this should not
// happen.
// Otherwise, we probably should dispatch *asynchronously* even for the
// cost of a block copy heap. But then, we cannot be sure that _state and
// _result is "visible" in the handler queue, unless they have the same
// target queue (which is NOT true currently!).



- (void) fulfillWithValue:(id)result {
    assert(dispatch_get_specific(KeyID) != RX_DISPATCH_BRIDGE_VOID_CAST(s_sync_queue));
    assert(![result isKindOfClass:[NSError class]]);

    dispatch_once(&_once_result, ^{
        // dispatch a fulfill signal on the sync queue:
        dispatch_async(s_sync_queue, ^{
            DLogInfo(@"self: %@, exec on sync_queue: `fulfillWithValue:`%@", self, result);
            _result = result;
            [self _setState:Fulfilled];
            if (_handler_queue) {
                dispatch_resume(_handler_queue);
                RX_DISPATCH_RELEASE(_handler_queue);
                _handler_queue = NULL;
            }
        });
    });
}

- (void) rejectWithReason:(id)reason {
    assert(dispatch_get_specific(KeyID) != RX_DISPATCH_BRIDGE_VOID_CAST(s_sync_queue));

    if (![reason isKindOfClass:[NSError class]]) {
        reason = [[NSError alloc] initWithDomain:@"RXPromise" code:-1000 userInfo:@{@"reason": reason}];
    }
    dispatch_once(&_once_result, ^{
        // dispatch a rejected signal on the sync queue:
        dispatch_async(s_sync_queue, ^{ // TODO: check whether dispatch_sync is preferable
            DLogInfo(@"self: %@, exec on sync_queue: `rejectWithReason:`%@", self, reason);
            _result = reason;
            [self _setState:Rejected];
            if (_handler_queue) {
                dispatch_resume(_handler_queue);
                RX_DISPATCH_RELEASE(_handler_queue);
                _handler_queue = NULL;
            }
        });
    });
}

- (void) cancelWithReason:(id)reason {
    //assert(dispatch_get_specific(KeyID) != RX_DISPATCH_BRIDGE_VOID_CAST(s_sync_queue));

    if (![reason isKindOfClass:[NSError class]]) {
        reason = [[NSError alloc] initWithDomain:@"RXPromise" code:-1 userInfo:@{@"reason": reason}];
    }
    dispatch_once(&_once_result, ^{
        // dispatch a cancel signal on the sync queue:
        dispatch_async(s_sync_queue, ^{ // TODO: check whether dispatch_sync is preferable
            DLogInfo(@"self: %@, exec on sync_queue: `cancelWithReason:`%@", self, reason);
            _result = reason;
            [self _setState:Cancelled];
            if (_handler_queue) {
                dispatch_resume(_handler_queue);
                RX_DISPATCH_RELEASE(_handler_queue);
                _handler_queue = NULL;
            }
        });
    });
    dispatch_async(s_sync_queue, ^{
        if (_state != Cancelled) {
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


- (void) bind:(RXPromise*) other {
    assert(other != nil);
    //assert(dispatch_get_specific(KeyID) != RX_DISPATCH_BRIDGE_VOID_CAST(s_sync_queue));
    
    dispatch_async(s_sync_queue, ^{  // TODO: check whether dispatch_sync is preferable
        assert(_state == Pending || _state == Cancelled);
        if (_state == Cancelled) {
            [other cancelWithReason:_result];
            return;
        }
        other.then(^id(id result){
            assert( _state == Pending || _state == Cancelled );
            [self fulfillWithValue:result];
            return result;
        }, ^id(NSError*error){
            assert( _state == Pending || _state == Cancelled );
            [self rejectWithReason:error];
            return error;
        });
        
        self.then(nil, ^id(NSError*reason){
            if (_state == Cancelled) {
                [other cancelWithReason:reason];
            }
            return reason;
        });
    });
}



- (void) setProgress:(id)progress {
    //assert(dispatch_get_specific(KeyID) != RX_DISPATCH_BRIDGE_VOID_CAST(s_sync_queue));
    dispatch_async(s_sync_queue, ^{ // TODO: check whether dispatch_sync is preferable
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

// `returnedPromise` may be nil, which means that we simply call the corresponding
// completion handler but do not resolve the returned promise.
- (void) resolveReturnedPromise:(RXPromise*)returnedPromise
                     completion:(id(^)(id result))completionHandler
                          error:(id(^)(NSError* error))errorHandler
{
    assert(dispatch_get_specific(KeyID) == RX_DISPATCH_BRIDGE_VOID_CAST(s_handler_parent_queue));
    assert(_state != Pending);
    DLogInfo(@"returned promise: %@", returnedPromise);
    
    // Note: when we reach here we should be pretty sure that there is no race
    // when accessing _state and _result. Iff the handler queue and the sync
    // queue have the same parent queue (which is currently NOT true!) this is
    // always guaranteed. Nonetheless, be safe:
    id result = self.result;
    RXPomise_State state = self.state;
    
    id new_result;
    if (state == Fulfilled) {
        new_result = completionHandler ? completionHandler(result) : result;
    } else {
        if (!errorHandler) {
            DLogInfo(@"error signal with reason %@ not handled by the promise %@", result, self);
        }
        new_result = errorHandler ? errorHandler(result) : result;
    }
    if (returnedPromise != nil) {
        if (new_result == returnedPromise) {
            NSError* error = [NSError errorWithDomain:@"RXPromise" code:-2 userInfo:@{NSLocalizedDescriptionKey: @"TypeError"}];
            [returnedPromise rejectWithReason:error];
            return;
        }
        if (state == Cancelled) {
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
}

#pragma mark -



- (void) registerCompletionHandler:(id(^)(id result))completionHandler
                      errorHandler:(id(^)(NSError* error))errorHandler
                   progressHandler:(void(^)(id progress))progressHandler
                   returnedPromise:(RXPromise**)returnedPromise
{
    DLogInfo(@"self: %@", self);
    RXPromise* promise = nil;
    if (returnedPromise != NULL) {
        promise = [[RXPromise alloc] init];
        *returnedPromise = promise;
    }
    __block RXPromise* blockSelf = self;
    dispatch_async(s_sync_queue, ^{
        if (promise)
            [blockSelf.promises addObject:promise];
        // handlers will be queued in the sync queue behind "us".
        if (_state == Pending) {
            DLogInfo(@"exec on sync_queue: queueing handler on handler queue. self: %@", self);
            __weak RXPromise* weakSelf = blockSelf;
            dispatch_async(blockSelf.handlerQueue, ^{
                // Note: the current queue is suspended!
                assert(_state != Pending); // TODO: is it's safe to access _state?
                if (weakSelf) {
                    [weakSelf resolveReturnedPromise:promise completion:completionHandler error:errorHandler];
                } else {
                    DLogWarn(@"promise has been deleted before handlers called.");
                }
            });
        }
        else {
            dispatch_async(s_handler_parent_queue, ^{ // TODO: check whether dispatch_sync is preferable
                [blockSelf resolveReturnedPromise:promise completion:completionHandler error:errorHandler];
            });
        }
        if (progressHandler) {
            [blockSelf.progressHandlers addObject:progressHandler];
        }
        blockSelf = nil;
    });
    DLogInfo(@"Returning. self: %@", self);
}


- (void) registerCompletionHandler:(id(^)(id result))completionHandler
                            errorHandler:(id(^)(NSError* error))errorHandler
                         returnedPromise:(RXPromise**)returnedPromise
{
    [self registerCompletionHandler:completionHandler errorHandler:errorHandler progressHandler:nil returnedPromise:returnedPromise];
}

- (void) registerCompletionHandler:(id(^)(id result))completionHandler
                         returnedPromise:(RXPromise**)returnedPromise
{
    [self registerCompletionHandler:completionHandler errorHandler:nil progressHandler:nil returnedPromise:returnedPromise];
}


// Thenable:

- (RXPromise*)then:(completionHandler_t)completionHandler errorHandler:(errorHandler_t)errorHandler {
    RXPromise* returnedPromise;
    [self registerCompletionHandler:completionHandler errorHandler:errorHandler progressHandler:nil returnedPromise:&returnedPromise];
    return returnedPromise;
}



#pragma mark -


+(RXPromise*) all:(NSArray*)promises
{
    __block int count = (int)[promises count];
    assert(count > 0);
    RXPromise* promise = [[RXPromise alloc] init];
    completionHandler_t onSuccess = ^(id result){
        --count;
        if (count == 0) {
            [promise fulfillWithValue:promises];
        }
        return result;
    };
    errorHandler_t onError = ^(NSError* error) {
        [promise rejectWithReason:error];
        return error;
    };
    dispatch_async(s_sync_queue, ^{
        for (RXPromise* p in promises) {
            p.then(onSuccess, onError);
        }
    });
    
    promise.then(nil, ^id(NSError*error){
        for (RXPromise* p in promises) {
            [p cancelWithReason:error];
        }
        return error;
    });
    
    return promise;
}



#pragma mark -



- (void) cancel {
    [self cancelWithReason:@"cancelled"];
}

/** Future version
- (void) always:(void(^)(id value))onCompletion {
    assert(onCompletion);
    self.then(^id(id result){
        onCompletion(result);
        return nil;
    }, ^id(NSError*error){
        onCompletion(error);
        return nil;
    });
} 
*/

#pragma mark -

- (id) get
{
    assert(dispatch_get_specific(KeyID) != RX_DISPATCH_BRIDGE_VOID_CAST(s_sync_queue)); // Must not execute on the private sync queue!
    
    __block id result;
    __block dispatch_semaphore_t avail = NULL;
    dispatch_sync(s_sync_queue, ^{
        if (_state != Pending) {
            result = _result;
            return;
        } else {
            avail = dispatch_semaphore_create(0);
            dispatch_async(self.handlerQueue, ^{
                dispatch_semaphore_signal(avail);
            });
        }
    });
    if (avail) {
        // result was not yet availbale: queue a handler
        if (dispatch_semaphore_wait(avail, DISPATCH_TIME_FOREVER) == 0) { // wait until handler_queue will be resumed ...
            dispatch_sync(s_sync_queue, ^{  // safely retrieve _result
                result = _result;
            });
        }
        RX_DISPATCH_RELEASE(avail);
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
                             ( (_state == Fulfilled)?[NSString stringWithFormat:@"fulfilled with value: %@", _result]:
                              (_state == Rejected)?[NSString stringWithFormat:@"rejected with reason: %@", _result]:
                              (_state == Cancelled)?[NSString stringWithFormat:@"cancelled with reason: %@", _result]
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
    [self registerCompletionHandler:^id(id result) {
        [promise fulfillWithValue:result];  // §2.2: if self is fulfilled, fulfill promise with the same value
        return nil;
    }
    errorHandler:^id(NSError *error) {
        [promise rejectWithReason:error];  // §2.3: if self is rejected, reject promise with the same value.
        return nil;
    } progressHandler:nil
    returnedPromise:NULL];
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
      }
      ];
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




