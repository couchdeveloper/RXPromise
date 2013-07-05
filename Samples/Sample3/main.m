//
//  main.m
//  Sample3
//

#import <Foundation/Foundation.h>
#import <RXPromise/RXPromise.h>


/*
 
 Objective:  Sequencially invoke N times an asynchronous function.
 
 */


typedef RXPromise* (^task_block_t)(void);

static RXPromise* do_times(int n, task_block_t task, RXPromise* promise);

static RXPromise* times(int n, task_block_t task)
{
    RXPromise* promise = [RXPromise new];
    do_times(n, task, promise);
    return promise;
}

static RXPromise* do_times(int n, task_block_t task, RXPromise* promise)
{
    if (n == 0) {
        [promise fulfillWithValue:@"OK"];
        return promise;
    }
    if (promise.isCancelled) {
        return promise;
    }
    task().then(^id(id result) {
        do_times(n-1, task, promise);
        return nil;
    }, ^id(NSError*error){
        [promise rejectWithReason:error];
        return nil;
    });
    return promise;
}





int main(int argc, const char * argv[])
{
    printf("start\n");
    @autoreleasepool {
        [times(1000, ^RXPromise*(){
            //printf(".");
            RXPromise* promise = [RXPromise new];
            [promise fulfillWithValue:@"OK"];
            return promise;
        }) wait];
    }
    printf("finished\n");
    return 0;
}

