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
#import "RXPromise+Private.h"
#import <CoreData/CoreData.h>
#import <objc/runtime.h>
#include <dispatch/dispatch.h>
#include <cassert>
#include <cstdio>

// Set default logger serverity to "Error" (logs only errors)
#if !defined (DEBUG_LOG)
#define DEBUG_LOG 1
#endif
#import "utility/DLog.h"


/**
 See <http://promises-aplus.github.io/promises-spec/>  for specification.
 */




@interface NSError (RXResolver)
- (void) rxp_synced_resolvePromise:(RXPromise*)promise;
@end

@interface NSObject (RXResolver)
- (void) rxp_synced_resolvePromise:(RXPromise*)promise;
@end

@interface RXPromise (RXResolver)
- (void) rxp_synced_resolvePromise:(RXPromise*)promise;
@end


#pragma mark ExecutionContext - NSThread
@interface NSThread (RXPromise)
- (void) rxp_dispatchBlock:(void(^)())block;
- (void) rxp_performBlock:(void(^)())block;
@end

@implementation NSThread (RXPromise)
- (void) rxp_dispatchBlock:(void(^)())block {
    if (block) {
        [self performSelector:@selector(rxp_performBlock:) onThread:self withObject:block waitUntilDone:NO];
    }
}
- (void) rxp_performBlock:(void(^)())block {
    if (block) {
        block();
    }
}

@end


#pragma mark ExecutionContext - NSManagedObjectContext
@interface NSManagedObjectContext (RXPromise)
- (void) rxp_dispatchBlock:(void(^)())block;
@end

@implementation NSManagedObjectContext (RXPromise)
- (void) rxp_dispatchBlock:(void(^)())block {
    [self performBlock:block];
}
@end


#pragma mark ExecutionContext - NSOperationQueue
@interface NSOperationQueue (RXPromise)
- (void) rxp_dispatchBlock:(void(^)())block;
@end

@implementation NSOperationQueue (RXPromise)
- (void) rxp_dispatchBlock:(void(^)())block {
    [self addOperationWithBlock:block];
}
@end



rxpromise::shared Shared;

#pragma mark -
namespace {
    
    DISPATCH_RETURNS_RETAINED
    NSError* makeTimeoutError() {
        return [[NSError alloc] initWithDomain:@"RXPromise" code:-1001 userInfo:@{NSLocalizedFailureReasonErrorKey: @"timeout"}];
    }
    
    
    DISPATCH_RETURNS_RETAINED
    inline dispatch_queue_t createHandlerQueue(bool suspended, void* tag)  {
        char buffer[64];
        snprintf(buffer, sizeof(buffer),"RXPromise.handler_queue-%p", tag);
        dispatch_queue_t handler_queue = dispatch_queue_create(buffer, NULL);
        assert(handler_queue);
        dispatch_set_target_queue(handler_queue, Shared.sync_queue);
        if (suspended) {
            dispatch_suspend(handler_queue);
        }
        return handler_queue;
    }
 
}



#pragma mark - RXPromise

@interface RXPromise ()
@property (nonatomic) id result;
@property (nonatomic, readwrite) RXPromise* parent;
@end



@implementation RXPromise {
    RXPromise*          _parent;
    dispatch_queue_t    _handler_queue;  // a serial queue, uses target queue: s_sync_queue
    id                  _result;
    RXPromise_State     _state;
}
@synthesize result = _result;
@synthesize parent = _parent;



- (void) dealloc {
    DLogInfo(@"dealloc: %p", (__bridge void*)self);
    if (_handler_queue) {
        if (_state == Pending) {
            DLogWarn(@"handlers not signaled");
            dispatch_resume(_handler_queue);
        }
    }
    void const* key = (__bridge void const*)(self);
    if (dispatch_get_specific(rxpromise::shared::QueueID) == rxpromise::shared::sync_queue_id) {
        Shared.assocs.erase(key);
    } else {
        dispatch_barrier_sync(Shared.sync_queue, ^{
            Shared.assocs.erase(key);
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


- (RXPromise*) root {
    RXPromise* root = self;
    while (root.parent) {
        root = root.parent;
    }
    return root;
}


- (RXPromise_StateAndResult) peakStateAndResult {
    if (dispatch_get_specific(rxpromise::shared::QueueID) == rxpromise::shared::sync_queue_id) {
        return {_state, _result};
    }
    else {
        __block RXPromise_StateAndResult result;
        dispatch_sync(Shared.sync_queue, ^{
            result.result = _result;
            result.state = _state;
        });
        return result;
    }
}


- (RXPromise_StateAndResult) synced_peakStateAndResult {
    assert(dispatch_get_specific(rxpromise::shared::QueueID) == rxpromise::shared::sync_queue_id);
    return {_state, _result};
}

- (id) synced_peakResult {
    assert(dispatch_get_specific(rxpromise::shared::QueueID) == rxpromise::shared::sync_queue_id);
    assert(_state != Pending);
    return _result;
}



- (void) cancel {
    [self cancelWithReason:@"cancelled"];
}

- (void) cancelWithReason:(id)reason {
    dispatch_barrier_async(Shared.sync_queue, ^{  // async, in order to be less prone to dead locks
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
    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, Shared.sync_queue);
    dispatch_source_set_event_handler(timer, ^{
        dispatch_source_cancel(timer); // one shot timer
        [self rejectWithReason:makeTimeoutError()];
    });
    dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(timeout * NSEC_PER_SEC)),
                              DISPATCH_TIME_FOREVER /*one shot*/, 0 /*_leeway*/);
    dispatch_resume(timer);

    id executionContext = Shared.sync_queue;
    [self registerWithExecutionContext:executionContext onSuccess:^id(id result) {
        dispatch_source_cancel(timer);
        return nil;
    }  onFailure:^id(NSError *error) {
        dispatch_source_cancel(timer);
        return nil;
    }
    returnPromise:NO];

    return self;
}



- (void) synced_resolveWithResult:(id)result {
    assert(dispatch_get_specific(rxpromise::shared::QueueID) == rxpromise::shared::sync_queue_id);
    if (result == nil) {
        [self synced_fulfillWithValue:nil];
    }
    else {
        [result rxp_synced_resolvePromise:self];
    }
}


- (void) synced_fulfillWithValue:(id)result {
    assert(dispatch_get_specific(rxpromise::shared::QueueID) == rxpromise::shared::sync_queue_id);
    if (_state != Pending) {
        return;
    }
    _result = result;
    _state = Fulfilled;
    if (_handler_queue) {
        dispatch_resume(_handler_queue);
    }
}


- (void) synced_rejectWithReason:(id)reason {
    assert(dispatch_get_specific(rxpromise::shared::QueueID) == rxpromise::shared::sync_queue_id);
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
    }
}


- (void) synced_cancelWithReason:(id)reason {
    assert(dispatch_get_specific(rxpromise::shared::QueueID) == rxpromise::shared::sync_queue_id);
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
        }
    }
    else {
        // We cancelled the promise at a time as it already was resolved.
        // That means, the _handler_queue is gone and we cannot forward the
        // cancellation event to any child ("returnedPromise") anymore.
        // In order to cancel the possibly already resolved children promises,
        // we need to send cancel to each promise in the children list:
        void const* key = (__bridge void const*)(self);
        auto range = Shared.assocs.equal_range(key);
        while (range.first != range.second) {
            DLogDebug(@"%p forwarding cancel to %p", key, (__bridge void*)((*(range.first)).second));
            [(*(range.first)).second cancelWithReason:reason];
            ++range.first;
        }
        Shared.assocs.erase(key);
    }
}


// Registers success and failure handlers.
// The receiver will be retained and only released when the receiver will be
// resolved (see "Requirements for an asynchronous result provider").
// Returns a new promise which represents the return values of the handler
// blocks.
- (instancetype) registerWithExecutionContext:(id)executionContext
                         onSuccess:(promise_completionHandler_t)onSuccess
                         onFailure:(promise_errorHandler_t)onFailure
                     returnPromise:(BOOL)returnPromise
{
    RXPromise* returnedPromise = returnPromise ? ([[[self class] alloc] init]) : nil;
    returnedPromise.parent = self;
    __weak RXPromise* weakReturnedPromise = returnedPromise;
    __block RXPromise* blockSelf = self;
    if (executionContext == nil) {
        executionContext = Shared.default_concurrent_queue;
    }
    dispatch_block_t registerBlock = ^{
        assert(dispatch_get_specific(rxpromise::shared::QueueID) == rxpromise::shared::sync_queue_id);
        if (_handler_queue == nil) {
            _handler_queue = createHandlerQueue(_state == Pending, (__bridge void*)self);
        }
        // Finally, *enqueue* a wrapper block which eventually gets invoked when the
        // promise will be resolved:
        dispatch_async(_handler_queue, ^{
            // The continuation has been fired!
            assert(executionContext);
            // Get the state of the promise:
            assert(dispatch_get_specific(rxpromise::shared::QueueID) == rxpromise::shared::sync_queue_id);
            RXPromise_StateT promise_state = blockSelf->_state;
            __strong id promise_result = blockSelf->_result;
            
            dispatch_block_t handlerBlock = ^{
                // The handler block will be executed in the specified execution
                // context - it can be Shared.sync_queue, too - when invoked internally!
                // If the execution context equals the Shared.sync_queue, the block
                // must be enqueued with a barrier! (implementation details)
                @autoreleasepool {
                    assert(promise_state != Pending);
                    RXPromise_StateT state = promise_state;
                    __strong id result = promise_result;
                    if (state == Fulfilled && onSuccess) {
                        result = onSuccess(blockSelf->_result);
                    }
                    else if (state != Fulfilled && onFailure) {
                        result = onFailure(blockSelf->_result);
                    }
                    RXPromise* strongReturnedPromise = weakReturnedPromise;
                    if (strongReturnedPromise) {
                        assert(result != strongReturnedPromise); // @"cyclic promise error");
                        if (state == Cancelled) {
                            [strongReturnedPromise cancelWithReason:result];
                        }
                        else {
                            DLogInfo(@"%p add child %p", (__bridge void*)(blockSelf), (__bridge void*)(strongReturnedPromise));
                            if (executionContext == Shared.sync_queue) {
                                // prerequiste: the block must have been enqueued with a barrier!
                                Shared.assocs.emplace((__bridge void*)(blockSelf), weakReturnedPromise);
                            } else {
                                void const* parent_pointer = (__bridge void*)(blockSelf);
                                dispatch_barrier_async(Shared.sync_queue, ^{  // TODO:
                                    Shared.assocs.emplace(parent_pointer, weakReturnedPromise);
                                }); 
                            }
                            //  §2.2: if parent is fulfilled, fulfill the "returned promise" with the same value
                            //  §2.3: if parent is rejected, reject the "returned promise" with the same value.
                            //
                            // There are four cases how the "returned promise" (child) will be resolved:
                            // 1. result isKindOfClass NSError   -> rejected with reason error
                            // 2. result isKindOfClass RXPromise -> fulFilled with promise
                            // 3. result equals nil              -> fulFilled with nil
                            // 4  result is any other object     -> fulFilled with value
                            //
                            // Note: if parent is cancelled, the "returned promise" will NOT be cancelled - it just adopts the error reason!
                            if (result && [result isKindOfClass:[NSError class]]) {
                                [strongReturnedPromise rejectWithReason:result];
                            }
                            else if (result && [result isKindOfClass:[RXPromise class]]) {
                                [strongReturnedPromise bind:result];
                            }
                            else {
                                [strongReturnedPromise fulfillWithValue:result];
                            }
                        }
                    }
                    else {
                        DLogInfo(@"parent's  %p returned promisze %p died", (__bridge void*)(blockSelf), (__bridge void*)(strongReturnedPromise));
                    }
                    blockSelf = nil;
                }//@autoreleasepool
            };
            
            if (executionContext == Shared.default_concurrent_queue) {
                // If the continuation has been registered with `then`, we run
                // the handler is parallel:
                dispatch_async(executionContext, handlerBlock);
            }
            else if ([executionContext conformsToProtocol:@protocol(OS_dispatch_queue)]) {
                // If the continuation has been registered with `thenOn:` and when the
                // execution context is a dispatch queue, we run the handler serially:
                dispatch_barrier_async(executionContext, handlerBlock);
            }
            else {
                // Otherwise, the execution context is not a dispatch_queue. Dispatch
                // to the corresponding execution context:
                [executionContext rxp_dispatchBlock:handlerBlock];
            }
        });
    };
    
    if (dispatch_get_specific(rxpromise::shared::QueueID) == rxpromise::shared::sync_queue_id) {
        // when entering here, we need to ensure the block has been dispatched with a barrier!
        // (currently, this path only gets executed when invoking `resolveWithResult:` and `bind:`)
        registerBlock();
    }
    else {
        assert(Shared.sync_queue);
        dispatch_barrier_sync(Shared.sync_queue, registerBlock);
    }
    return returnedPromise;
}


- (then_block_t) then {
    return ^RXPromise*(promise_completionHandler_t onSuccess, promise_errorHandler_t onFailure) {
        return [self registerWithExecutionContext:nil onSuccess:onSuccess onFailure:onFailure returnPromise:YES];
    };
}


- (then_on_block_t) thenOn {
    return ^RXPromise*(id executionContext, promise_completionHandler_t onSuccess, promise_errorHandler_t onFailure) {
        return [self registerWithExecutionContext:executionContext onSuccess:onSuccess onFailure:onFailure returnPromise:YES];
    };
}


- (then_on_main_block_t) thenOnMain {
    return ^RXPromise*(promise_completionHandler_t onSuccess, promise_errorHandler_t onFailure) {
        return [self registerWithExecutionContext:dispatch_get_main_queue() onSuccess:onSuccess onFailure:onFailure returnPromise:YES];
    };
}

- (catch_on_block_t) catchOn {
    return ^RXPromise*(id executionContext, promise_errorHandler_t onFailure) {
        return [self registerWithExecutionContext:executionContext onSuccess:nil onFailure:onFailure returnPromise:YES];
    };
}

- (catch_on_main_block_t) catchOnMain {
    return ^RXPromise*(promise_errorHandler_t onFailure) {
        return [self registerWithExecutionContext:dispatch_get_main_queue() onSuccess:nil onFailure:onFailure returnPromise:YES];
    };
}



#pragma mark -

- (id) get {
    return [self getWithTimeout:-1.0];  // negative means infinitive
}


- (id) getWithTimeout:(NSTimeInterval)timeout
{
    assert(dispatch_get_specific(rxpromise::shared::QueueID) != rxpromise::shared::sync_queue_id); // Must not execute on the private sync queue!
    
    __block id result;
    __block dispatch_semaphore_t sem = NULL;
    dispatch_sync(Shared.sync_queue, ^{
        if (_state != Pending) {
            result = _result;
        } else {
            sem = dispatch_semaphore_create(0);
            if (_handler_queue == nil) {
                _handler_queue = createHandlerQueue(_state == Pending, (__bridge void*)self);
            }
            dispatch_async(_handler_queue, ^{
                dispatch_semaphore_signal(sem);
            });
        }
    });
    if (sem) {
        // result was not yet availbale: queue a handler
        dispatch_time_t t = timeout < 0 ? DISPATCH_TIME_FOREVER : dispatch_time(DISPATCH_TIME_NOW, (int64_t)(timeout * NSEC_PER_SEC));
        if (dispatch_semaphore_wait(sem, t) == 0) { // wait until handler_queue will be resumed ...
            dispatch_sync(Shared.sync_queue, ^{  // safely retrieve _result
                result = _result;
            });
        }
        else {
            result = makeTimeoutError();
        }
    }
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
    
    static CFRunLoopSourceContext context;

    CFRunLoopRef runLoop = CFRunLoopGetCurrent();
    CFRunLoopSourceRef runLoopSource = CFRunLoopSourceCreate(NULL, 0, &context);
    CFRunLoopAddSource(runLoop, runLoopSource, kCFRunLoopDefaultMode);
    
    self.then(^id(id result) {
        CFRunLoopStop(runLoop);
        return nil;
    }, ^id(NSError* error) {
        CFRunLoopStop(runLoop);
        return nil;
    });
    while (1) {
        if (!self.isPending) {
            break;
        }
        CFRunLoopRun();
    }
    CFRunLoopRemoveSource(runLoop, runLoopSource, kCFRunLoopDefaultMode);
    CFRelease(runLoopSource);
}



- (void) bind:(RXPromise*) other
{
    if (dispatch_get_specific(rxpromise::shared::QueueID) == rxpromise::shared::sync_queue_id) {
        [self synced_bind:other];
    }
    else {
        dispatch_barrier_async(Shared.sync_queue, ^{
            [self synced_bind:other];
        });
    }
}


// The receiver will adopt the state of the promise `other`.
//
// Promise `other` will be retained and released only until after `other` will be
// resolved.
//
// Caution: if _other_ is or will be cancelled, the receiver (the "bound promise")
// will be cancelled as well! Unlike in a parent-child relationship, method `bind`
// will make the receiver not just adopt the error reason - but also adopt its
// cancellation!
- (void) synced_bind:(RXPromise*) other {
    assert(other != nil);
    assert(dispatch_get_specific(rxpromise::shared::QueueID) == rxpromise::shared::sync_queue_id);

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
            [other registerWithExecutionContext:Shared.sync_queue onSuccess:^id(id result) {
                assert(dispatch_get_specific(rxpromise::shared::QueueID) == rxpromise::shared::sync_queue_id);
                RXPromise* strongSelf = weakSelf;
                [strongSelf synced_fulfillWithValue:result];
                return nil;
            } onFailure:^id(NSError *error) {
                assert(dispatch_get_specific(rxpromise::shared::QueueID) == rxpromise::shared::sync_queue_id);
                RXPromise* strongSelf = weakSelf;
                if (other.isCancelled)
                    [strongSelf synced_cancelWithReason:error];
                else {
                    [strongSelf synced_rejectWithReason:error];
                }
                return nil;
            } returnPromise:NO];
        }
    }
    __weak RXPromise* weakSelf = self;
    __weak RXPromise* weakOther = other;
    [self registerWithExecutionContext:Shared.sync_queue onSuccess:nil onFailure:^id(NSError *error) {
        assert(dispatch_get_specific(rxpromise::shared::QueueID) == rxpromise::shared::sync_queue_id);
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

- (NSString*) description {
    __block NSString* desc;
    dispatch_sync(Shared.sync_queue, ^{
        desc = [self rxp_descriptionLevel:0];
    });
    return desc;
}

- (NSString*) debugDescription {
    return [self rxp_descriptionLevel:0];
}


- (NSString*) rxp_descriptionLevel:(int)level {
    NSString* indent = [NSString stringWithFormat:@"%*s",4*level,""];
    NSMutableString* desc = [[NSMutableString alloc] initWithFormat:@"%@<%@:%p> %ld { %@ }",
                             indent,
                             NSStringFromClass([self class]), (__bridge void*)self,
                             CFGetRetainCount((__bridge CFTypeRef)self),
                             ( (_state == Fulfilled)?[NSString stringWithFormat:@"fulfilled with value: %@", _result]:
                              (_state == Rejected)?[NSString stringWithFormat:@"rejected with reason: %@", _result]:
                              (_state == Cancelled)?[NSString stringWithFormat:@"cancelled with reason: %@", _result]
                              :@"pending")
                             ];
    void* key = (__bridge void*)(self);
    auto range = Shared.assocs.equal_range(key);
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

- (NSString*) rxp_debugSummary {
    NSString* result = [_result description];
    NSMutableString* summary = [[NSMutableString alloc] initWithFormat:@"<%@>{%@}",
                                NSStringFromClass([self class]),
                                ( (_state == Fulfilled)?[NSString stringWithFormat:@"fulfilled with value: %@", result]:
                                 (_state == Rejected)?[NSString stringWithFormat:@"rejected with reason: %@", result]:
                                 (_state == Cancelled)?[NSString stringWithFormat:@"cancelled with reason: %@", result]
                                 :@"pending")
                                ];
    return summary;
}

@end


#pragma mark - RXPromise (RXResolver)

@implementation RXPromise (RXResolver)
- (void) rxp_synced_resolvePromise:(RXPromise*)promise
{
    assert(dispatch_get_specific(rxpromise::shared::QueueID) == rxpromise::shared::sync_queue_id);
    [promise synced_bind:self];
}
@end

@implementation NSObject (RXResolver)
- (void) rxp_synced_resolvePromise:(RXPromise*)promise {
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

- (void) rxp_synced_resolvePromise:(RXPromise*)promise {
    [promise rejectWithReason:self];
}

@end




#pragma mark - RXPromiseD


@interface RXPromiseD : RXPromise
- (instancetype) initWithDeallocHandler:(void(^)())deallocHandler;
@end

@implementation RXPromiseD {
    dispatch_block_t _deallocHandler;
}


- (instancetype) initWithDeallocHandler:(void(^)())deallocHandler
{
    self = [super init];
    if (self) {
        _deallocHandler = [deallocHandler copy];
    }
    return self;
}

- (void) dealloc {
    if (_deallocHandler) {
        _deallocHandler();
    }
}

@end




#pragma mark - RXPromise (Deferred)


@implementation RXPromise (Deferred)

#pragma mark Convenient Class Methods

+ (instancetype) promiseWithResult:(id)result {
    RXPromise* promise = [[self alloc] initWithResult:result];
    return promise;
}

+ (RXPromise*) promiseWithDeallocHandler:(void(^)())deallocHandler {
    RXPromise* promise = [[RXPromiseD alloc] initWithDeallocHandler:deallocHandler];
    return promise;
}

+ (instancetype)promiseWithTask:(id(^)(void))task {
    assert(task);
    RXPromise* promise = [[self alloc] init];
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        [promise resolveWithResult:task()];
    });
    return promise;
}


+ (instancetype)promiseWithQueue:(dispatch_queue_t)queue task:(id(^)(void))task {
    assert(queue);
    assert(task);
    RXPromise* promise = [[self alloc] init];
    dispatch_async(queue, ^{
        [promise resolveWithResult:task()];
    });
    return promise;
}

#pragma mark Initializer

// 1. Designated Initializer
- (instancetype)init {
    self = [super init];
    DLogInfo(@"create: %p", (__bridge void*)self);
    return self;
}

// 2. Designated Initializer
- (instancetype)initWithResult:(id)result {
    assert(![result isKindOfClass:[RXPromise class]]);
    DLogInfo(@"create: %p", (__bridge void*)self);
    self = [super init];
    if (self) {
        _result = result;
        _state = [result isKindOfClass:[NSError class]] ? Rejected : Fulfilled;
    }
    return self;
}

#pragma mark Resolver

- (void) resolveWithResult:(id)result {
    dispatch_barrier_async(Shared.sync_queue, ^{
        [self synced_resolveWithResult:result];
    });
}


- (void) fulfillWithValue:(id)value {
    assert(![value isKindOfClass:[NSError class]]);
    if (dispatch_get_specific(rxpromise::shared::QueueID) == rxpromise::shared::sync_queue_id) {
        [self synced_fulfillWithValue:value];
    }
    else {
        dispatch_barrier_async(Shared.sync_queue, ^{
            [self synced_fulfillWithValue:value];
        });
    }
}


- (void) rejectWithReason:(id)reason {
    if (dispatch_get_specific(rxpromise::shared::QueueID) == rxpromise::shared::sync_queue_id) {
        [self synced_rejectWithReason:reason];
    }
    else {
        dispatch_barrier_async(Shared.sync_queue, ^{
            [self synced_rejectWithReason:reason];
        });
    }
}





@end