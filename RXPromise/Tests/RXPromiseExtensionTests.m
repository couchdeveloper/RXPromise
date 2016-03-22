//
//  RXPromiseExtensionTests.m
//  RXPromise
//
//  Created by Andreas Grosam on 22/03/16.
//
//

#if !defined(DEBUG_LOG)
#warning DEBUG_LOG not defined
#endif

#import <XCTest/XCTest.h>

#import <RXPromise/RXPromise.h>

@interface RXPromiseExtensionTests : XCTestCase

@end

@implementation RXPromiseExtensionTests

- (void)setUp {
    [super setUp];
    // Put setup code here. This method is called before the invocation of each test method in the class.
}

- (void)tearDown {
    // Put teardown code here. This method is called after the invocation of each test method in the class.
    [super tearDown];
}

- (void)testExample {
    RXPromise* promise = [RXPromise promiseWithResult:@"OK"];
    
    [RXPromise all:@[promise]].then(^id(id result) {
        return nil;
    }, ^id(id error ) {
        return nil;
    });
}


@end
