//
//  main.m
//  Sample7
//
//  Created by Andreas Grosam on 26.02.14.
//
//

#import <Foundation/Foundation.h>
#import <RXPromise/RXPromise.h>
#import <RXPromise/RXPromise+RXExtension.h>


/**
 
 Objective: Demonstrate how to use `repeat`.
 
 */


// As an example add a category for NSString to simulate an asynchronous task
@implementation NSString (Example)

- (RXPromise*) asyncTask
{
    RXPromise* promise = [[RXPromise alloc] init];
    
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        int count = 10;
        while (count--) {
            usleep(100*1000);
        }
        if ([self isEqualToString:@"X"]) {
            [promise rejectWithReason:@"Bad Input"];
        }
        else {
            [promise fulfillWithValue:[self capitalizedString]];
        }
    });
    
    return promise;
}

@end


// Contains a more or less "canonical" implementation of the "asynchronous loop"
// with the class method `repeat`.
RXPromise* performTasksWithArray(NSArray* inputs)
{
    const NSUInteger count = [inputs count];
    __block NSUInteger i = 0;
    return [RXPromise repeat:^id{
        if (i >= count) {
            return @"final value";
        }
        return [inputs[i++] asyncTask].then(^id(id result){
            NSLog(@"%@", result);
            return nil;  // intermediate result not used in repeat
        }, nil);
    }];
}


int main(int argc, const char * argv[])
{
    @autoreleasepool {
        
        NSArray* inputs = @[@"a", @"b", @"c", @"X", @"e", @"f", @"g"];
        
        [performTasksWithArray(inputs)
        .then(^id(id result){
            NSLog(@"Finished: %@", result);
            return nil;
        }, ^id(NSError* error){
            NSLog(@"Error occured: %@", error);
            return nil;
        }) runLoopWait];
        
    }
    return 0;
}

