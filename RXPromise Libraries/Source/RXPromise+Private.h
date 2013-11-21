//
//  RXPromise+Private.h
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
#include <map>

#if TARGET_OS_IPHONE
// Compiling for iOS
    #if __IPHONE_OS_VERSION_MIN_REQUIRED >= 60000
        // >= iOS 6.0
        #define RX_DISPATCH_RELEASE(__object) do {} while(0)
        #define RX_DISPATCH_RETAIN(__object) do {} while(0)
        #define RX_DISPATCH_BRIDGE_VOID_CAST(__object) (__bridge void*)__object
    #else
        // <= iOS 5.x
        #define RX_DISPATCH_RELEASE(__object) do {dispatch_release(__object);} while(0)
        #define RX_DISPATCH_RETAIN(__object) do { dispatch_retain(__object); } while(0)
        #define RX_DISPATCH_BRIDGE_VOID_CAST(__object) __object
    #endif
#elif TARGET_OS_MAC
    // Compiling for Mac OS X
    #if MAC_OS_X_VERSION_MIN_REQUIRED >= 1080
        // >= Mac OS X 10.8
        #define RX_DISPATCH_RELEASE(__object) do {} while(0)
        #define RX_DISPATCH_RETAIN(__object) do {} while(0)
        #define RX_DISPATCH_BRIDGE_VOID_CAST(__object) (__bridge void*)__object
    #else
        // <= Mac OS X 10.7.x
        #define RX_DISPATCH_RELEASE(__object) do {dispatch_release(__object);} while(0)
        #define RX_DISPATCH_RETAIN(__object) do { dispatch_retain(__object); } while(0)
        #define RX_DISPATCH_BRIDGE_VOID_CAST(__object) __object
    #endif
#endif





/** RXPromise_State */
typedef enum RXPromise_StateT {
    Pending     = 0x0,
    Fulfilled   = 0x01,
    Rejected    = 0x02,
    Cancelled   = 0x06
} RXPromise_State;


struct RXPromise_StateAndResult {
    RXPromise_StateT  state;
    id                result;
};


@class RXPromise;

namespace rxpromise {
    
    struct shared {
        typedef std::multimap<void const*, __weak RXPromise*> assocs_t;
        
        dispatch_queue_t sync_queue;
        static constexpr char const* sync_queue_id = "RXPromise.shared_sync_queue";
        
        dispatch_queue_t default_concurrent_queue;
        char const* default_concurrent_queue_id = "RXPromise.default_concurrent_queue";
        
        static constexpr char const* QueueID = "RXPromise.queue_id";
        
        assocs_t  assocs;
        
        shared()
        :   sync_queue(dispatch_queue_create(sync_queue_id, NULL)),
        default_concurrent_queue(dispatch_queue_create(default_concurrent_queue_id, DISPATCH_QUEUE_CONCURRENT))
        {
            assert(sync_queue);
            assert(default_concurrent_queue);
            dispatch_queue_set_specific(sync_queue, QueueID, (void*)(sync_queue_id), NULL);
        }
        
    };
    
    
}

extern rxpromise::shared Shared;


@interface RXPromise (Private)
- (RXPromise_StateAndResult) peakStateAndResult;
- (RXPromise_StateAndResult) synced_peakStateAndResult;
- (id) synced_peakResult;
@end
