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
 @brief Method \c all returns a \p RXPromise object which will be resolved when \a all
 promises in the array @p promises are fulfilled or when \a any of it will be rejected.
 
 @discussion The returned promise' completion handler (if any) will be called when
 all promises in the array @p promises have been resolved successfully. The parameter 
 @p result of the completion handler will be an array containing the result of each 
 promise from the array @p promises in the corresponding order.
 
 @par The returned promise' error handler (if any) will be called when any promise 
 in the array @p promises has been rejected with the reason of the first failed 
 promise. If any more promises do fail, the reason will be ignored. It is suggested
 to register error handlers
 
 @par If the returned promise will be cancelled or if any promise in the array has 
 been rejected or cancelled, all other promises in the array will remain unaffected.
 If it is desired to cancel promises if any promise within the array failed, it is 
 suggested to do this in the error handler.
 
 
 @par \b Note:
 If the eventual result of the task equals \c nil, an object of type \c NSNull will be 
 stored in the correspondin index of the result array instead. This is due the restriction 
 of \c NSArray which cannot contain \c nil values.
 
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

 @param promises A @c NSArray containing promises.

 @warning The promise is rejected with reason \c \@"parameter error" if
 the parameter @p promises is \c nil or empty.
 
 @return A new promise.
 */
+ (instancetype)all:(NSArray*)promises NS_RETURNS_RETAINED;


/**
 @brief Method \c allSettled returns a \p RXPromise object which will be resolved when \a all
 promises in the array @p promises are fulfilled or all are rejected.
 
 @discussion In contrast to \c all, which resolves as soon as one of the promises
 has been rejected, \c allSettled waits until all promises have resolved before
 proceeding. The promise will be fulfilled as long \c allSettled was provided with
 valid params. The parameter @p result of the completion handler will be an array
 of RXSettledResult objects. Each will have either isFulfilled or isRejected set to
 true, and the result property will hold the fulfillment value or rejection reason.
 
 @par \b Caution:
 The completion handler's return value MUST NOT be \c nil. This is due the restriction
 of \c NSArrays which cannot contain \c nil values.
 
 @param promises A @c NSArray containing promises.
 
 @warning The promise is rejected with reason \c \@"parameter error" if
 the parameter @p promises is \c nil or empty.
 
 @return A new promise.
 */
+ (instancetype)allSettled:(NSArray*)promises NS_RETURNS_RETAINED;

/*!
 @brief Method \p any returns a \c RXPromise object which will be resolved when
 \a any promise in the array \p promises is fulfilled or when \a all have been rejected.
 
 @discussion
 If the first promises in the array will be resolved by the underlying task, all 
 others will be unaffected. When it is desired to cancel all other promises it is 
 suggested to do so in the completion respectively the error handler of the returned
 promise.
 
 The @p result parameter of the completion handler of the @p then property of the
 returned promise is the result of the first promise which has been fulfilled.
 
 The @p reason parameter of the error handler of the @p then property of the returned
 promise indicates that none of the promises has been fulfilled.
 
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
 
 @note The promise is rejected with reason \c \@"parameter error" if
 the parameter \p promises is \c nil or empty.
 
 @return A new promise.
 */
+ (instancetype)any:(NSArray*)promises NS_RETURNS_RETAINED;


/*!
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
+ (instancetype) sequence:(NSArray*)inputs task:(RXPromise* (^)(id input)) task NS_RETURNS_RETAINED;


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
 
 @return A promise. If the \p repeat: method could be executed successfully, the
 promise's value equals @"OK". Otherwise the promise's value will contain the
 error reason of the task which rejected the returned promise.
*/
+ (instancetype) repeat:(rxp_nullary_task)block NS_RETURNS_RETAINED;



#pragma mark - iOS Specific

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE

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
