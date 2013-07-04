//
//  main.m
//  Chain
//
//  Created by Andreas Grosam on 03.06.13.
//
//

#import <Foundation/Foundation.h>
#import <RXPromise/RXPromise.h>

typedef void (^completion_t)();


// An unary task takes one parameter and returns a RXPromise
typedef RXPromise* (^unary_async_t)(id param);



static void do_each(NSEnumerator* iter, unary_async_t task, RXPromise* promiseResult)
{
    if (promiseResult.isCancelled) {
        return;
    }
    id obj = [iter nextObject];
    if (obj == nil) {
        [promiseResult fulfillWithValue:@"Done"];
        return;
    }
    task(obj).then(^id(id result){
        do_each(iter, task, promiseResult);
        return result;
    }, ^id(NSError*error){
        return error;
    });
}

static RXPromise* sequence(NSArray* array, unary_async_t task)
{
    NSEnumerator* iter = [array objectEnumerator];
    RXPromise* result = [[RXPromise alloc] init];
    do_each(iter, task, result);
    return result;
}




@implementation NSArray (RX_extensions)

- (RXPromise*) async_each:(unary_async_t) task {
    return sequence(self, task);
}

@end


int main(int argc, const char * argv[])
{
    @autoreleasepool {
        
        // Define a task which takes 1 second to run.
        double delayInSeconds = 1.0;
        unary_async_t task = ^(id obj) {
            RXPromise* promise = [[RXPromise alloc] init];
            dispatch_async(dispatch_get_global_queue(0, 0), ^{
                NSLog(@"Start: %@", obj);
                dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayInSeconds * NSEC_PER_SEC));
                dispatch_after(popTime, dispatch_get_global_queue(0, 0), ^(void){
                    NSLog(@"End: %@", obj);
                    [promise fulfillWithValue:obj];
                });
            });
            return promise;
        };
        
        
        // Create a number of inputs which will be passed to the task's parameter _param_
        NSArray* inputArray = @[@"A", @"B", @"C", @"D", @"E", @"F", @"G", @"H", @"I", @"J"];
        RXPromise* result = [inputArray async_each:task];
        [result wait];
        
//        printf("Result: %s\n", [[[result get] description] UTF8String]);
//        printf("promise: %s\n", [[result description] UTF8String]);
    }
    return 0;
}

