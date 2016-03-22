//
//  RXTimer.m
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

#import "RXTimer.h"


@interface RXTimer ()
@end

@implementation RXTimer {
    dispatch_source_t   _timer;
    uint64_t            _interval;
    uint64_t            _leeway;
}


- (id) initWithTimeIntervalSinceNow:(NSTimeInterval)delay
                          tolerance:(double)tolerance
                              queue:(dispatch_queue_t)queue
                              block:(RXTimerHandler)block;
{
    self = [super init];
    if (self) {
        _interval = delay * NSEC_PER_SEC;
        _leeway = tolerance * NSEC_PER_SEC;
        _timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, queue);
        
        dispatch_source_set_event_handler(_timer, ^{
            dispatch_source_cancel(_timer); // one shot timer
            if (block) {
                block(self);
            }
        });
    }
    return self;
}

- (void) dealloc {
    dispatch_source_cancel(_timer);
    //dispatch_release(_timer);
}



// Invoking this method has no effect if the timer source has already been canceled.
- (void) start {
    assert(_timer);
    dispatch_source_set_timer(_timer, dispatch_time(DISPATCH_TIME_NOW, _interval),
                              DISPATCH_TIME_FOREVER /*one shot*/, _leeway);
    dispatch_resume(_timer);
}

- (void) cancel {
    dispatch_source_cancel(_timer);
}

- (BOOL) isValid {
    return _timer && 0 == dispatch_source_testcancel(_timer);
}

@end
