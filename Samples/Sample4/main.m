//
//  main.m
//  NSArrayExtension
//
//  Created by Andreas Grosam on 16.07.13.
//
//

#import <Foundation/Foundation.h>
#import <RXPromise/RXPromise.h>

typedef RXPromise* (^unary_async_t)(id object);

static RXPromise* serial_for_each(NSArray* array, unary_async_t task);


static RXPromise* do_serial_each(NSEnumerator* iter, RXPromise* promiseResult, unary_async_t task)
{
    if (!promiseResult.isPending) {
        return promiseResult;
    }
    id obj = [iter nextObject];
    if (obj == nil) {
        [promiseResult fulfillWithValue:nil];
        return promiseResult;
    }
    RXPromise* p = task(obj).then(^id(id result){
        /* result ignored */
        return do_serial_each(iter, promiseResult, task);
    }, ^id(NSError*error){
        [promiseResult rejectWithReason:error];
        return nil;
    });
    promiseResult.then(nil, ^id(NSError* error) {
        [p cancel];
        return nil;
    });
    
    return promiseResult;
}

static RXPromise* serial_for_each(NSArray* inArray, unary_async_t task) {
    RXPromise* promise = [RXPromise new];
    NSEnumerator* iter = [inArray objectEnumerator];
    return do_serial_each(iter, promise, task);
}

static RXPromise* concurrent_for_each(NSArray* inArray, unary_async_t task) {
    NSUInteger count = [inArray count];
    NSMutableArray* promises = [[NSMutableArray alloc] initWithCapacity:count];
    for (int i = 0; i < count; ++i)  {
        [promises addObject:task([inArray objectAtIndex:i])];
    }
    return [RXPromise all:promises];
}



@interface NSArray (RXExtension)

- (RXPromise*) rx_serialForEach:(unary_async_t)task;
- (RXPromise*) rx_concurrentForEach:(unary_async_t)task;

@end

@implementation NSArray (RXExtension)

- (RXPromise*) rx_serialForEach:(unary_async_t)task {
    return serial_for_each(self, task);
}

- (RXPromise*) rx_concurrentForEach:(unary_async_t)task {
    return concurrent_for_each(self, task);
}

@end


static RXPromise* processName(NSString* name) {
    RXPromise* promise = [RXPromise new];
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        NSString* capitalizedName = [name capitalizedString];
        int count = 1000;
        while (count--) {
            if ([promise isCancelled])
                break;
            usleep(1000);
        }
        if (![promise isCancelled]) {
            if ([@"X" isEqualToString:capitalizedName]) {
                [promise rejectWithReason:@"X"];
            } else {
                [promise fulfillWithValue:capitalizedName];
            }
        }
        else {
            NSLog(@"cancelled");
        }
    });
    return promise;
}



int main(int argc, const char * argv[])
{
    @autoreleasepool {
        
        NSArray* a1 = @[@"a", @"b", @"c", @"d", @"e"];
        NSLog(@"ForEach Serial");

        [[a1 rx_serialForEach:^RXPromise *(id object) {
            RXPromise* taskPromise = processName(object);
            RXPromise* returnedPromise = taskPromise.then(^id(id result) {
                NSLog(@"%@", result);
                return result;
            }, nil);
            returnedPromise.then(nil,
                                 ^id(NSError* error) {
                                     [taskPromise cancel];
                                     return error;
                                 });
            return returnedPromise;
        }]
        .then(nil, ^id(NSError* error) {
            NSLog(@"ERROR: %@", error);
            return nil;
        }) wait];
        
        
        RXPromise* all = [a1 rx_concurrentForEach:^RXPromise*(id object) {
            RXPromise* taskPromise = processName(object);
            RXPromise* returnedPromise = taskPromise.then(^id(id result) {
                NSLog(@"%@", result);
                return result;
            }, nil);
            returnedPromise.then(nil,
            ^id(NSError* error) {
                [taskPromise cancel];
                return error;
            });
            return returnedPromise;
        }];
        
        all.then(nil, ^id(NSError* error) {
            NSLog(@"ERROR: %@", error);
            return nil;
        });
        
        NSLog(@"ForEach Concurrent");
        NSLog(@"Start");
        [all wait];
        NSLog(@"End");
        
    }
    return 0;
}

