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
 
 @discussion The returned promise' success handler(s) (if any) will be called when 
 all given promises have been resolved successfully. The parameter @p result of the 
 success handler will be an array containing the eventual result of each promise 
 from the given array @p promises in the corresponding order.
 
 @par The returned promise' error handler(s) (if any) will be called when any given
 promise has been rejected with the reason of the failed promise.
 
 @par If any promise in the array has been rejected, all others will be send a
 @p cancelWithReason: message whose parameter @p reason is the error reason of the
 failing promise.
 
 @par \b Caution:
 The handler's return value MUST NOT be \c nil. This is due the restriction of
 \c NSArrays which cannot contain \c nil values.
 
 @par \b Example: @code
 [RXPromise all:@[self asyncA], [self asyncB]]
 .then(^id(id results){
     id result = [self asyncCWithParamA:results[0]
                                 paramB:results[1]]
     assert(result != nil);
     return result;
 },nil);
 @endcode

 @param promises A @c NSArray containing promises.

 @warning The promise is rejected with reason \c \@"parameter error" if
 the parameter @p promises is \c nil or empty.
 
 @return A new promise. 
 
 */
+ (instancetype)all:(NSArray*)promises;



/*!
 @brief Method \p any returns a \c RXPromise object which will be resolved when
 \a any promise in the array \p promises is fulfilled or when \a all have been rejected.
 
 @discussion
 If any of the promises in the array will be fulfilled, all others will be send a
 \c cancel message.
 
 The @p result parameter of the completion handler of the @p then property of the
 returned promise is the result of the first promise which has been fulfilled.
 
 The @p reason parameter of the error handler of the @p then property of the returned
 promise indicates that none of the promises has been fulfilled.
 
 @par \b Example:@code
 NSArray* promises = @[async_A(),
     async_B(), async_C();
 RXPromise* any = [RXPromise any:promises]
 .then(^id(id result){
     NSLog(@"first result: %@", result);
     return nil;
 },nil);
 @endcode
 
 @param promises A \c NSArray containing promises.
 
 @note The promise is rejected with reason \c \@"parameter error" if
 the parameter \p promises is \c nil or empty.
 
 @return A new promise.
 */
+ (instancetype)any:(NSArray*)promises;


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
+ (instancetype) sequence:(NSArray*)inputs task:(RXPromise* (^)(id input)) task;


/**
 Asynchronously executes the block in a continuous loop until the block returns
 \c nil or the returned promise will be rejected.
 
 The block can be regarded as the body in a while loop. The block's return value is 
 used in the expression in the "repeat" statement: If the block returns \c nil or if the
 returned promise will be rejected, the loop stops executing the next iteration.
 
 The asychronous "repeat" can be canceled by sending the returned promise a
 cancel message.
 
 @param block The block shall return a promise returned from an asynchronous 
 task, or \c nil in order to indicate the stop condition for the loop.
 
 @return A promise. If the \p repeat: method could be executed successfully, the
 promise's value equals @"OK". Otherwise the promise's value will contain the
 error reason of the task which rejected the returned promise.
*/
+ (instancetype) repeat:(rxp_nullary_task)block;



@end
