//
//  main.m
//  Sample6
//
//  Created by Andreas Grosam on 03.12.13.
//
//

#import <Foundation/Foundation.h>
#import <RXPromise/RXPromise.h>

/**
 
 Objective: Cancel an asynchronous task when there are no more "subscribers".
 
 A "subscriber" is a named strong reference to a promise, or a handler which has
 been registered and which is not yet called. A "named" strong reference to a promise
 is an ivar, a captured promise in a block, or any named temporary variable, etc..
 Handlers will get "unregistered" after they have been called when the promise 
 has been resolved.
 
 What we want to achieve is that the task will be automaticalyl cancelled when 
 there is no one waiting for the result, withou a call-site explicitly sending
 `cancel` to the promise which is associated to the task.
 
 */


/**
 
 Canonical Subclass of NSOperation
 
 A cancelable, asynchronous operation
 
 */

typedef void (^completion_block_t)(id result);

@interface MyOperation : NSOperation

// Designated Initializer
// Parameter count equals the duration in 1/10 seconds until the task is fininshed.
- (id)initWithCount:(int)count completion:(completion_block_t)completioHandler;

@property (nonatomic, readonly) id result;
@property (nonatomic, copy) completion_block_t completionHandler;
@end

@implementation MyOperation {
    BOOL _isExecuting;
    BOOL _isFinished;
    
    dispatch_queue_t _syncQueue;
    int _count;
    id _result;
    completion_block_t _completionHandler;
    id _self;  // immortality
}

- (id)initWithCount:(int)count completion:(completion_block_t)completionHandler
{
    self = [super init];
    if (self) {
        _count = count;
        _syncQueue = dispatch_queue_create("op.sync_queue", NULL);
        _completionHandler = [completionHandler copy];
    }
    return self;
}

- (id) result {
    __block id result;
    dispatch_sync(_syncQueue, ^{
        result = _result;
    });
    return result;
}

- (void) start
{
    dispatch_async(_syncQueue, ^{
        if (!self.isCancelled && !_isFinished && !_isExecuting) {
            self.isExecuting = YES;
            _self = self; // make self immortal for the duration of the task
            dispatch_async(dispatch_get_global_queue(0, 0), ^{
                
                // Simulated work load:
                int count = _count;
                while (count > 0) {
                    if (self.isCancelled) {
                        break;
                    }
                    printf(".");
                    usleep(100*1000);
                    --count;
                }
                
                // Set result and terminate
                dispatch_async(_syncQueue, ^{
                    if (_result == nil && count == 0) {
                        _result = @"OK";
                    }
                    [self terminate];
                });
            });
        }
    });
}

- (void) terminate {
    self.isExecuting = NO;
    self.isFinished = YES;
    completion_block_t completionHandler = _completionHandler;
    _completionHandler = nil;
    id result = _result;
    _self = nil;
    if (completionHandler) {
        dispatch_async(dispatch_get_global_queue(0, 0), ^{
            completionHandler(result);
        });
    }
}


- (BOOL) isConcurrent {
    return YES;
}

- (BOOL) isExecuting {
    return _isExecuting;
}
- (void) setIsExecuting:(BOOL)isExecuting {
    if (_isExecuting != isExecuting) {
        [self willChangeValueForKey:@"isExecuting"];
        _isExecuting = isExecuting;
        [self didChangeValueForKey:@"isExecuting"];
    }
}

- (BOOL) isFinished {
    return _isFinished;
}
- (void) setIsFinished:(BOOL)isFinished {
    if (_isFinished != isFinished) {
        [self willChangeValueForKey:@"isFinished"];
        _isFinished = isFinished;
        [self didChangeValueForKey:@"isFinished"];
    }
}

- (void) cancel {
    dispatch_async(_syncQueue, ^{
        if (_result == nil) {
            NSLog(@"Operation cancelled");
            [super cancel];
            _result = [[NSError alloc] initWithDomain:@"MyOperation"
                                                 code:-1000
                                             userInfo:@{NSLocalizedDescriptionKey: @"cancelled"}];
        }
    });
}

@end



int main(int argc, const char * argv[])
{
    
    @autoreleasepool {
        
        typedef RXPromise* (^task_t)();
        
        task_t task = ^RXPromise*{
            
            // This is the "tricky" part:
            
            // In order to acmomplish our objective we use a variant of the
            // promise where we can specify a handler when the promise gets
            // deallocated. However, we need painstakenly care about object
            // references: we need to use weak refernces, in order to avoid
            // keeping either the promise or the task for lifing longer than
            // neccessary:
            
            RXPromise* promise;
            MyOperation* op = [[MyOperation alloc]
                               initWithCount:1000
                               completion:nil];

            // First off: the operation MUST NOT keep a strong reference to its
            // returned promise!
            // When the promise gets deallocated, we cancel the operation.
            // We need a weak referece of the operation in the dealloc handler.
            // Otherwise, the compeltion block would retain the op, and op would
            // live until after the promise get deallocated. However, we don't want
            // the op have any dependency to the promise's life.
            __weak MyOperation* weakOp = op;
            promise = [RXPromise promiseWithDeallocHandler:^{
                MyOperation* strongOp = weakOp;
                [strongOp cancel];
            }];
            // We also require a weak referece of the promise where the operation
            // resolves the promise. Otherwise, the promise wouldn't be deallocated,
            // since the operation is itself a "subscriber".
            __weak RXPromise* weakPromise = promise;
            completion_block_t completionHandler = ^(id result) {
                if ([result isKindOfClass:[NSError class]]) {
                    [weakPromise rejectWithReason:result];
                }
                else {
                    [weakPromise fulfillWithValue:result];
                }
            };
            op.completionHandler = completionHandler;
            [op start];
            return promise;
        };
        
        
        @autoreleasepool {
            __block RXPromise* promise;
            promise = task();
            [promise setTimeout:1.0];
            [promise.then(^id(id result) {
                NSLog(@"Result: %@", result);
                return nil;
            }, ^id(NSError* error) {
                NSLog(@"Error: %@", error);
                promise = nil;
                return nil;
            }) runLoopWait];
        }
        sleep(1);
    }
    return 0;
}

