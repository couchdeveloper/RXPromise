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

//static void work_for(RXPromise*promise, double duration, dispatch_queue_t queue, double interval, completion_t completion) {
//    if (promise.isCancelled)
//        return;
//    __block double t = duration;
//    if (t > 0) {
//        dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(std::min(interval, t) * NSEC_PER_SEC));
//        dispatch_after(popTime, queue, ^(void) {
//            //printf(".");
//            if (promise.isCancelled)
//                return;
//            else if (t > interval)
//                work_for(promise, t-interval, queue, completion);
//            else {
//                //printf("\n");
//                completion();
//            }
//        });
//    }
//    else {
//        //printf("\n");
//        completion();
//    }
//}
//
//static RXPromise* async(double duration, id result) {
//    RXPromise* promise = [RXPromise new];
//    dispatch_queue_t queue = dispatch_get_global_queue(0, 0);
//    work_for(promise, duration, queue, 0.1, ^{
//        [promise fulfillWithValue:result];
//    });
//    return promise;
//}
//


static RXPromise* async(int n) {
    RXPromise* promise = [[RXPromise alloc] init];
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        //printf(".");
        [promise fulfillWithValue:[NSNumber numberWithInt:n]];
    });
    return promise;
}


static RXPromise* chain(int n)
{
    return async(n)
    .then(^id(id result_){
        int x = [result_ intValue];
        if (x>0){
            return chain(n-1);
        } else {
            return @"Done";
        }
    }, ^id(NSError*error){
        return error;
    });
}



typedef RXPromise* (func_t)(int n);

static void do_each(int n, func_t task, RXPromise* result)
{
    if (n == 0) {
        return [result fulfillWithValue:@"Done"];
    }
    task(n).then(^id(id number){
        do_each(n-1, task, result);
        return number;
    }, ^id(NSError*error){
        return error;
    });
}

static RXPromise* each(int n, func_t task)
{
    RXPromise* result = [[RXPromise alloc] init];
    do_each(n, task, result);
    return result;
}




int main(int argc, const char * argv[])
{
    for (int i = 0; i < 100 ; ++i) {
        @autoreleasepool {
            RXPromise* result = each(1000, async);
            [result wait];
            
            printf("Result: %s\n", [[[result get] description] UTF8String]);
            printf("promise: %s\n", [[result description] UTF8String]);
        }
    }
    return 0;
}

