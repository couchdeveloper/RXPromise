//
//  main.m
//  Sample2
//

#import <Foundation/Foundation.h>

#import <Foundation/Foundation.h>
#import <RXPromise/RXPromise.h>

/*
 Objective:
 
 Asynchronously process an array of items - one after the other. 
 Return an array of the transformed items. If an error occured
 return the error of the failing item.
 
 */


typedef RXPromise* (^unary_async_t)(id object);

static RXPromise* transform(NSArray* array, unary_async_t task);


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
            NSString* s = [object capitalizedString];
            [promise fulfillWithValue:s];
        }
        else {
            [promise rejectWithReason:@"Object does not respond to capitalize"];
        }
    });
    return promise;
};


int main(int argc, const char * argv[])
{
    @autoreleasepool {
        NSLog(@"Started");
        NSLog(@"processedNames: %@", [transformEach(@[@"a", @"b", @"c"], capitalize) get]);
        NSLog(@"processedNames: %@", [transformEach(@[@"a", @"b", @"c", [NSObject new]], capitalize) get]);
        
        RXPromise* result = transformEach(@[@"a", @"b", @"c", [NSObject new]], capitalize);
        sleep(2);
        [result cancel];
        NSLog(@"processedNames: %@", [result get]);
        NSLog(@"Finished");

    }
    return 0;
}
