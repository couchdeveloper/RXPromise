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
 
 A RXPromise is a lightweight primitive which helps managing asynchronous patterns
 and make them easier to follow and understand. It also adds a few powerful features
 to asynchronous operations like \a continuation , \a grouping and \a cancellation
 
 
## Synopsis
 
 See also [RXPromise(Deferred)](@ref RXPromise(Deferred)).
 
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
 

 
 
## Concurrency:

 Concurrent access to shared resources is only guaranteed to be safe for accesses
 from within handlers whose promises belong to the same "promise tree".
 
 A "promise tree" is a set of promises which share the same root promise.
 

 @remarks Currently, it is guraranteed that concurrent access from within
 any handler from any promise to a shared resource is guaranteed to be safe.

 
## Usage:
 

 An example for continuation:
 
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
 
 
Simultaneous Invokations:
   
 
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
typedef RXPromise* (^then_block_t)(completionHandler_t, errorHandler_t) __attribute((ns_returns_retained));



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
 Property `then` returns a block which when called will register a completion 
 handler and an error handler which are passed as arguments to the block. When 
 the receiver will be fulfilled the completion handler will be called. When 
 the receiver will be rejected the error handler will be called.
 
 The receiver will be retained and only released until after the receiver has
 been resolved (see "Requirements for an asynchronous result provider").
 
 The block returns a new RXPromise whose result will become the return value
 of either handler that gets called when the receiver will be resolved.
  
 If the receiver is already resolved when the block is invoked, the corresponding
 handler will be called immediately.
 
 Handlers may be NULL.
 
 The receiver can register zero or more handler (pairs) through clientes calling
 the block multiple times.
 
 @return Returns a block of type `RXPromise* (^)(completionHandler_t, errorHandler_t)`.
 */
@property (nonatomic, readonly) then_block_t then;

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
 
 @param promises A `NSArray` containing promises. The array must not be `nil`, and
 it must not be empty.
 
 @return A new promise.
 */
+ (RXPromise*)all:(NSArray*)promises;

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
 
 @param result The result given from the asynchronous result provider.
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

@end


