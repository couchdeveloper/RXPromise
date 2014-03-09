//
//  main.m
//  Sample8
//
//  Created by Andreas Grosam on 06.03.14.
//
//

#import <Foundation/Foundation.h>
#import <RXPromise/RXPromise.h>
#include <dispatch/dispatch.h>


/**
 
 Demonstrates:
 
 Returned objects with retain count +1 in handlers *may* be autoreleased.
 Hence, handlers which create objects and return it as the return value
 in a handler shall use an autorelease pool.
 
 */

@interface MyObject : NSObject
@end
@implementation MyObject
- (id)init
{
    self = [super init];
    if (self) {
        ;
    }
    NSLog(@"+++ Object created: 0x%p", (__bridge void*)self);
    return self;
}

- (void) dealloc {
    NSLog(@"-- Object destroyed: 0x%p", (__bridge void*)self);
}
@end




NS_RETURNS_RETAINED static RXPromise*  async()  {
    RXPromise* promise = [[RXPromise alloc] init];
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        usleep(1000);
        [promise fulfillWithValue:@"OK"];
    });
    return promise;
}

int test()
{
    @autoreleasepool {
        dispatch_semaphore_t sem = dispatch_semaphore_create(0);
        
        async().then(^id(id result) {
            return [[MyObject alloc] init];
        }, nil)
        .then(^id(id result) {
            return [[MyObject alloc] init];
        }, nil)
        .then(^id(id result) {
            return [[MyObject alloc] init];
        }, nil)
        .then(^id(id result) {
            return [[MyObject alloc] init];
        }, nil)
        .then(^id(id result) {
            return [[MyObject alloc] init];
        }, nil)
        .then(^id(id result) {
            return [[MyObject alloc] init];
        }, nil)
        .then(^id(id result) {
            dispatch_semaphore_signal(sem);
            return nil;
        }, nil);
        
        dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
        
        sleep(1);
    }
    
    return 0;
}


int main(int argc, const char * argv[])
{
    @autoreleasepool {
        NSLog(@"start");
        for (int i = 0; i < 10; ++i) {
            test();
        }
        NSLog(@"finished");
    }
    return 0;
}

