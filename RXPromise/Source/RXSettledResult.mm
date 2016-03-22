//
//  RXSettledResult.m
//  RXPromise Libraries
//
//  Created by Luke Melia on 5/13/14.
//
//

#import "RXSettledResult.h"

@implementation RXSettledResult {
    BOOL _fulfilled;
    id _result;
}

-(instancetype)initWithFulfilled:(BOOL)isFulfilled andResult:(id)valueOrReason;
{
    self = [super init];
    if (self) {
        _fulfilled = isFulfilled;
        _result = valueOrReason;
    }
    return self;
}

-(BOOL) isFulfilled {
    return _fulfilled;
}

-(BOOL) isRejected {
    return !_fulfilled;
}

@end
