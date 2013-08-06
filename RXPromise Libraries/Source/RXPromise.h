//
//  RXPromise.h
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

#import <Foundation/Foundation.h>


/*
 
 A RXPromise object represents the eventual result of an asynchronous function
 or method.
 
 
## Synopsis
 
 See also [RXPromise(Deferred)](@ref RXPromise(Deferred)).
 
@class RXPromise;

typedef id (^promise_promise_completionHandler_t)(id result);
typedef id (^promise_errorHandler_t)(NSError* error);
 
typedef RXPromise* (^then_block_t)(promise_completionHandler_t, promise_errorHandler_t);
typedef RXPromise* (^then_on_block_t)(dispatch_queue_t, promise_completionHandler_t, promise_errorHandler_t);


@interface RXPromise : NSObject

@property (nonatomic, readonly) BOOL isPending;
@property (nonatomic, readonly) BOOL isFulfilled;
@property (nonatomic, readonly) BOOL isRejected;
@property (nonatomic, readonly) BOOL isCancelled;

@property (nonatomic, readonly) then_t then;

+ (RXPromise*)all:(NSArray*)promises;
- (void) cancel;
- (void) bind:(RXPromise*) other;
- (id) get;
- (void) wait;

@end

@interface RXPromise(Deferred)

- (id)init;
- (void) fulfillWithValue:(id)result;
- (void) rejectWithReason:(id)error;
- (void) cancelWithReason:(id)reason;
- (void) setProgress:(id)progress;

@end
 

 
 
## Concurrency:
 
 RXPromises are itself thread safe and will not dead lock. It's safe to send them 
 messages from any thread/queue and at any time.
 
 The handlers use an "execution context" which they are executed on. The execution
 context is either explicit or implicit.
 
 If the `then` propertie's block will be used to define the success and error
 handler, the handlers will implictily run on an _unspecified_ and _concurrent_
 execution context. That is, once the promise is resolved the corresponding 
 handler MAY execute on any thread and concurrently to any other handler.
 
 If the `thenOn` propertie's block will be used to define success and error handler,
 the execution context will be explicitly defined through the first parameter 
 _queue_ of the block, which is either a serial or concurrent _dispatch queue_.
 Once the promise is resolved, the handler is guaranteed to execute on the specified
 execution context. The execution context MAY be serial or concurrent.

 Without any other synchronization means, concurrent access to shared resources 
 from within handlers is only guaranteed to be safe when they execute on the same
 and _serial_ execution context.
 
 The "execution context" for a dispatch queue is the target queue of that queue.
 The target queue is responsible for processing the success or error block.
 
 
 It's safe to specify the same execution context where the `then` or `thenOn` 
 property will be executed.
 
 
 
## Usage:
 

### An example for continuation:
 
    [self fetchUsersWithURL:url]
    .then(^id(id usersJSON){
        return [foo parseJSON:usersJSON];
     }, nil)
    .then(^id(id users){
        return [self mergeIntoMOC:users];
    }, nil)
    .thenOn(dispatch_get_main_queue(), nil,
    ^id(NSError* error) {
        // on main thread
        [self alertError:error];
        return nil;
    });
 
 
### Simultaneous Invokations:
   
 
 Perform authentication for a user, if that succeeded, simultaneously load profile
 and messages for that user, parse the JSON and create models.
 
    RXPromise* if_auth = [self.user authenticate];

    if_auth
    .then(^id(id result){ return [self.user loadProfile]; }, nil)
    .then(^id(id result){ return [self parseJSON:result]; }, nil)
    .then(^id(id result){ return [self createProfileModel:result]; }, nil)
    });

    if_auth
    .then(^id(id result){ return [self.user loadMessages]; }, nil)
    .then(^id(id result){ return [self parseJSON:result]; }, nil)
    .then(^id(id result){ return [self createMessagesModel:result]; }, nil)
    });
 
 
*/




// forward
@class RXPromise;

/**
 @brief Type definition for the completion handler block.
 
 @discussion The completion handler will be invoked when the associated promise has 
 been fulfilled. The exucution context is either the execution context specified
 when the handlers have been registered via property `thenOn` or it is 
 unspecified when registred via `then`.
 
 @param result The value set by the "asynchronous result provider" when it succeeded.
 
 @return An object or `nil`. If the return value is an NSError object the handler
 indicates a failure and the associated promise (namely the "returned promise") will
 be rejected with this error. Otherwise, any other value indicates success and the
 associated promise will be fulfilled with this value.
 */
typedef id (^promise_completionHandler_t)(id result);

/**
 @brief Type definition for the error handler block.
 
 @discussion The error handler will be invoked when the associated promise has been
 rejected or cancelled. The exucution context is either the execution context specified
 when the handlers have been registered via property `thenOn` or it is
 unspecified when registred via `then`.
 
 @param error The value set by the "asynchronous result provider" when it failed.
 
 @return An object or `nil`. If the return value is an NSError object the handler
 indicates a failure and the associated promise (namely the "returned promise") will
 be rejected with this error. Otherwise, any other value indicates success and the
 assiciated promise will be fulfilled with this value.
 */
typedef id (^promise_errorHandler_t)(NSError* error);

/**
 @brief Type definition of the "then block". The "then block" is the return value
 of the property `then`.
 
 @discussion  The "then block" has two blocks as parameters, the completion handler
 and the error handler. The blocks may be NULL. The "then block" returns a promise, 
 the "returned promise". When the parent promise will be resolved the corresponding
 handler will be invoked and executed on a _concurrent_ unspecified execution context.
 
 If the handler is not NULL, the minimum implementation of each block must return 
 a value. The returned value becomes the eventual or immediate result of the
 "returned promise", the return value of the `then` property.
 (see `promise_completionHandler_t` and `promise_errorHandler_t`).
 */
typedef RXPromise* (^then_block_t)(promise_completionHandler_t, promise_errorHandler_t) __attribute((ns_returns_retained));

/**
 @brief Type definition of the "then_on block". The "then_on block" is the return 
 value of the property `thenOn`. 
 
 @discussion The "then_on block" has three parameters, the execution context, the
 completion handler and the error handler. The blocks may be NULL. The "then block" 
 returns a promise, the "returned promise". When the parent promise will be resolved 
 the corresponding handler will be invoked and executed on the _specified execution_
 given in the first parameter.
 
 If the handler is not NULL, the minimum implementation of each block must return
 a value. The returned value becomes the eventual or immediate result of the
 "returned promise", the return value of the `then` property.
 (see `promise_completionHandler_t` and `promise_errorHandler_t`).
 */
typedef RXPromise* (^then_on_block_t)(dispatch_queue_t, promise_completionHandler_t, promise_errorHandler_t) __attribute((ns_returns_retained));


/**
 
 @brief A \a RXPromise object represents the eventual result of an asynchronous
 function or method.
 
 A RXPromise is a lightweight primitive which helps managing asynchronous patterns
 and make them easier to follow and understand. It also adds a few powerful features
 to asynchronous operations like \a continuation , \a grouping and \a cancellation
 
 
 @par \b Caution:
 
 A promise which has registered one or more handlers will not deallocate unless
 it is resolved and the handlers are executed. This implies that an asynchronous
 result provider MUST eventually resolve its promise.
 
 @par \b Concurrency:
 
 Concurrent access to shared resources is only guaranteed to be safe for accesses
 from within handlers whose promises belong to the same "promise tree".
 
 A "promise tree" is a set of promises which share the same root promise.
 
 
 @remarks Currently, it is guraranteed that concurrent access from within
 any handler from any promise to a shared resource is guaranteed to be safe.
 */

@interface RXPromise  : NSObject


/**
 @brief Property `then` returns a block whose signature is
  `RXPromise* (^)(promise_completionHandler_t onSuccess, promise_errorHandler_t onError)`.
 
 When the block is called it will register the completion handler _onSuccess_ and
 the error handler _onError_.
  
 The receiver will be retained and only released until after the receiver has
 been resolved (see "Requirements for an asynchronous result provider").
 
 The block returns a new RXPromise, the "returned promise" whose result will become 
 the return value of either handler that gets called when the receiver will be resolved.
  
 If the receiver is already resolved when the block is invoked, the corresponding
 handler will be immediately asynchronously scheduled for execution on the 
 _unspecified_ execution context.
 
 Parameter _onSuccess_ and _onError_ may be `nil`.
 
 The receiver can register zero or more handler (pairs) through clientes calling
 the block multiple times.
 
 @return Returns a block of type `RXPromise* (^)(promise_completionHandler_t, promise_errorHandler_t)`.
 */
@property (nonatomic, readonly) then_block_t then;


/**
 @brief Property `thenOn` returns a block whose signature is
 `RXPromise* (^)(dispatch_queue_t queue, promise_completionHandler_t onSuccess, promise_errorHandler_t onError)`.
 
 
 When the block is called it will register the completion handler _onSuccess_ and 
 the error handler _onError_. When the receiver will be fulfilled the success handler 
 will be executed on the specified queue _queue_. When the receiver will be rejected 
 the error handler will be called on the specified queue _queue_.
 
 The receiver will be retained and only released until after the receiver has
 been resolved (see "Requirements for an asynchronous result provider").
 
 The block returns a new RXPromise whose result will become the return value
 of either handler that gets called when the receiver will be resolved.
 
 If the receiver is already resolved when the block is invoked, the corresponding
 handler will be immediately asynchronously scheduled for execution on the
 _specified_ execution context.
 
 Parameter _onSuccess_ and _onError_ may be `nil`.
 
 Parameter _queue_ may be `nil` which effectivle is the same as when using the 
 `then_block_t` block returned from property `then`.
 
 The receiver can register zero or more handler (pairs) through clientes calling
 the block multiple times.
 
 @return Returns a block of type `RXPromise* (^)(dispatch_queue_t, promise_completionHandler_t, promise_errorHandler_t)`.
 */
@property (nonatomic, readonly) then_on_block_t thenOn;

/**
 Returns `YES` if the receiveer is pending.
 */
@property (nonatomic, readonly) BOOL isPending;

/**
 Returns `YES` if the receiver is fulfilled.
 */
@property (nonatomic, readonly) BOOL isFulfilled;

/**
 Returns `YES` if the receiver is rejected.
 */
@property (nonatomic, readonly) BOOL isRejected;

/**
 Returns `YES` if the receiver is cancelled.
 */
@property (nonatomic, readonly) BOOL isCancelled;


/**
 Returns the parent promise - the promise which created
 the receiver.
 */
@property (nonatomic, readonly) RXPromise* parent;


/**
 Cancels the promise unless it is already resolved and then forwards the
 message to all children.
 */
- (void) cancel;

/**
 @brief Cancels the promise with the specfied reason unless it is already resolved and
 then forwards the message wto all children.
 
 @param reason The reason. If reason is not a NSError object, the receiver will
 create a NSError object whose demain is @"RXPromise", the error code is -1000
 and the user dictionary contains an entry with key NSLocalizedFailureReason whose
 value becomes parameter reason.
 */
- (void) cancelWithReason:(id)reason;


/**
 @brief Binds the receiver to the given promise  @p other.
 
 @discussion The receiver will take in the state of the given promise @p other, and
 vice versa: The receiver will be fulfilled or rejected according its bound promise. If the
 receiver receives a `cancel` message, the bound promise will be sent a `cancelWithReason:`
 message with the receiver's reason.<br>
 
 @attention A promise should not be bound to more than one other promise.<p>
 
 
 @par Example: @code
 - (RXPromise*) doSomethingAsync {
 self.promise = [RXPromise new];
 return self.promise;
 }
 
 - (void) handleEvent:(id)event {
 RXPromise* other = [self handleEvenAsync:event];
 [self.promise bind:other];
 }
 @endcode
 
 @param other The promise that will bind to the receiver.
 */
- (void) bind:(RXPromise*) other;


/**
 @brief Blocks the current thread until after the promise has been resolved, and previously
 queued handlers have been finished.
 */
- (void) wait;

/**
 Returns the value of the promise.
 
 Will block the current thread until after the promise has been resolved.
 
 @return Returns the _value_ of the receiver.
 */
- (id) get;


/**
 @brief Method \a all returns a \a RXPromise object which will be resolved when all promises
 in the array @p promises are fulfilled or when any of it will be rejected.
 
 @discussion
 
 If any of the promises in the array will be rejected, all others will be send a
 `cancelWithReason:` message whose parameter @p reason is the error reason of the
 failing promise.
 
 The @p result parameter of the completion handler of the @p then property of the
 returned promise is the `NSArray` @p promises which has been passed as parameter.
 
 The @p reason parameter of the error handler of the `then` property of the returned
 promise is the error reason of the first rejected promise.
 
 Example:
 
 @code NSArray* promises = @[async_A(),
     async_B(), async_C();
 RXPromise* all = [RXPromise all:promises]
 .then(^id(id result){
     assert(result == promise);
     return nil;
 },nil);
 @endcode
 
 @param promises A `NSArray` containing promises.
 
 @return A new promise. The promise is rejected with reason @"parameter error" if
 the parameter _promises_ is `nil` or empty.
 */
+ (RXPromise*)all:(NSArray*)promises;



/**
 @brief Method \a any returns a \a RXPromise object which will be resolved when
 any promise in the array @p promises is fulfilled or when all have been rejected.
 
 @discussion
 
 If any of the promises in the array will be fulfilled, all others will be send a
 `cancel` message.
 
 The @p result parameter of the completion handler of the @p then property of the
 returned promise is the result of the first promise which has been fulfilled.
 
 The @p reason parameter of the error handler of the `then` property of the returned
 promise indicates that none of the promises has been fulfilled.
 
 Example:
 
 @code NSArray* promises = @[async_A(),
     async_B(), async_C();
 RXPromise* any = [RXPromise any:promises]
 .then(^id(id result){
     NSLog(@"first result: %@", result);
     return nil;
 },nil);
 @endcode
 
 @param promises A `NSArray` containing promises.
 
 @return A new promise. The promise is rejected with reason @"parameter error" if
 the parameter _promises_ is `nil` or empty.
 */
+ (RXPromise*)any:(NSArray*)promises;




@end



/**
 
 See also: `RXPromise` interface.
 
 The "Deferred" interface is what the asynchronous result provider will see.
 It is responisble for creating and resolving the promise.
 
 */
@interface RXPromise(Deferred)

/**
 @brief Returns a new promise whose state is pending.
 
 Designated Initializer
 */
- (id)init;


/**
 @brief Fulfilles the promise with value _result_.
 
 If the promise is already resolved this method has no effect.
 
 @param value The result given from the asynchronous result provider.
 */
- (void) fulfillWithValue:(id)value;


/**
 @brief  Rejects the promise with the specified reason.
 
 If the promise is already resolved this method has no effect.
 
 @param reason The reason. If reason is not a NSError object, the receiver will
 create a NSError object whose demain is @"RXPromise", the error code is -1000 
 and the user dictionary contains an entry with key NSLocalizedFailureReason whose 
 value becomes parameter reason.
 */
- (void) rejectWithReason:(id)reason;


/**
 internal
 */

- (RXPromise*) registerWithQueue:(dispatch_queue_t)target_queue
                       onSuccess:(promise_completionHandler_t)onSuccess
                       onFailure:(promise_errorHandler_t)onFailure
                   returnPromise:(BOOL)returnPromise    __attribute((ns_returns_retained));

@end


