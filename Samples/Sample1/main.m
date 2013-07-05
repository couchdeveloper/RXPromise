//
//  main.m
//  Sample1
//

#import <Foundation/Foundation.h>
#import <RXPromise/RXPromise.h> 

/*
    Objective:  
 
    Invoke an asynchronous function which returns an array of items.
    Then, asynchronously process each item in parallel and return an 
    array containing the processed items.
 
    Note: 
 

 */



static RXPromise* getNames() {
    RXPromise* promise = [RXPromise new];
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        NSArray* result = @[@"a", @"b", @"c", @"d", @"e", @"f", @"g", @"h", @"i", @"j"];
        [promise fulfillWithValue:result];
    });    
    return promise;
}

static RXPromise* processName(NSString* name) {
    RXPromise* promise = [RXPromise new];
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        NSString* capitalizedName = [name capitalizedString];
        [promise fulfillWithValue:capitalizedName];
    });
    return promise;
}


static RXPromise* getNamesAndProcessNames() {
    RXPromise* promise = [RXPromise new];    
    getNames().then(^id(id array){
        NSMutableArray* processedNames = [[NSMutableArray alloc] init];
        __block NSUInteger count = [array count];
        for (NSString* name in array) {
            processName(name).then(^id(id processedName) {
                [processedNames addObject:processedName];
                --count;
                if (count == 0) {
                    [promise fulfillWithValue:processedNames];
                }
                return nil;
            }, ^id(NSError* error) {
                [promise rejectWithReason:error];
                return nil;
            });
        }
        return nil;
    }, ^id(NSError* error){
        [promise rejectWithReason:error];
        return nil;
    });
    return promise;
}



int main(int argc, const char * argv[])
{
    @autoreleasepool {
        RXPromise* result = getNamesAndProcessNames();
        NSArray* processedNames = [result get];
        NSLog(@"processedNames: %@", processedNames);
    }
    return 0;
}

