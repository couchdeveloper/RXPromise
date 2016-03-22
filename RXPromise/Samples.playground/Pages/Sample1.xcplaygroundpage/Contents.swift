//: [Previous](@previous)

import Foundation
import RXPromise
import XCPlayground
XCPlaygroundPage.currentPage.needsIndefiniteExecution = true

//: # Sample 1

//: Objective:
//: Invoke an asynchronous function which returns an array of items. Then, asynchronously process each item in parallel and return an array containing the processed items.


func getNames() -> RXPromise {
    let promise = RXPromise()
    dispatch_async(dispatch_get_global_queue(0, 0)) {
        let result = ["a", "b", "c", "d", "e", "f", "g", "h", "i", "j"]
        promise.fulfillWithValue(result)
    }
    return promise
}

func processName(name: String) -> RXPromise {
    let promise = RXPromise()
    dispatch_async(dispatch_get_global_queue(0, 0)) {
        let capitalizedName = name.capitalizedString
        promise.fulfillWithValue(capitalizedName)
    }
    return promise
}


func getNamesAndProcessNames() -> RXPromise {
    let promise = RXPromise()
    getNames().then( { array in
        var processedNames = [String]()
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
        },
    { error in
            [promise rejectWithReason:error];
            return nil;
    });
    return promise;
}



getNames().then({result in
    return nil
}, {error in
    return nil
})

//: [Next](@next)
