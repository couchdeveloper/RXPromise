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
//#define DEBUG_LOG_MIN 4   //enable this in order to log verbosely
#import "utility/DLog.h"
#include <stdio.h>



/**
 See <http://promises-aplus.github.io/promises-spec/>  for specification.
 
 */

@interface  NSObject (RXIntrospection)
@end
@implementation NSObject (RXIntrospection)
- (BOOL) isNSBlock {
    return [self isKindOfClass:NSClassFromString(@"NSBlock")];
}
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
    dispatch_queue_t        _sync_queue;        // a serial queue, uses target queue: s_sync_queue_parent
    dispatch_queue_t        _handler_queue;     // a serial queue, uses target queue: s_handler_queue_parent
    dispatch_semaphore_t    _avail;
    NSMutableArray*         _progressHandlers;
    NSMutableArray*         _promises;
    BOOL                    _isFulfilled;
    BOOL                    _isRejected;
    BOOL                    _isCancelled;
}
@synthesize progressHandlers = _progressHandlers;
@synthesize promises = _promises;


static dispatch_queue_t s_sync_queue_parent;
static dispatch_queue_t s_handler_queue_parent;


- (id)init
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        s_sync_queue_parent = dispatch_queue_create("s_sync_queue_parent", NULL);
    });
    
    DLogInfo(@"init: %p", (__bridge void*)self);
    self = [super init];
    if (self) {
        _avail = dispatch_semaphore_create(0);
        char buffer[64];
        snprintf(buffer, sizeof(buffer),"RXPromise_sync_queue-%p", (__bridge void*)self);
        _sync_queue = dispatch_queue_create(buffer, DISPATCH_QUEUE_SERIAL);
        assert(_sync_queue);
        dispatch_set_target_queue(_sync_queue, s_sync_queue_parent);
        dispatch_queue_set_specific(_sync_queue, "sync_queue.id", [self syncQueueToken], NULL);
    }
    return self;
}

- (void) dealloc {
    DLogInfo(@"dealloc: %p", (__bridge void*)self);
    dispatch_release(_avail);
    dispatch_release(_sync_queue);
    if (_handler_queue) {
        DLogWarn(@"handler queue has not been resumed - probably the promise hasn't been signaled");
        dispatch_resume(_handler_queue);
        dispatch_release(_handler_queue);
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
    assert(dispatch_get_specific("sync_queue.id") == [self syncQueueToken]);
    if (_progressHandlers == nil) {
        _progressHandlers = [[NSMutableArray alloc] initWithCapacity:1];
    }
    return _progressHandlers;
}

- (NSMutableArray*) promises
{
    assert(dispatch_get_specific("sync_queue.id") == [self syncQueueToken]);
    if (_promises == nil) {
        _promises = [[NSMutableArray alloc] initWithCapacity:1];
    }
    return _promises;
}



-(void*) syncQueueToken {
    return s_sync_queue_parent;
}

- (BOOL) isPending {
    if (_sync_queue == NULL || dispatch_get_specific("sync_queue.id") == [self syncQueueToken]) {
        return !(_isFulfilled || _isRejected || _isCancelled);
    }
    else {
        __block BOOL result;
        dispatch_sync(_sync_queue, ^{
            result = !(_isFulfilled || _isRejected || _isCancelled) ;
        });
        return result;
    }
}

- (BOOL) isFulfilled {
    if (_sync_queue == NULL || dispatch_get_specific("sync_queue.id") == [self syncQueueToken]) {
        return _isFulfilled;
    }
    else {
        __block BOOL result;
        dispatch_sync(_sync_queue, ^{ result = _isFulfilled; });
        return result;
    }
}

- (BOOL) isRejected {
    if (_sync_queue == NULL || dispatch_get_specific("sync_queue.id") == [self syncQueueToken]) {
        return _isRejected;
    }
    else {
        __block BOOL result;
        dispatch_sync(_sync_queue, ^{ result = _isRejected; });
        return result;
    }
}

- (BOOL) isCancelled {
    if (_sync_queue == NULL || dispatch_get_specific("sync_queue.id") == [self syncQueueToken]) {
        return _isCancelled;
    }
    else {
        __block BOOL result;
        dispatch_sync(_sync_queue, ^{ result = _isCancelled; });
        return result;
    }
}


#pragma mark - Resolver

- (void) fulfillWithValue:(id)result {
    assert(![result isKindOfClass:[NSError class]]);
    dispatch_once(&_once_result, ^{
        assert(_sync_queue);
        // dispatch a fulfill signal on the sync queue:
        dispatch_async(_sync_queue, ^{
            DLogInfo(@"self: %@, exec on sync_queue: `fulfillWithValue:`%@", self, result);
            _result = result;
            self.isFulfilled = YES;
            if (_handler_queue) {
                dispatch_resume(_handler_queue);
                dispatch_release(_handler_queue), _handler_queue = NULL;
            }
            dispatch_semaphore_signal(_avail);
        });
    });
}

- (void) rejectWithReason:(id)reason {
    if (![reason isKindOfClass:[NSError class]]) {
        reason = [[NSError alloc] initWithDomain:@"RXPromise" code:-1000 userInfo:@{@"reason": reason}];
    }
    dispatch_once(&_once_result, ^{
        assert(_sync_queue);
        // dispatch a rejected signal on the sync queue:
        dispatch_async(_sync_queue, ^{
            DLogInfo(@"self: %@, exec on sync_queue: `rejectWithReason:`%@", self, reason);
            _result = reason;
            self.isRejected = YES;
            if (_handler_queue) {
                dispatch_resume(_handler_queue);
                dispatch_release(_handler_queue), _handler_queue = NULL;
            }
            dispatch_semaphore_signal(_avail);
        });
    });
}

- (void) cancelWithReason:(id)reason {
    if (![reason isKindOfClass:[NSError class]]) {
        reason = [[NSError alloc] initWithDomain:@"RXPromise" code:-1 userInfo:@{@"reason": reason}];
    }
    dispatch_once(&_once_result, ^{
        assert(_sync_queue);
        // dispatch a cancel signal on the sync queue:
        dispatch_async(_sync_queue, ^{
            DLogInfo(@"self: %@, exec on sync_queue: `cancelWithReason:`%@", self, reason);
            _result = reason;
            self.isCancelled = YES;
            self.isRejected = YES;
            if (_handler_queue) {
                dispatch_resume(_handler_queue);
                dispatch_release(_handler_queue), _handler_queue = NULL;
            }
            dispatch_semaphore_signal(_avail);
        });
    });
    dispatch_async(_sync_queue, ^{
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
    dispatch_async(_sync_queue, ^{
        for (progressHandler_t block in _progressHandlers) {
            block(progress);
        }
    });
}




#pragma mark -


- (void) resolveReturnedPromise:(RXPromise*)returnedPromise withResult:(id)value
{
    assert(dispatch_get_specific("sync_queue.id") == [self syncQueueToken]);
    assert(_isFulfilled || _isRejected);

    DLogInfo(@"returned promise: %@, value: %@", returnedPromise, value);
    
    if (value == returnedPromise) {
        NSError* error = [NSError errorWithDomain:@"RXPromise" code:-2 userInfo:@{NSLocalizedDescriptionKey: @"TypeError"}];
        [returnedPromise rejectWithReason:error];
    }
    else if ([value isKindOfClass:[RXPromise class]]) {
        RXPromise* promise = (RXPromise*)value;
        [promise then:^id(id result) {
            [returnedPromise fulfillWithValue:result];
            return nil; // TODO: ???
        }
         errorHandler:^id(NSError* error) {
            [returnedPromise rejectWithReason:promise.get];
             return nil;  // TODO: ???
        }];
    }
    else if ([value isKindOfClass:[NSError class]]) {
        [returnedPromise rejectWithReason:value]; // forward error
    }
    else {
#if defined (HANDLE_THENABLE)
        if ([value respondsToSelector:@selector(then:errorHandler:)]) {
            [value then:^id(id y) {
                if (value == y) {
                    [returnedPromise fulfillWithValue:value];
                }
                else {
                    [self resolveReturnedPromise:returnedPromise withResult:y];
                }
                return nil;
            }
           errorHandler:^id(NSError *error) {
               [returnedPromise rejectWithReason:error];
               return nil;
           }];
        }
        else {
            // We should reach here if value is either `nil`, is an `NSError`, or
            // does not respond to a then:errorHandler: message.
            [returnedPromise fulfillWithValue:value]; // forward result
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
        [returnedPromise fulfillWithValue:value]; // forward result
#endif
    }
}


- (void) resolveReturnedPromise:(RXPromise*)returnedPromise
                     completion:(id(^)(id result))completionHandler
                          error:(id(^)(NSError* error))errorHandler
{
    assert(dispatch_get_specific("sync_queue.id") == [self syncQueueToken]);
    assert(_isFulfilled || _isRejected);
    
    DLogInfo(@"returned promise: %@", returnedPromise);
    
    if (_isFulfilled) {
        id new_result = completionHandler ? completionHandler(_result) : _result;
        [self resolveReturnedPromise:returnedPromise withResult:new_result];
    } else if (_isRejected) {
        id new_result = errorHandler ? errorHandler(_result) : _result;
        if (!errorHandler) {
            DLogInfo(@"error signal with reason %@ not handled by the promise %@", new_result, self);
        }
        if (_isCancelled) {
            [returnedPromise cancelWithReason:_result];
        }
        else {
            [self resolveReturnedPromise:returnedPromise withResult:new_result];
        }
    }
}

#pragma mark -

- (RXPromise*) then:(id(^)(id result))completionHandler
       errorHandler:(id(^)(NSError* error))errorHandler
    progressHandler:(void(^)(id progress))progressHandler
{
    DLogInfo(@"Invoking `then`. self: %@", self);
    
    RXPromise* promise = [[RXPromise alloc] init];
    dispatch_async(_sync_queue, ^{
        [self.promises addObject:promise];
        // handlers will be queued in the sync queue behind "us".
        if (!(_isFulfilled || _isRejected)) {
            DLogInfo(@"exec on sync_queue: queueing handler on handler queue. self: %@", self);
            if (!_handler_queue) {
                char buffer[64];
                snprintf(buffer, sizeof(buffer),"RXPromise_handler_queue-%p", (__bridge void*)self);
                _handler_queue = dispatch_queue_create(buffer, DISPATCH_QUEUE_SERIAL);
                assert(_handler_queue);
                dispatch_set_target_queue(_handler_queue, s_handler_queue_parent);
                dispatch_suspend(_handler_queue);
            }
            dispatch_async(_handler_queue, ^{
                DLogInfo(@"exec on handler_queue: dispatch handler on sync queue. self: %@", self);
                assert(self.isFulfilled || self.isRejected);
                dispatch_async(_sync_queue, ^{
                    DLogInfo(@"exec on sync_queue: self: %@, returned promise: %@ ...", self, promise);
                    [self resolveReturnedPromise:promise completion:completionHandler error:errorHandler];
                });
            });
        }
        else {
            DLogInfo(@"exec on sync_queue: dispatch handler on sync queue. self: %@", self);
            dispatch_async(_sync_queue, ^{
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


- (id) get {
    dispatch_semaphore_wait(_avail, DISPATCH_TIME_FOREVER);
    dispatch_semaphore_signal(_avail);
    return _result;
}

- (void) wait {
    dispatch_semaphore_wait(_avail, DISPATCH_TIME_FOREVER);
    dispatch_semaphore_signal(_avail);
    dispatch_sync(_sync_queue, ^{
        assert(_handler_queue == NULL);
    });
}


#pragma mark -

- (NSString*) description {
    return [self rx_descriptionLevel:0];
}


- (NSString*) rx_descriptionLevel:(int)level {
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
            [desc appendString:[p rx_descriptionLevel:level+1]];
            [desc appendString:@"\n"];
        }
        [desc appendString:[NSString stringWithFormat:@"%@]", indent]];
    }
    return desc;
}



@end
