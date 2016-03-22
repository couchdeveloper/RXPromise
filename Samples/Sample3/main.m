//
//  main.m
//  Sample3
//

#import <Foundation/Foundation.h>
#import <RXPromise/RXPromise.h>


/*
 
 Objective:  Sequencially invoke N times an asynchronous function.
 
 See also: RXPromise' class method `sequence:task:`
 
 */


typedef RXPromise* (^task_block_t)(void);


/**
 
 @brief Call the task _task_ N times asynchrounously in sequence. The function 
 _times_ forms itself an asynchronous task.
 
 @discussion The result value of each task is ignored (one might define a
 "task-completion" block in order to achieve that).
 
 When the task _times_ will be cancelled, it cancelles the current active 
 task and stops by rejecting its promise.
 
 @param n The number of times _task_ shall be invoked.

 @param task The task to be invoked.
 
 @return A promise.
 
 */
RXPromise* times(int n, task_block_t task);




static RXPromise* do_times(int n, task_block_t task, RXPromise* returnedPromise)
{
    promise_completionHandler_t onSuccess = ^id(id result) {
        do_times(n-1, task, returnedPromise);
        return nil;
    };
    promise_errorHandler_t onError = ^id(NSError*error){
        [returnedPromise rejectWithReason:error];
        return nil;
    };
    
    if (n == 0) {
        [returnedPromise fulfillWithValue:@"OK"];
        return returnedPromise;
    }
    if (returnedPromise.isCancelled) {
        return returnedPromise;
    }
#if 1
    task().then(onSuccess, onError);
#else
    [task() registerWithQueue:dispatch_get_global_queue(0, 0)
                    onSuccess:onSuccess
                    onFailure:onError
                returnPromise:NO];
    
#endif
    return returnedPromise;
}

RXPromise* times(int n, task_block_t task)
{
    RXPromise* returnedPromise = [RXPromise new];
    do_times(n, task, returnedPromise);
    return returnedPromise;
}

// Some nasty workload:
unsigned int fibonacci_recursive(unsigned int n)
{
    if (n == 0) {
        return 0;
    }
    if (n == 1) {
        return 1;
    }
    return fibonacci_recursive(n - 1) + fibonacci_recursive(n - 2);
}


int main(int argc, const char * argv[])
{
    RXPromise* promise =[RXPromise new];
    NSArray* promises = @[promise];
    RXPromise* promiseAll = [RXPromise all: promises];
    
    @autoreleasepool {
        NSLog(@"This sample is meant to be profiled. It may take a while to finish.");
        
#if 1
        // The time it takes to finish one fibonacci_recursive(30) call is roughly
        // 15 ms. fibonacci_recursive is a CPU bound operation.
        // Profiling reveals, that in this setup the overhead due to promises is
        // merely 0.5% (99.5% time spent in function fibonacci_recursive).
        // Four threads are in use (main thread which is blocked and three
        // dispatch worker threads).
        NSLog(@"start\n");
        [times(1000, ^RXPromise*(){
                RXPromise* promise = [RXPromise new];
                __block int result;
                dispatch_async(dispatch_get_global_queue(0, 0), ^{
                    result = fibonacci_recursive(30);
                    [promise fulfillWithValue:[NSNumber numberWithInt:result]];
                });
                return promise;
            })
         wait];
        NSLog(@"finished\n");
#else
        // For comparision:
        // This code seems to benefit from a better utilization of CPU caches
        // - which makes the fibonacci code about 15% faster than above.
        // Only one thread is used.
        
        int r = 0;
        NSLog(@"start\n");
        for (int i = 0; i < 1000; ++i) {
            int result = fibonacci_recursive(30);
            NSNumber* number = [NSNumber numberWithInt:result];
            r += result;
            number = nil;
        }
        NSLog(@"finished %d\n", r);
#endif
    }
    
    
    return 0;
}

