//
//  main.m
//  Sample2
//

#import <Foundation/Foundation.h>

#import <Foundation/Foundation.h>
#import <RXPromiseForAll/RXPromiseForAll.h>
#import <dispatch/dispatch.h>

/*
 Objective:
 
 Asynchronously process an array of items - one after the other. 
 Return an array of the transformed items. If an error occured during processing
 the items stop iterating and return the error of the failing item.
 
 Demonstrate how to cancel the sequential asynchronous tasks and how failures
 are handled.
 
 Demonstrate a "traditional" implemention utilizing dispatch lib and blocks where
 error handling may become elaborated and where cancellation is very likely
 impossible to implement.
 

 see also: RXPromise' class method `sequence:task:`
 
 */


/*******************************************************************************
    1. Utilizing dispatch and blocks
*******************************************************************************/

typedef void (^d_completion_t)(id result);
typedef void (^d_unary_async_t)(id input, d_completion_t completion);

static void d_transformEach(NSArray* inArray, d_unary_async_t task, d_completion_t completion);

static void d_do_each(NSEnumerator* iter, d_unary_async_t task, NSMutableArray* outArray, d_completion_t completion)
{
    id obj = [iter nextObject];
    if (obj == nil) {
        if (completion)
            completion([outArray copy]);
        return;
    }
    task(obj, ^(id result){
        [outArray addObject:result];
        d_do_each(iter, task, outArray, completion);
    });
}

static void d_transformEach(NSArray* inArray, d_unary_async_t task, d_completion_t completion) {
    NSMutableArray* outArray = [[NSMutableArray alloc] initWithCapacity:[inArray count]];
    NSEnumerator* iter = [inArray objectEnumerator];
    d_do_each(iter, task, outArray, completion);
}

d_unary_async_t d_capitalize = ^(id input, d_completion_t completion) {
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        sleep(1);
        if ([input respondsToSelector:@selector(capitalizedString)]) {
            NSLog(@"processing: %@", input);
            NSString* result = [input capitalizedString];
            if (completion)
                completion(result);
        }
    });
};


/*******************************************************************************
  2. Utilizing RXPromise

    Note: this simplified aproach does not forward the cancel signal sent to the
    returned promise to the _current active task_. A cancellation only stops the
    iteration.
 ******************************************************************************/

@interface RXPromiseWrapper : NSObject
@property (nonatomic) RXPromise* promise;
@end
@implementation RXPromiseWrapper
@end


typedef RXPromise* (^unary_async_t)(id object);

static void do_transformSequence(NSEnumerator* iter, RXPromise* returnedPromise,
                                 unary_async_t task, NSMutableArray* outArray,
                                 RXPromiseWrapper* currentTaskPromise,
                                 dispatch_queue_t sync_queue)
{
    if (returnedPromise.isCancelled) {
        return;
    }
    id obj = [iter nextObject];
    if (obj == nil) {
        [returnedPromise fulfillWithValue:outArray];
        return;
    }
    currentTaskPromise.promise = task(obj);
    currentTaskPromise.promise.thenOn(sync_queue, ^id(id result){
        [outArray addObject:result];
        do_transformSequence(iter, returnedPromise, task, outArray, currentTaskPromise, sync_queue);
        return nil; // result not used
    }, ^id(NSError*error){
        [returnedPromise rejectWithReason:error];
        return nil; // result not used
    });
}

static RXPromise* transformSequence(NSArray* inArray, unary_async_t task) {
    NSMutableArray* outArray = [[NSMutableArray alloc] initWithCapacity:[inArray count]];
    RXPromise* returnedPromise = [RXPromise new];
    RXPromiseWrapper* currentTaskPromise = [[RXPromiseWrapper alloc] init];
    NSEnumerator* iter = [inArray objectEnumerator];
    dispatch_queue_t sync_queue = dispatch_queue_create("sync_queue", 0);
    
    dispatch_sync(sync_queue, ^{
        do_transformSequence(iter, returnedPromise, task, outArray, currentTaskPromise, sync_queue);

        // Register an error handler which cancels the current task's root:
        returnedPromise.thenOn(sync_queue, nil, ^id(NSError*error){
            NSLog(@"cancelling current task promise's root: %@", currentTaskPromise.promise.root);
            [currentTaskPromise.promise.root cancelWithReason:error];
            return error;
        });
    });
    
    return returnedPromise;
}

unary_async_t capitalize = ^RXPromise*(id object) {
    RXPromise* promise = [RXPromise new];
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        NSLog(@"processing: %@", object);
        int count = 1000;
        while (count-- && promise.isPending) {
            usleep(1000);
        }
        if (!promise.isPending) {
            NSLog(@"task cancelled");
            return;
        }
        if ([object respondsToSelector:@selector(capitalizedString)]) {
            NSString* s = [object capitalizedString];
            NSLog(@"finished processing with result: %@", s);
            [promise fulfillWithValue:s];
        }
        else {
            [promise rejectWithReason:[NSString stringWithFormat:@"Object [%@] does not respond to capitalize", [object class]]];
        }
    });
    return promise;
};


int main(int argc, const char * argv[])
{
    @autoreleasepool {
        
        NSLog(@"\n=== Started with traditional dispatch and completion blocks ===");
        dispatch_semaphore_t sem = dispatch_semaphore_create(0);
        d_transformEach(@[@"a", @"b", @"c"], d_capitalize, ^(id result){
            NSLog(@"Result: %@", result);
            dispatch_semaphore_signal(sem);
        });
        dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
        NSLog(@"Finished with completion blocks");
        
        NSLog(@"\n=== Started with RXPromise ===");
        NSLog(@"Result: %@", [transformSequence(@[@"a", @"b", @"c"], capitalize) get]);
        NSLog(@"Finished with RXPromise");
        
        
        NSLog(@"\n=== Started with RXPromise and input array resulting in failure ===");
        NSLog(@"Result: %@", [transformSequence(@[@"a", @"b", [NSNull null]], capitalize) get]);
        NSLog(@"Finished with with RXPromise and input array resulting in failure");
        
        
        NSLog(@"\n===Started with RXPromise and cancelleing after 2 seconds ===");
        RXPromise* result = transformSequence(@[@"a", @"b", @"c", [NSObject new]], capitalize);
        sleep(2);
        NSLog(@"cancelling...");
        [result cancel];
        NSLog(@"Result: %@", [result get]);
        NSLog(@"Finished with RXPromise and cancelleing");
    }
    return 0;
}
