//
//  RXPromise.mm
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
#include <cassert>
#include <map>
#import "utility/DLog.h"
#include <cstdio>


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
typedef enum RXPromise_StateT {
    Pending     = 0x0,
    Fulfilled   = 0x01,
    Rejected    = 0x02,
    Cancelled   = 0x06
} RXPromise_State;


struct RXPromise_StateAndResult {
    RXPromise_StateT  state;
    id                result;
};

@interface RXPromise ()
@property (nonatomic) id result;
@end

@implementation RXPromise {
    RXPromise*          _parent;
    dispatch_queue_t    _handler_queue;  // a serial queue, uses target queue: s_sync_queue
    id                  _result;
    RXPromise_State     _state;
}
@synthesize result = _result;
@synthesize parent = _parent;

typedef std::multimap<void const*, __weak RXPromise*> assocs_t;

static dispatch_queue_t s_sync_queue;
static const char* s_sync_queue_id = "RXPromise.shared_sync_queue";

static dispatch_queue_t s_default_concurrent_queue;
static const char* s_default_concurrent_queue_id = "RXPromise.default_concurrent_queue";


static assocs_t  s_assocs;
static dispatch_once_t  onceSharedQueues;

const static char* QueueID = "RXPromise.queue_id";



static void RXPromise_init() {
    dispatch_once(&onceSharedQueues, ^{
        s_sync_queue = dispatch_queue_create(s_sync_queue_id, NULL);
        assert(s_sync_queue);
        dispatch_queue_set_specific(s_sync_queue, QueueID, (void*)(s_sync_queue_id), NULL);

        s_default_concurrent_queue = dispatch_queue_create(s_default_concurrent_queue_id, DISPATCH_QUEUE_CONCURRENT);
        assert(s_default_concurrent_queue);
    });
}

static NSError* makeTimeoutError() {
    return [[NSError alloc] initWithDomain:@"RXPromise" code:-1001 userInfo:@{NSLocalizedFailureReasonErrorKey: @"timeout"}];
}



// Designated Initializer
- (id)initWithParent:(RXPromise*)parent {
    self = [super init];
    if (self) {
        RXPromise_init();
        _parent = parent;
    }
    DLogInfo(@"create: %p", (__bridge void*)self);
    return self;
}

// Designated Initializer
- (id)initRootWithHandlerQueue:(dispatch_queue_t)handler_queue{
    self = [super init];
    if (self) {
        RXPromise_init();
        _parent = nil;
    }
    DLogInfo(@"create: %p", (__bridge void*)self);
    return self;
}

- (id)init {
    return [self initWithParent:nil];
}

- (void) dealloc {
    DLogInfo(@"dealloc: %p", (__bridge void*)self);
    if (_handler_queue) {
        DLogWarn(@"handlers not signaled");
        dispatch_resume(_handler_queue);
        RX_DISPATCH_RELEASE(_handler_queue);
    }
    void const* key = (__bridge void const*)(self);
    if (dispatch_get_specific(QueueID) == s_sync_queue_id) {
        s_assocs.erase(key);
    } else {
        dispatch_barrier_sync(s_sync_queue, ^{
            s_assocs.erase(key);
        });
    }
}

#pragma mark -


- (BOOL) isPending {
    return _state == Pending ? YES : NO;
}

- (BOOL) isFulfilled {
    return _state == Fulfilled ? YES : NO;
}

- (BOOL) isRejected {
    return ((_state & Rejected) != 0) ? YES : NO;
}

- (BOOL) isCancelled {
    return _state == Cancelled ? YES : NO;
}


- (RXPromise_StateAndResult) peakStateAndResult {
    if (dispatch_get_specific(QueueID) == s_sync_queue_id) {
        return {_state, _result};
    }
    else {
        __block RXPromise_StateAndResult result;
        dispatch_sync(s_sync_queue, ^{
            result.result = _result;
            result.state = _state;
        });
        return result;
    }
}


- (RXPromise_StateAndResult) synced_peakStateAndResult {
    assert(dispatch_get_specific(QueueID) == s_sync_queue_id);
    return {_state, _result};
}


- (dispatch_queue_t) handlerQueue
{
    if (dispatch_get_specific(QueueID) == s_sync_queue_id) {
        dispatch_queue_t queue = [self synced_handlerQueue];
        RX_DISPATCH_RETAIN(queue);
        return queue;
    }
    else {
        __block dispatch_queue_t queue = nil;
        dispatch_barrier_sync(s_sync_queue, ^{
            queue = [self synced_handlerQueue];
            RX_DISPATCH_RETAIN(queue);
        });
        return queue;
    }
}


// Returns the queue where the handlers will be executed.
// Returns s_sync_queue if the receiver has already been resolved.
-(dispatch_queue_t) synced_handlerQueue
{
    assert(dispatch_get_specific(QueueID) == s_sync_queue_id);
    if (_state == Pending) {
        if (_handler_queue == nil) {
            char buffer[64];
            snprintf(buffer, sizeof(buffer),"RXPromise.handler_queue-%p", (__bridge void*)self);
            _handler_queue = dispatch_queue_create(buffer, NULL);
            dispatch_set_target_queue(_handler_queue, s_sync_queue);
            dispatch_suspend(_handler_queue);
        }
        assert(_handler_queue);
        return _handler_queue;
    }
    return s_sync_queue;
}


- (void) resolveWithResult:(id)result {
    dispatch_barrier_async(s_sync_queue, ^{
        [self synced_resolveWithResult:result];
    });
}


- (void) fulfillWithValue:(id)value {
    assert(![value isKindOfClass:[NSError class]]);
    if (dispatch_get_specific(QueueID) == s_sync_queue_id) {
        [self synced_fulfillWithValue:value];
    }
    else {
        dispatch_barrier_sync(s_sync_queue, ^{
            [self synced_fulfillWithValue:value];
        });
    }
}


- (void) rejectWithReason:(id)reason {
    if (dispatch_get_specific(QueueID) == s_sync_queue_id) {
        [self synced_rejectWithReason:reason];
    }
    else {
        dispatch_barrier_sync(s_sync_queue, ^{
            [self synced_rejectWithReason:reason];
        });
    }
}


- (void) cancel {
    [self cancelWithReason:@"cancelled"];
}

- (void) cancelWithReason:(id)reason {
    dispatch_barrier_async(s_sync_queue, ^{  // async, in order to be less prone to dead locks
        [self synced_cancelWithReason:reason];
    });
}


- (RXPromise*) setTimeout:(NSTimeInterval)timeout {
    if (timeout < 0) {
        return self;
    }
    else if (timeout == 0) {
        [self rejectWithReason:makeTimeoutError()];
        return self;
    }
    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, s_sync_queue);
    dispatch_source_set_event_handler(timer, ^{
        dispatch_source_cancel(timer); // one shot timer
        [self rejectWithReason:makeTimeoutError()];
    });
    [self registerWithQueue:s_sync_queue onSuccess:^id(id result) {
        dispatch_source_cancel(timer);
        RX_DISPATCH_RELEASE(timer);
        return nil;
    }  onFailure:^id(NSError *error) {
        dispatch_source_cancel(timer);
        RX_DISPATCH_RELEASE(timer);
        return nil;
    }
    returnPromise:NO];
    dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(timeout * NSEC_PER_SEC)),
                              DISPATCH_TIME_FOREVER /*one shot*/, 0 /*_leeway*/);
    dispatch_resume(timer);

    return self;
}



- (void) synced_resolveWithResult:(id)result {
    assert(dispatch_get_specific(QueueID) == s_sync_queue_id);
    if (result == nil) {
        [self synced_fulfillWithValue:nil];
    }
    else {
        [result rxp_resolvePromise:self];
    }
}


- (void) synced_fulfillWithValue:(id)result {
    assert(dispatch_get_specific(QueueID) == s_sync_queue_id);
    if (_state != Pending) {
        return;
    }
    _result = result;
    _state = Fulfilled;
    if (_handler_queue) {
        dispatch_resume(_handler_queue);
        RX_DISPATCH_RELEASE(_handler_queue);
        _handler_queue = nil;
    }
}


- (void) synced_rejectWithReason:(id)reason {
    assert(dispatch_get_specific(QueueID) == s_sync_queue_id);
    if (_state != Pending) {
        return;
    }
    if (![reason isKindOfClass:[NSError class]]) {
        reason = [[NSError alloc] initWithDomain:@"RXPromise"
                                            code:-1000
                                        userInfo:@{NSLocalizedFailureReasonErrorKey: reason ? reason : @""}];
    }
    _result = reason;
    _state = Rejected;
    if (_handler_queue) {
        dispatch_resume(_handler_queue);
        RX_DISPATCH_RELEASE(_handler_queue);
        _handler_queue = nil;
    }
}


- (void) synced_cancelWithReason:(id)reason {
    assert(dispatch_get_specific(QueueID) == s_sync_queue_id);
    if (_state == Cancelled) {
        return;
    }
    if (![reason isKindOfClass:[NSError class]]) {
        reason = [[NSError alloc] initWithDomain:@"RXPromise"
                                            code:-1
                                        userInfo:@{NSLocalizedFailureReasonErrorKey: reason ? reason : @""}];
    }
    if (_state == Pending) {
        DLogDebug(@"cancelled %p.", (__bridge void*)(self));
        _result = reason;
        _state = Cancelled;
        if (_handler_queue) {
            dispatch_resume(_handler_queue);
            RX_DISPATCH_RELEASE(_handler_queue);
            _handler_queue = nil;
        }
    }
    if (_state != Cancelled) {
        // We cancelled the promise at a time as it already was resolved.
        // That means, the _handler_queue is gone and we cannot forward the
        // cancellation event to any child ("returnedPromise") anymore.
        // In order to cancel the possibly already resolved children promises,
        // we need to send cancel to each promise in the children list:
        void const* key = (__bridge void const*)(self);
        auto range = s_assocs.equal_range(key);
        while (range.first != range.second) {
            DLogDebug(@"%p forwarding cancel to %p", key, (__bridge void*)((*(range.first)).second));
            [(*(range.first)).second cancel];
            ++range.first;
        }
        s_assocs.erase(key);
    }
}


// Registers success and failure handlers.
// The receiver will be retained and only released when the receiver will be
// resolved (see "Requirements for an asynchronous result provider").
// Returns a new promise which represents the return values of the handler
// blocks.
- (RXPromise*) registerWithQueue:(dispatch_queue_t)target_queue
                       onSuccess:(promise_completionHandler_t)onSuccess
                       onFailure:(promise_errorHandler_t)onFailure
                   returnPromise:(BOOL)returnPromise    __attribute((ns_returns_retained))
{
    RXPromise* returnedPromise = returnPromise ? [[RXPromise alloc] initWithParent:self] : nil;
    __weak RXPromise* weakReturnedPromise = returnedPromise;
    __block RXPromise* blockSelf = self;
    if (target_queue == nil) {
        target_queue = s_default_concurrent_queue;
    }
    dispatch_queue_t handler_queue = [self handlerQueue];
    assert(handler_queue);
    assert(handler_queue == s_sync_queue || handler_queue == _handler_queue);
    DLogInfo(@"promise %p register handlers %p %p running on %s returning promise: %p",
             (__bridge void*)(blockSelf), (__bridge void*)(onSuccess), (__bridge void*)(onFailure),
             dispatch_queue_get_label(target_queue),
             (__bridge void*)(returnedPromise));
    
    dispatch_block_t handlerBlock = ^{
        @autoreleasepool { // mainly for releasing unused return values from the handlers
            RXPromise_StateAndResult ps = [blockSelf peakStateAndResult];
            assert(ps.state != Pending);
            if (ps.state == Fulfilled && onSuccess) {
                ps.result = onSuccess(ps.result);
            }
            else if (ps.state != Fulfilled && onFailure) {
                ps.result = onFailure(ps.result);
            }
            RXPromise* strongReturnedPromise = weakReturnedPromise;
            if (strongReturnedPromise) {
                assert(ps.result != strongReturnedPromise); // @"cyclic promise error");
                if (ps.state == Cancelled) {
                    [strongReturnedPromise cancelWithReason:ps.result];
                }
                else {
                    DLogInfo(@"%p add child %p", (__bridge void*)(blockSelf), (__bridge void*)(strongReturnedPromise));
                    dispatch_block_t block = ^{
                        s_assocs.emplace((__bridge void*)(blockSelf), weakReturnedPromise);
                    };
                    if (target_queue == s_sync_queue) {
                        block();
                    } else {
                        dispatch_barrier_sync(s_sync_queue, block);  // MUST be synchronous!
                    }
                    // There are four cases how the returned promise will be resolved:
                    // 1. result isKindOfClass NSError   -> rejected with reason error
                    // 2. result isKindOfClass RXPromise -> fulFilled with promise
                    // 3. result equals nil              -> fulFilled with nil
                    // 4  result is any other object     -> fulFilled with value
                    if (ps.result && [ps.result isKindOfClass:[NSError class]]) {
                        [strongReturnedPromise rejectWithReason:ps.result];
                    }
                    else if (ps.result && [ps.result isKindOfClass:[RXPromise class]]) {
                        [returnedPromise bind:ps.result];
                    }
                    else {
                        [strongReturnedPromise fulfillWithValue:ps.result];
                    }
                }
            }
        }
        RX_DISPATCH_RELEASE(target_queue);
        blockSelf = nil;
    };
    RX_DISPATCH_RETAIN(target_queue);
    dispatch_async(handler_queue, ^{
        // A handler fires:
        assert(dispatch_get_specific(QueueID) == s_sync_queue_id);
        if (target_queue == s_sync_queue) {
            handlerBlock();
        }
        else {
            dispatch_async(target_queue, handlerBlock);
        }
    });
    RX_DISPATCH_RELEASE(handler_queue);
    return returnedPromise;
}


- (then_block_t) then {
    __block RXPromise* blockSelf = self;
    return ^RXPromise*(promise_completionHandler_t onSucess, promise_errorHandler_t onFailure) __attribute((ns_returns_retained)) {
        RXPromise* p = [blockSelf registerWithQueue:nil onSuccess:onSucess onFailure:onFailure returnPromise:YES];
        blockSelf = nil;
        return p;
    };
}


- (then_on_block_t) thenOn {
    __block RXPromise* blockSelf = self;
    return ^RXPromise*(dispatch_queue_t queue, promise_completionHandler_t onSucess, promise_errorHandler_t onFailure) __attribute((ns_returns_retained)) {
        RXPromise* p = [blockSelf registerWithQueue:queue onSuccess:onSucess onFailure:onFailure returnPromise:YES];
        blockSelf = nil;
        return p;
    };
}



#pragma mark -

- (id) get {
    return [self getWithTimeout:-1.0];  // negative means infinitive
}


- (id) getWithTimeout:(NSTimeInterval)timeout
{
    assert(dispatch_get_specific(QueueID) != s_sync_queue_id); // Must not execute on the private sync queue!
    
    __block id result;
    __block dispatch_semaphore_t avail = NULL;
    dispatch_sync(s_sync_queue, ^{
        if (_state != Pending) {
            result = _result;
        } else {
            avail = dispatch_semaphore_create(0);
            dispatch_async([self synced_handlerQueue], ^{
                dispatch_semaphore_signal(avail);
            });
        }
    });
    if (avail) {
        // result was not yet availbale: queue a handler
        dispatch_time_t t = timeout < 0 ? DISPATCH_TIME_FOREVER : dispatch_time(DISPATCH_TIME_NOW, (int64_t)(timeout * NSEC_PER_SEC));
        if (dispatch_semaphore_wait(avail, t) == 0) { // wait until handler_queue will be resumed ...
            dispatch_sync(s_sync_queue, ^{  // safely retrieve _result
                result = _result;
            });
        }
        else {
            result = makeTimeoutError();
        }
        RX_DISPATCH_RELEASE(avail);
    }
    return result;
}




- (id) get2 {
    assert(dispatch_get_specific(QueueID) != s_sync_queue_id); // Must not execute on the private sync queue!
    __block id result;
    dispatch_semaphore_t avail = dispatch_semaphore_create(0);
    dispatch_async([self handlerQueue], ^{
        result = _result;
        dispatch_semaphore_signal(avail);
    });
    dispatch_semaphore_wait(avail, DISPATCH_TIME_FOREVER);
    RX_DISPATCH_RELEASE(avail);
    return result;
}


- (void) wait {
    [self get];
}


- (void) runLoopWait
{
    // The current thread MUST have a run loop and at least one event source!
    // This is difficult to verfy in this method - thus this is simply
    // a prerequisite which must be ensured by the client. If there is no
    // event source, the run lopp may quickly return with the effect that the
    // while loop will "busy wait".
    
    NSThread* thread = [NSThread currentThread];
    self.then(^id(id result) {
        [@"" performSelector:@selector(self) onThread:thread withObject:nil waitUntilDone:NO];
        return nil;
    }, ^id(NSError* error) {
        [@"" performSelector:@selector(self) onThread:thread withObject:nil waitUntilDone:NO];
        return nil;
    });
    NSRunLoop* runLoop = [NSRunLoop currentRunLoop];
    while (1) {
        if (!self.isPending) {
            break;
        }
        [runLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate distantFuture]];
    }
}



- (void) bind:(RXPromise*) other {
    if (dispatch_get_specific(QueueID) == s_sync_queue_id) {
        [self synced_bind:other];
    }
    else {
        dispatch_barrier_async(s_sync_queue, ^{
            [self synced_bind:other];
        });
    }
}

// Promise `other` will be retained and released only until after `other` will be
// resolved.
- (void) synced_bind:(RXPromise*) other {
    assert(other != nil);
    assert(dispatch_get_specific(QueueID) == s_sync_queue_id);

    if (_state == Cancelled) {
        [other cancelWithReason:_result];
        return;
    }
    if (_state != Pending) {
        return;
    }
    RXPromise_StateAndResult ps = [other synced_peakStateAndResult];
    switch (ps.state) {
        case Fulfilled:
            [self synced_fulfillWithValue:ps.result];
            break;
        case Rejected:
            [self synced_rejectWithReason:ps.result];
            break;
        case Cancelled:
            [self synced_cancelWithReason:ps.result];
            break;
        default: {
            __weak RXPromise* weakSelf = self;
            [other registerWithQueue:s_sync_queue onSuccess:^id(id result) {
                //const char* queue_id = (const char*)dispatch_get_specific(QueueID);
                assert(dispatch_get_specific(QueueID) == s_sync_queue_id);
                RXPromise* strongSelf = weakSelf;
                [strongSelf synced_fulfillWithValue:result];  // §2.2: if self is fulfilled, fulfill promise with the same value
                return nil;
            } onFailure:^id(NSError *error) {
                //const char* queue_id = (const char*)dispatch_get_specific(QueueID);
                assert(dispatch_get_specific(QueueID) == s_sync_queue_id);
                RXPromise* strongSelf = weakSelf;
                [strongSelf synced_rejectWithReason:error];   // §2.3: if self is rejected, reject promise with the same value.
                return nil;
            } returnPromise:NO];
        }
    }
    __weak RXPromise* weakSelf = self;
    __weak RXPromise* weakOther = other;
    [self registerWithQueue:s_sync_queue onSuccess:nil onFailure:^id(NSError *error) {
        //const char* queue_id = (const char*)dispatch_get_specific(QueueID);
        assert(dispatch_get_specific(QueueID) == s_sync_queue_id);
        RXPromise* strongSelf = weakSelf;
        if (strongSelf) {
            if (strongSelf->_state == Cancelled) {
                RXPromise* strongOther = weakOther;
                [strongOther synced_cancelWithReason:error];
            }
        }
        return error;
    } returnPromise:NO];
    
}




#pragma mark -


+(RXPromise*) all:(NSArray*)promises
{
    RXPromise* promise = [RXPromise new];
    __block int count = (int)[promises count];
    if (count == 0) {
        [promise rejectWithReason:@"parameter error"];
        return promise;
    }
    promise_completionHandler_t onSuccess = ^(id result){
        --count;
        if (count == 0) {
            [promise fulfillWithValue:promises];
        }
        return result;
    };
    promise_errorHandler_t onError = ^(NSError* error) {
        [promise rejectWithReason:error];
        return error;
    };

    for (RXPromise* p in promises) {
        p.thenOn(s_sync_queue, onSuccess, onError);
    }
    promise.thenOn(s_sync_queue, nil, ^id(NSError*error){
        for (RXPromise* p in promises) {
            [p cancelWithReason:error];
        }
        return error;
    });
    
    return promise;
}


+ (RXPromise*) any:(NSArray*)promises
{
    RXPromise* promise = [RXPromise new];
    __block int count = (int)[promises count];
    if (count == 0) {
        [promise rejectWithReason:@"parameter error"];
        return promise;
    }
    promise_completionHandler_t onSuccess = ^(id result){
        for (RXPromise* p in promises) {
            [p cancel];
        }
        [promise fulfillWithValue:result];
        return result;
    };
    promise_errorHandler_t onError = ^(NSError* error) {
        --count;
        if (count == 0) {
            [promise rejectWithReason:@"none succeeded"];
        }
        return error;
    };
    
    for (RXPromise* p in promises) {
        p.thenOn(s_sync_queue, onSuccess, onError);
    }
    promise.thenOn(s_sync_queue, nil, ^id(NSError*error){
        for (RXPromise* p in promises) {
            [p cancelWithReason:error];
        }
        return error;
    });
    
    return promise;
}




#pragma mark -

- (NSString*) description {
    __block NSString* desc;
    dispatch_sync(s_sync_queue, ^{
        desc = [self rxp_descriptionLevel:0];
    });
    return desc;
}

- (NSString*) debugDescription {
    return [self rxp_descriptionLevel:0];
}


- (NSString*) rxp_descriptionLevel:(int)level {
    NSString* indent = [NSString stringWithFormat:@"%*s",4*level,""];
    NSMutableString* desc = [[NSMutableString alloc] initWithFormat:@"%@<%@:%p> { %@ }",
                             indent,
                             NSStringFromClass([self class]), (__bridge void*)self,
                             ( (_state == Fulfilled)?[NSString stringWithFormat:@"fulfilled with value: %@", _result]:
                              (_state == Rejected)?[NSString stringWithFormat:@"rejected with reason: %@", _result]:
                              (_state == Cancelled)?[NSString stringWithFormat:@"cancelled with reason: %@", _result]
                              :@"pending")
                             ];
    void* key = (__bridge void*)(self);
    auto range = s_assocs.equal_range(key);
    if (range.first != range.second) {
        [desc appendString:[NSString stringWithFormat:@", children: [\n"]];
        while (range.first != range.second) {
            RXPromise* p = (*(range.first)).second;
            [desc appendString:p ? [p rxp_descriptionLevel:level+1] : @"<nil>"];
            [desc appendString:@"\n"];
            ++range.first;
        }
        [desc appendString:[NSString stringWithFormat:@"%@]", indent]];
    }
    
    return desc;
}

@end


#pragma mark - RXResolver

@implementation RXPromise (RXResolver)
- (void) rxp_resolvePromise:(RXPromise*)promise
{
    assert(dispatch_get_specific(QueueID) == s_sync_queue_id);
    [promise synced_bind:self];
}
@end

@implementation NSObject (RXResolver)
- (void) rxp_resolvePromise:(RXPromise*)promise {
    // This is not strict according the spec:
    // If value is an object we require it to be a `thenable` or we must
    // reject the promise with an appropriate error.
    // However this API supports only objects, that is, our value is always
    // an `id` and not a struct or other primitive C type or a C++ class, etc.
    // We also do not support `thenables`.
    // So, we handle values which are not RXPromises and not NSErrors as if
    // they were non-objects and simply fulfill the promise with this value.
    [promise fulfillWithValue:self]; // forward result
}

@end

@implementation NSError (RXResolver)

- (void) rxp_resolvePromise:(RXPromise*)promise {
    [promise rejectWithReason:self];
}

@end


