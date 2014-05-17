//
//  RXSettledResult.h
//  RXPromise Libraries
//
//  Created by Luke Melia on 5/13/14.
//
//

#import <Foundation/Foundation.h>

@interface RXSettledResult : NSObject

@property (nonatomic, assign, readonly, getter=isFulfilled) BOOL fulfilled;
@property (nonatomic, assign, readonly, getter=isRejected) BOOL rejected;
@property (readonly, nonatomic) id result;

-(instancetype)initWithFulfilled:(BOOL)isFulfilled andResult:(id)valueOrReason;

@end
