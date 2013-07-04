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


/**
 
 @brief A \a RXPromise object represents the eventual result of an asynchronous function
 or method.
 
 A RXPromise is a lightweight primitive which helps managing asynchronous patterns
 and make them easier to follow and understand. It also adds a few powerful features
 to asynchronous operations like \a continuation , \a grouping and \a cancellation
 
 
@par Synopsis
 
 See also [RXPromise(Deferred)](@ref RXPromise(Deferred)).
 
@code
@class RXPromise;

typedef id (^completionHandler_t)(id result);
typedef id (^errorHandler_t)(NSError* error);
typedef void (^progressHandler_t)(id progress);
typedef RXPromise* (^then_t)(completionHandler_t, errorHandler_t);


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
 
@endcode

 
 
@par \b Concurrency:

 Concurrent access to shared resources is only guaranteed to be safe for accesses
 from within handlers whose promises belong to the same "promise tree".
 
 A "promise tree" is a set of promises which share the same root promise.
 

 @remarks Currently, it is guraranteed that concurrent access from within
 any handler from any promise to a shared resource is guaranteed to be safe.

 
@par \b Usage:
 

 An example for continuation or chaining:
 
@code 
foo.result = nil;
id input = ...;

[foo doSomethingAsyncWith:input]
.then(^id(id result){
    return [foo doFooAsyncWith:result];
 }, nil)
.then(^id(id result){
    return [foo doBarAsyncWith:result];
}, nil)
.then(^id(id result){
    return [foo doFoobarAsyncWith:result];
}, nil)
.then(^id(id result){
    [foo setResult:result];
    return nil;
}, ^id(NSError* error){
    [foo setError:error];
    return nil;
});
@endcode
 
 
Simultaneous Invokations:
   
 
 @par Perform authentication for a user, if that succeeded, simultaneously load profile
 and messages for that user, parse the JSON and create models.
 
@code 
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
@endcode
 
 */






@class RXPromise;


/**
 @brief Type definition for the completion handler block.
 
 @param result The value set by the asynchronous result provided when it succeeded.

 @return An object or `nil`. If the return value is an NSError object the handler
 indicates a failure and an associated promise will be rejected with this error. 
 Otherwise, any other value indicate success and an assiciated promise will be
 fulfilled with this value.
 */
typedef id (^completionHandler_t)(id result);

/**
 Type definition for the error handler block.

 @param error The value set by the asynchronous result provided when it failed.
 
 @return An object or `nil`. If the return value is an NSError object the handler 
 indicates a failure and an associated promise will be rejected with this error. 
 Otherwise, any other value indicate success and an assiciated promise will be
 fulfilled with this value.
 */
typedef id (^errorHandler_t)(NSError* error);

typedef void (^progressHandler_t)(id progress);

/**
 @brief Type definition of the block which will be returned from property `then`.
 
 @discussion The `then` block is used to install a completion handler and an error
 handler for the promise that returned this block. One of this block will be invoked
 (unless, it is `NULL`) when the promise will be resolved.
 
 @par The block returns a new promise which represents the return value of either
 of the handlers that will be called. Handlers must return a value (an object or `nil`) 
 which then becomes the eventual result of the new promise. If the return value of 
 the handler that gets called returns a RXPromise then the eventual result of the 
 new promise will be deferred again. 
 */
typedef RXPromise* (^then_t)(completionHandler_t, errorHandler_t);



/**
 @class RXPromise
 
 @brief A RXPromise object represents the eventual result of an asynchronous function
 or method.
 
 @discussion
 
 A RXPromise is a lightweight primitive which helps managing asynchronous patterns
 and make them easier to follow and understand. It also adds a few powerful features
 to asynchronous operations like \a continuation, \a grouping and \a cancellation.
 */
@interface RXPromise : NSObject

/** @name Retrieving State */

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


/** @name Then */

/**
 `then` returns a block of type `RXPromise* (^)(completionHandler_t, errorHandler_t)`.

 Through calling the returnd block a client can register a completion handler and 
 an error handler passed as arguments to the block. When the receiver will be 
 fulfilled the completion handler will be called. When the receiver will be rejected 
 the error handler will be called.

 The block also returns a new RXPromise whose result will become the return value 
 of either handler that gets called when the receiver will be resolved.
 
 The client may keep a reference of the returnd new promise. For example in order 
 to be able to cancel the underlaying asynchronous result provider or to chain
 further asynchronous tasks when the return value of the handler is a RXPromise.
 
 If the receiver is already resolved when the block is invoked, the corresponding 
 handler will be called immediately.
 
 Handlers may be NULL.
 
 The receiver can register zero or more handler (pairs) through clientes calling 
 the block multiple times. 
 
 @return Returns a block.
 */
@property (nonatomic, readonly) then_t then;


/** @name Cancellation */

/**
 Cancels the promise unless it is already resolved and then forwards the 
 message to all children.
 */
- (void) cancel;


/** @name Grouping  */

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
 
 @param promises A `NSArray` containing promises. The array must not be `nil`, and
 it must not be empty.
 
 @return A new promise.
 */
+ (RXPromise*)all:(NSArray*)promises;






/** @name Miscellaneous  */


/**
 Returns the value of the promise. 
 
 Will block the current thread until after the promise has been resolved.
 
 @return Returns the _value_ of the receiver.
 */
- (id) get;

/**
 Blocks the current thread until after the promise has been resolved, and previously 
 queued handlers have been finished.
 */
- (void) wait;


@end




/**    
 
 See also: `RXPromise` interface.

 The "Deferred" interface is what the asynchronous result provider will see.
 It is responisble for creating and resolving the promise.
 
 */
@interface RXPromise(Deferred)

/** @name Initialization */

/**
 Returns a new promise whose state is pending.
 
 Dedicated Initializer
 */
- (id)init;


/** @name Resolving */

/**
 @brief Fulfilles the promise with value _result_.
 
 If the promise is already resolved this method has no effect.
 
 @param result The result given from the asynchronous result provider.
 */
- (void) fulfillWithValue:(id)result;

/**
 Rejects the promise with reason _error_.

 If the promise is already resolved this method has no effect.
 
 @param error The error reason given from the asynchronous result provider.
 */
- (void) rejectWithReason:(id)error;


/**
 Resovles the promise by canceling it, and forwards the message.

 If the promise is already resolved the promise only forwards the cancel message.
 
 @param reason The reason of the cancellation.
*/
- (void) cancelWithReason:(id)reason;



/** @name Binding  */

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




/** @name Notifying Progress Information */

/**
 
 @param progress The progress 
 
*/
- (void) setProgress:(id)progress;

@end


