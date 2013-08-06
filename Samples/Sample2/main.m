//
//  main.m
//  Sample2
//

#import <Foundation/Foundation.h>

#import <Foundation/Foundation.h>
#import <RXPromise/RXPromise.h>
#import <dispatch/dispatch.h>

/*
 Objective:
 
 Asynchronously process an array of items - one after the other. 
 Return an array of the transformed items. If an error occured return the error 
 of the failing item.
 
 Demonstrate how to cancel the sequential asynchronous tasks and how failures
 are handled.
 
 Demonstrate a "traditional" implemention utilizing dispatch lib and blocks where
 error handling may become elaborated and where cancellation is very likely
 impossible to implement.
 
 */


/**
    Dispatch and blocks only aproach
 */

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

@interface NSArray (AsyncExtension)
- (void) async_forEach(d_unary_async_t task, d_completion_t completion);
@end
@implementation NSArray (AsyncExtension)
- (void) async_forEach(d_unary_async_t task, d_completion_t completion) {
    d_transformEach(self, task, completion);
}
@end


/**
    Implementation on top of RXPromise
 */

typedef RXPromise* (^unary_async_t)(id object);

static RXPromise* do_each(NSEnumerator* iter, RXPromise* promiseResult, unary_async_t task, NSMutableArray* outArray)
{
    if (promiseResult.isCancelled) {
        return promiseResult;
    }
    id obj = [iter nextObject];
    if (obj == nil) {
        [promiseResult fulfillWithValue:outArray];
        return promiseResult;
    }
    promiseResult = task(obj).then(^id(id result){
        [outArray addObject:result];
        return do_each(iter, promiseResult, task, outArray);
    }, ^id(NSError*error){
        return error;
    });
    return promiseResult;
}

static RXPromise* transformEach(NSArray* inArray, unary_async_t task) {
    NSMutableArray* outArray = [[NSMutableArray alloc] initWithCapacity:[inArray count]];
    RXPromise* promise = [RXPromise new];
    NSEnumerator* iter = [inArray objectEnumerator];
    return do_each(iter, promise, task, outArray);
}

unary_async_t capitalize = ^RXPromise*(id object) {
    RXPromise* promise = [RXPromise new];
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        sleep(1);
        if ([object respondsToSelector:@selector(capitalizedString)]) {
            NSLog(@"processing: %@", object);
            NSString* s = [object capitalizedString];
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
        NSLog(@"Result: %@", [transformEach(@[@"a", @"b", @"c"], capitalize) get]);
        NSLog(@"Finished with RXPromise");
        
        
        NSLog(@"\n=== Started with RXPromise and input array resulting in failure ===");
        NSLog(@"Result: %@", [transformEach(@[@"a", @"b", [NSNull null]], capitalize) get]);
        NSLog(@"Finished with with RXPromise and input array resulting in failure");
        
        
        NSLog(@"\n===Started with RXPromise and cancelleing after 2 seconds ===");
        RXPromise* result = transformEach(@[@"a", @"b", @"c", [NSObject new]], capitalize);
        sleep(2);
        NSLog(@"cancelling...");
        [result cancel];
        NSLog(@"Result: %@", [result get]);
        NSLog(@"Finished with with RXPromise and cancelleing");
    }
    return 0;
}
