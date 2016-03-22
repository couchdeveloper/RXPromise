//
//  main.m
//  Sample5
//
//  Objective: Chaining asynchronous tasks from an array of objects
//
//  Given:
//      - an array of input values
//      - an asychronous function processing an input value
//
// also: Delayed Task with Cancellation


#import <Foundation/Foundation.h>
#import <RXPromise/RXPromise.h>

#import <dispatch/dispatch.h>
#import "RXTimer.h"



// As an example add a category for NSString to simulate an asynchronous task
// (Actually, this is a delayed task with cancellation)
@implementation NSString (Example)

- (RXPromise*) asyncTask
{
    RXPromise* promise = [[RXPromise alloc] init];
    
    RXTimerHandler block = ^(RXTimer* timer) {
        id result = [self capitalizedString];
        [promise fulfillWithValue:result];
    };
    RXTimer* timer = [[RXTimer alloc] initWithTimeIntervalSinceNow:0.5
                                                         tolerance:0.1
                                                             queue:dispatch_get_global_queue(0, 0)
                                                             block:block];
    promise.then(nil, ^id(NSError*error){
        [timer cancel];
        NSLog(@"Operation with receiver '%@' cancelled", self);
        return nil;
    });

    [timer start];
    //NSLog(@"Creating task promise: %@", promise);
    return promise;
}

@end



int main(int argc, const char * argv[])
{
    @autoreleasepool {
        
        NSArray* inputs = @[@"a", @"b", @"c", @"d", @"e", @"f", @"g"];
        
        RXPromise* finished = [RXPromise sequence:inputs task:^RXPromise*(id input) {
            return [input asyncTask]
            .thenOn(dispatch_get_main_queue(), ^id(id result) {
                printf("%s", [[result description] UTF8String]);
                return nil;
            }, nil);
        }];
        
        [finished runLoopWait];
        printf("\n");
        
        
        // Again with a timeout, cancelling the operations:

        finished = [RXPromise sequence:inputs task:^RXPromise*(id input) {
            return [input asyncTask]
            .thenOn(dispatch_get_main_queue(), ^id(id result) {
                printf("%s", [[result description] UTF8String]);
                return nil;
            }, nil);
        }];
        
        
        // A timeout will cause to signal an error to the promise, which in turn causes
        // the sequence to cancel the current task's root promise:
        [finished setTimeout:1.25];
        
        
//        finished.then(nil, ^id(NSError*error){
//            [finished.parent cancel];  // the task promise is the finished's parent promise
//            return nil;
//        });
        
        [finished runLoopWait];
        sleep(1);
        printf("\n");
        
    }
    return 0;
}

