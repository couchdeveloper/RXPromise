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

#import <Foundation/Foundation.h>
#import "RXPromise.h"
#import <dispatch/dispatch.h>
#include <map>
#include "utility/DLog.h"


#if defined(__has_feature) && __has_feature(objc_arc)
#define RX_ARC_ENABLED 1
#else
#error ARC must be enabled
#endif


#if !defined (OS_OBJECT_HAVE_OBJC_SUPPORT)
#error missing include os/object.h
#endif

#if !OS_OBJECT_HAVE_OBJC_SUPPORT
#error OS_OBJECT_HAVE_OBJC_SUPPORT must be enabled
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
    
    static_assert(OS_OBJECT_HAVE_OBJC_SUPPORT == 1, "");
    
    struct shared {
        typedef std::multimap<void const*, __weak RXPromise*> assocs_t;
        
        dispatch_queue_t sync_queue;
        static constexpr char const* sync_queue_id = "RXPromise.shared_sync_queue";
        
        dispatch_queue_t default_concurrent_queue;
        static constexpr char const* default_concurrent_queue_id = "RXPromise.default_concurrent_queue";
        
        static constexpr char const* QueueID = "RXPromise.queue_id";
        
        assocs_t  assocs;
        
        shared()
        :   sync_queue(dispatch_queue_create(sync_queue_id, NULL)),
        default_concurrent_queue(dispatch_queue_create(default_concurrent_queue_id, DISPATCH_QUEUE_CONCURRENT))
        {
            assert(sync_queue);
            assert(default_concurrent_queue);
            dispatch_queue_set_specific(sync_queue, QueueID, (void*)(sync_queue_id), NULL);
            DLogInfo(@"created: sync_queue (0x%p), default_concurrent_queue (0y%p) ", (sync_queue), (default_concurrent_queue));
        }
        
        ~shared() {
            DLogInfo(@"destroyed: sync_queue (0x%p), default_concurrent_queue (0y%p) ", (sync_queue), (default_concurrent_queue));
#if defined (DEBUG)
            // Note: at exit, the sync queue *may* still have enqueued blocks,
            // which insert/remove associations between a parent and its children
            // running on a secondary thread. At exit, this running thread will be
            // forced to terminate and the assocs container may not be clean. This
            // is considered harmless.
            if (assocs.size() != 0) {
                DLogInfo(@"Association container not empty");
            }
#endif
        }
        
    };
    
    
}

extern rxpromise::shared Shared;


@interface RXPromise (Private)
- (RXPromise_StateAndResult) peakStateAndResult;
- (RXPromise_StateAndResult) synced_peakStateAndResult;
- (id) synced_peakResult;
@end
