//
//  RXTimer.h
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

@class RXTimer;
typedef void (^RXTimerHandler)(RXTimer* timer);

@interface RXTimer : NSObject


/**
 Initalizes a cancelable, one-shot timer in suspended state.
 
 @discussion Setting a tolerance for a timer allows it to fire later than the scheduled fire
 date, improving the ability of the system to optimize for increased power savings
 and responsiveness. The timer may fire at any time between its scheduled fire date
 and the scheduled fire date plus the tolerance. The timer will not fire before the
 scheduled fire date. The default value is zero, which means no additional tolerance
 is applied.
 
 As the user of the timer, you will have the best idea of what an appropriate tolerance
 for a timer may be. A general rule of thumb, though, is to set the tolerance to at
 least 10% of the interval, for a repeating timer. Even a small amount of tolerance
 will have a significant positive impact on the power usage of your application.
 The system may put a maximum value of the tolerance.
 
 
 @param: delay The delay in seconds after the timer will fire
 
 @param queue  The queue on which to submit the block.
 
 @param block  The block to submit. This parameter cannot be NULL.
 
 @param tolearance A tolerance in seconds the fire data can deviate. Must be
 positive.
 
 @return An initialized \p RXTimer object.
 
 
 */

- (id)initWithTimeIntervalSinceNow:(NSTimeInterval)delay
                         tolorance:(double)tolerance
                             queue:(dispatch_queue_t)queue
                             block:(RXTimerHandler)block;


/**
 Starts the timer.
 
 The timer fires once after the specified delay plus the specified tolerance.
 */
- (void) start;

/**
 Cancels the timer.
 
 The timer becomes invalid and its block will not be executed.
 */
- (void)cancel;

/**
 Returns YES if the timer has not yet been fired and it is not cancelled.
 */
- (BOOL)isValid;

@end
