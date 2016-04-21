//
//  RXPromise+RXExtension.h
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

#import "RXPromise.h"

/* Synopsis
 
 typedef RXPromise* (^rxp_unary_task)(id input);
 typedef RXPromise* (^rxp_nullary_task)();
 
 
 @interface RXPromise (RXExtension)

 + (RXPromise*) all:(NSArray*)promises;
 + (RXPromise*) any:(NSArray*)promises;
 + (RXPromise*) sequence:(NSArray*)inputs task:(RXPromise* (^)(id input)) task;
 + (instancetype) repeat:(rxp_nullary_task)block;
 
 @end
 
*/



/**
 @brief Type definition for an asynchronous block taking one input parameter and
 returning a \c RXPromise.
 */
typedef RXPromise* (^rxp_unary_task)(id input);


/**
 @brief Type definition for an asynchronous block taking no parameter and
 returning a \c RXPromise.
 */
typedef RXPromise* (^rxp_nullary_task)();




@interface RXPromise (RXExtension)

/**
 @brief Returns a new \p RXPromise object. If \a all promises in the given array 
 \p promises have been \a fulfilled, the returned promise will be fulfilled with 
 an array containing the result of each promise. Otherwise, the returned promise 
 will be rejected with the error reason of the first failing promise in the array.
 
 @discussion If the given array is \c nil or empty, the returned promise will be
 fulfilled with an empty \c NSArray. Otherwise, if all promises have been fulfilled, 
 the returned promise will be fulfilled with an \c NSArray object containing the
 result value of each promise from the given array @p promises in the corresponding 
 order. 
 
 @par If the result of any promise equals `nil` a \c NSNull object will be stored 
 into the result array instead.
 
 @par If the returned promise will be cancelled or if any promise in the array has
 been rejected or cancelled, all other promises in the array will remain unaffected.
 If it is desired to cancel promises if any promise within the array failed, it is
 suggested to do this in the error handler.
 
 @note If more than one promises will be rejected, the error reason of the subsequent
 promises will be ignored. It is suggested to register error handlers in order 
 to track the errors if required.
 
 @param promises A @c NSArray containing promises. It may be empty or \c nil.
 
 @return A new promise whose value is a \c NSArray containing the result of each
 promise, or an empty \c NSArray.
 
 
 @par \b Example: @code
 [RXPromise all:@[
    [self asyncA]
    .then(^id(id result){ 
        return @"A";
    }, ^id(NSError*error){ 
        return error;
    });
 ,  [self asyncB]
    .then(^id(id result){ 
        return @"B";
    }, ^id(NSError*error){ 
        return error;
    });
 ]
 .then(^id(id results){
     // result equals @[@"A", @"B"]
     id result = [self asyncWithParamA:results[0]
                                paramB:results[1]]
     assert(result != nil);
     return result;
 }, ^id(NSError*error){
     for (RXPromise* p in promises) {[p.parent cancelWithReason:error];}
     return nil;
 });
 @endcode

 */
+ (instancetype)all:(NSArray*)promises;



/**
 @brief Returns a new \p RXPromise object. If \a all promises in the given array
 \p promises have been fulfilled \a or rejected, the returned promise will be
 \a fulfilled with an array containing \c RXSettledResult objects each representing
 the result of the correspoding promise in the same order.
 
 @discussion Each \c RXSettledResult object will have either \c isFulfilled or
 \c isRejected set to \c YES, and the \c result property will hold the value \a or
 the error reason. If the given array is \c nil or empty, the returned promise 
 will be fulfilled with an empty \c NSArray.

 @note The returned promise will always be be \a fulfilled when all promises in the
 array have been resolved - no matter if they get fulfilled \a or rejected or cancelled.
 
 @par If the returned promise will be cancelled or if any promise in the array has
 been rejected or cancelled, all other promises in the array will remain unaffected.
 If it is desired to cancel promises if any promise in the array has been rejected,
 it is suggested to do this in the error handler.
 
 @param promises A @c NSArray containing promises. It may be empty or \c nil.
 
 @return A new promise whose value is a \c NSArray containing \c RXSettledResult 
 objects, or an empty \c NSArray.
 */
+ (instancetype)allSettled:(NSArray*)promises;


/**
 @brief Returns a new \c RXPromise object. If \a any promise in the given array
 @p promises has been \a fulfilled, the returned promise will be fulfilled with 
 the value of this first fulfilled promise. The returned promise will be rejected
 only after when \a all promises in the given array have been rejected.
 
 @discussion If more than one promise will be fulfilled, the result of the subsequent
 promises will be ignored. If any promise in the array will be resolved or cancelled, 
 all other promises will be unaffected. When it is desired to cancel all other promises 
 it is suggested to do so in the completion respectively the error handler of the 
 returned promise.
 
 @par \b Example:@code
 NSArray* promises = @[async(a), async(b), async(c)];
 RXPromise* any = [RXPromise any:promises]
 .then(^id(id result){
     NSLog(@"first result: %@", result);
     for (RXPromise* p in promises) {[p cancel];}
     return nil;
 },^id(NSError* error){
     NSLog(@"Error: %@", error);
     for (RXPromise* p in promises) {[p cancelWithReason:error];}
     return nil;
 });
 @endcode
 
 @param promises A \c NSArray containing promises.
 
 @note The returned promise will be rejected with reason \c \@"parameter error" if
 the parameter \p promises is \c nil or empty.
 
 @return A new promise whose value is the value of the first fulfilled promise.
 */
+ (instancetype)any:(NSArray*)promises;


/**
 For each element in array \p inputs sequentially call the asynchronous task
 passing it the element as its input argument.
 

 @discussion If the task succeeds, the task will be invoked with the next input,
 if any. The eventual result of each task is ignored. If the tasks fails, no further 
 inputs will be processed and the returned promise will be resolved with the error.
 If all inputs have been processed successfully the returned promise will be 
 resoveld with @"OK".
 
 The tasks are cancelable. That is, if the returned promise will be cancelled, the
 cancel signal will be forwarded to the current running task via cancelling the
 root promise of task's returned promise.

@param inputs A array of input values.

@param task The unary task to be invoked.

@return A promise.
*/
+ (instancetype) sequence:(NSArray*)inputs task:(RXPromise* (^)(id input)) task;


/**
 Executes the asynchronous block repeatedly until the block returns \c nil or the 
 promise returned from the current block will be rejected.
 
 The block is an asynchronous task returning a new promise. The receiver will 
 \c sequentially invoke the asynchronous block until either it returns \c nil
 or its returned promise will be rejected. The next block will be executed
 only after the promise of the previous block has been fulfilled.
 
 The method \c repeat is itself asynchronous. It can be cancelled by sending the
 returned promise a \c cancel message.
 
 @param block The block shall return a new promise returned from an asynchronous
 task, or \c nil in order to indicate the stop condition for the loop.
 
 @return A new promise. If the \p repeat: method could be executed successfully, 
 the promise will be fulfilled with @"OK". Otherwise the promise will be rejected 
 with the error reason of the promise which has been rejected by the underlying task.
*/
+ (instancetype) repeat:(rxp_nullary_task)block;



#pragma mark - iOS Specific

#if defined(TARGET_OS_IOS) && TARGET_OS_IOS

/**
 Executes the asynchronous task associated to the receiver as an iOS Background Task.
 
 @discussion The receiver requests background execution time from the system which
 delays suspension of the app up until the receiver will be resolved or cancelled.
 
 Since Apps are given only a limited amount of time to finish background tasks, 
 this time may expire before the task finishes. In this case the receiver's root
 will be cancelled which in turn propagates the cancel event to all children of
 the reciever, including the receiver.
 
 Tasks may want to handle the cancellation in order to execute additional code which
 orderly closes the task. This should not take too long, since by the time the cancel
 handler is called, the app is already very close to its time limit.
 
 @warning Handlers registered on child promises may not be executed when the app 
 is in background.
 
 @param taskName The name to display in the debugger when viewing the background task.
 If you specify \c nil for this parameter, this method generates a name based on the
 name of the calling function or method.

 */
- (void) makeBackgroundTaskWithName:(NSString*)taskName;

    
#endif

@end
