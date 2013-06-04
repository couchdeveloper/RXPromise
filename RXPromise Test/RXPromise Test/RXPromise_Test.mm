//
//  RXPromise_Test.mm
//
//  If not otherwise noted, the content in this package is licensed
//  under the following license:
//
//  Copyright 2013 Andreas Grosam
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.

#import "RXPromise_Test.h"
#import "RXPromise/RXPromise.h"
#include <dispatch/dispatch.h>
#include <algorithm>  // std::min
#include <string>


#if defined (NDBEUG)
#error NDEBUG shall not be defined for testing.
#endif

#pragma mark  Semaphore

class semaphore {
public:
    typedef double      duration_type;
    
    
    static duration_type wait_forever() { return -1.0; }
    
    semaphore(const semaphore&) = delete;
    semaphore& operator=(const semaphore&) = delete;
    
    explicit semaphore(long n = 0) : sem_(dispatch_semaphore_create(n)) {
        assert(sem_);
    }
    
    ~semaphore() {
        dispatch_semaphore_t tmp = sem_;
        sem_ = 0;
        int count = 0;
        while (dispatch_semaphore_signal(tmp)) {
            ++count;
            usleep(100);  // this is primarily a workaround for an issue in lib dispatch
#if defined (DEBUG)
            printf("warning semaphore: resumed waiting thread in d-tor\n");
#endif
        }
        dispatch_release(tmp);
    }
    
    void signal()  {
        dispatch_semaphore_signal(sem_);
    }
    
    bool wait()  {
        long result = dispatch_semaphore_wait(sem_, DISPATCH_TIME_FOREVER);
        if (sem_ == 0) {
            throwInterrupted();
        }
        return result == 0;
    }
    
    bool wait(semaphore::duration_type timeout_sec)  {
        long result = dispatch_semaphore_wait(sem_,
                                              timeout_sec >= 0 ?
                                              dispatch_time(DISPATCH_TIME_NOW, timeout_sec*NSEC_PER_SEC)
                                              : DISPATCH_TIME_FOREVER);
        if (sem_ == 0) {
            throwInterrupted();
        }
        return result == 0;
    }
    
private:
    void throwInterrupted() {
        //throw std::runtime_error("interrupted");
    }
    
private:
    dispatch_semaphore_t sem_;
};



@class RXPromise;

#pragma mark AsyncOperation Mock

@interface AsyncOperation : NSOperation

- (id)initWithLabel:(NSString*)label workCount:(NSInteger)count workerQueue:(dispatch_queue_t)workerQueue;
- (id)initWithLabel:(NSString*)label workCount:(NSInteger)count;

- (void) failAtStep:(NSInteger)step withReason:(id)reason;

@property (nonatomic, readwrite) BOOL   isExecuting;
@property (nonatomic, readwrite) BOOL   isFinished;
@property (nonatomic, readwrite) BOOL   terminating;
@property (nonatomic, readonly) id      result;
@property (nonatomic) NSString*         label;
@property (nonatomic) RXPromise*        promise;
@property (nonatomic) double            timeInterval;

@end

@interface AsyncOperation ()
@property (nonatomic, readwrite) id      result;
@end


@implementation AsyncOperation {
    int32_t                 _ID;
    dispatch_queue_t        _workerQueue;
    NSInteger               _workCount;
    NSString*               _label;
    id                      _result;
    double                  _timeInterval;
    NSInteger               _step;
    id                      _failureReason;
    NSInteger               _failAtStep;
}

static int32_t s_ID = 0;


@synthesize isExecuting =   _isExecuting;   // explicitly implemented
@synthesize isFinished =    _isFinished;    // explicitly implemented
@synthesize promise =       _promise;
@synthesize result  =       _result;
@synthesize label   =       _label;
@synthesize timeInterval =  _timeInterval;


- (id)initWithLabel:(NSString*)label workCount:(NSInteger)count workerQueue:(dispatch_queue_t)workerQueue
{
    NSParameterAssert(workerQueue);
    
    self = [super init];
    if (self) {
        _label = label;
        _workCount = count;
        dispatch_retain(workerQueue);
        _workerQueue = workerQueue;
        _ID = OSAtomicIncrement32Barrier(&s_ID);
        _timeInterval = 0.1;
        _failAtStep = -1;
    }
    return self;
}

- (id)initWithLabel:(NSString*)label workCount:(NSInteger)count {
    return [self initWithLabel:label workCount:count workerQueue:dispatch_get_global_queue(0, 0)];
}


- (void) failAtStep:(NSInteger)step withReason:(id)reason {
    _failAtStep = step;
    _failureReason = reason;
}



- (void) dealloc {
    dispatch_release(_workerQueue);
}

- (void) doWork
{
    if (self.isCancelled) {
        self.result = [NSString stringWithFormat:@"Operation %@ cancelled with work items left: %ld",
                       _label, _workCount - _step];
        [self terminate];
        return;
    }
    if (_step == _failAtStep) {
        self.result = _failureReason;
        [self terminate];
    }
    if (_step == _workCount) {
        self.result = [NSString stringWithFormat:@"Operation %@ finished with result: %ld",
                       _label, _workCount];
        [self terminate];
        return;
    }
    dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(_timeInterval * NSEC_PER_SEC));
    dispatch_after(popTime, _workerQueue, ^(void){
#if defined (LOG_VERBOSE)
        printf("%p: %ld\n", self, (long)_workCount);
#endif
        _step++;
        [self.promise setProgress:[NSNumber numberWithInteger:_workCount]];
        [self doWork];
    });
}

- (void) start
{
    if (self.isCancelled || self.isFinished || self.isExecuting) {
        return;
    }
    self.isExecuting = YES;
    [self doWork];
}

- (BOOL) isCancelled {
    return [super isCancelled];
}
- (void) cancel {
    [super cancel];
}

- (BOOL) isExecuting {
    return _isExecuting;
}
- (void) setIsExecuting:(BOOL)isExecuting {
    if (_isExecuting != isExecuting) {
        [self willChangeValueForKey:@"isExecuting"];
        _isExecuting = isExecuting;
        [self didChangeValueForKey:@"isExecuting"];
    }
}

- (BOOL) isFinished {
    return _isFinished;
}
- (void) setIsFinished:(BOOL)isFinished {
    if (_isFinished != isFinished) {
        [self willChangeValueForKey:@"isFinished"];
        _isFinished = isFinished;
        [self didChangeValueForKey:@"isFinished"];
    }
}

- (void) terminate {
    self.isFinished = YES;
    self.isExecuting = NO;
    if ([self.result isKindOfClass:[NSError class]] || _step == _failAtStep) {
        [self.promise rejectWithReason:self.result];
    } else {
        [self.promise fulfillWithValue:self.result];
    }
}


@end


#pragma mark - Async Mocks



typedef void (^completion_t)();

static RXPromise* asyncOp(NSString* label, int workCount, NSOperationQueue* queue = NULL,
                          double interval = 0.1,
                          int failsAtStep = -1, id failureReason = nil)
{
    if (queue == NULL) {
        queue = [[NSOperationQueue alloc] init];
        queue.maxConcurrentOperationCount = 1;
    }
    AsyncOperation* op = [[AsyncOperation alloc] initWithLabel:label workCount:workCount];
    op.timeInterval = interval;
    if (failsAtStep >= 0) {
        [op failAtStep:failsAtStep withReason:failureReason];
    }
    op.promise = [[RXPromise alloc] init];
    [queue addOperation:op];
    
    return op.promise;
}

static void work_for(RXPromise*promise, double duration, dispatch_queue_t queue, completion_t completion, double interval = 0.1) {
    if (promise.isCancelled)
        return;
    __block double t = duration;
    if (t > 0) {
        dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(std::min(interval, t) * NSEC_PER_SEC));
        dispatch_after(popTime, queue, ^(void) {
            //printf(".");
            if (promise.isCancelled)
                return;
            else if (t > interval)
                work_for(promise, t-interval, queue, completion);
            else {
                //printf("\n");
                completion();
            }
        });
    }
    else {
        //printf("\n");
        completion();
    }
}



static RXPromise* async(double duration, id result = @"OK", dispatch_queue_t queue = NULL) {
    RXPromise* promise = [RXPromise new];
    if (queue == NULL) {
        queue = dispatch_get_global_queue(0, 0);
    }
    work_for(promise, duration, queue, ^{
        [promise fulfillWithValue:result];
    });
    return promise;
}


RXPromise* async_fail(double duration, id reason = @"Failure", dispatch_queue_t queue = NULL)
{
    RXPromise* promise = [RXPromise new];
    if (queue == NULL) {
        queue = dispatch_get_global_queue(0, 0);
    }
    work_for(promise, duration, queue, ^{
        [promise rejectWithReason:reason];
    });
    return promise;
}

// use a bound promise
static RXPromise* async_bind(double duration, id result = @"OK", dispatch_queue_t queue = NULL) {
    RXPromise* promise = [RXPromise new];
    double delayInSeconds = 0.01;
    dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayInSeconds * NSEC_PER_SEC));
    dispatch_after(popTime, dispatch_get_global_queue(0, 0), ^(void){
        [promise bind:async(duration, result, queue)];
    });
    return promise;
}

// use a bound promise
RXPromise* async_bind_fail(double duration, id reason = @"Failure", dispatch_queue_t queue = NULL)
{
    RXPromise* promise = [RXPromise new];
    double delayInSeconds = 0.01;
    dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayInSeconds * NSEC_PER_SEC));
    dispatch_after(popTime, dispatch_get_global_queue(0, 0), ^(void){
        [promise bind:async_fail(duration, reason, queue)];
    });
    return promise;
}





#pragma mark -



@implementation RXPromise_Test

- (void)setUp
{
    [super setUp];
}

- (void)tearDown
{
    // Tear-down code here.
    
    [super tearDown];
}

-(void) testPromiseAPI {
    
    RXPromise* promise = [[RXPromise alloc] init];
    
    STAssertTrue( [promise respondsToSelector:@selector(then)], @"A promise must have a property 'then'" );
    STAssertTrue( [[promise then] isKindOfClass:NSClassFromString(@"NSBlock")], @"property 'then' must return a block");    
}


-(void)testStatePending
{
    RXPromise* promise = [[RXPromise alloc] init];
    STAssertTrue(promise.isPending == YES, @"promise.isPending == YES");
    STAssertTrue(promise.isCancelled == NO, @"promise.isCancelled == NO");
    STAssertTrue(promise.isFulfilled == NO, @"promise.isFulfilled == NO");
    STAssertTrue(promise.isRejected == NO, @"promise.isRejected == NO");
}

-(void) testStateFulfilled
{
    RXPromise* promise = [[RXPromise alloc] init];
    
    [promise fulfillWithValue:@"OK"];
    
    STAssertTrue(promise.isPending == NO, @"promise.isPending == NO");
    STAssertTrue(promise.isCancelled == NO, @"promise.isCancelled == NO");
    STAssertTrue(promise.isFulfilled == YES, @"promise.isFulfilled == YES");
    STAssertTrue(promise.isRejected == NO, @"promise.isRejected == NO");
    STAssertTrue( [promise.get isKindOfClass:[NSString class]], @"[promise.get isKindOfClass:[NSString class]]");
    STAssertTrue( [promise.get isEqualToString:@"OK"], [promise.get description]);
    
    [promise fulfillWithValue:@"NO"];
    STAssertTrue(promise.isPending == NO, @"");
    STAssertTrue(promise.isCancelled == NO, @"");
    STAssertTrue(promise.isFulfilled == YES, @"");
    STAssertTrue(promise.isRejected == NO, @"");
    STAssertTrue( [promise.get isKindOfClass:[NSString class]], @"");
    STAssertTrue( [promise.get isEqualToString:@"OK"], [promise.get description]);
    
    [promise rejectWithReason:@"Fail!"];
    STAssertTrue(promise.isPending == NO, @"");
    STAssertTrue(promise.isCancelled == NO, @"");
    STAssertTrue(promise.isFulfilled == YES, @"");
    STAssertTrue(promise.isRejected == NO, @"");
    STAssertTrue( [promise.get isKindOfClass:[NSString class]], @"" );
    STAssertTrue( [promise.get isEqualToString:@"OK"], [promise.get description] );
    
    [promise cancelWithReason:@"Cancelled"];
    STAssertTrue(promise.isPending == NO, @"");
    STAssertTrue(promise.isCancelled == NO, @"");
    STAssertTrue(promise.isFulfilled == YES, @"");
    STAssertTrue(promise.isRejected == NO, @"");
    STAssertTrue( [promise.get isKindOfClass:[NSString class]], @"" );
    STAssertTrue( [promise.get isEqualToString:@"OK"], [promise get] );
}

-(void)testStateRejected
{
    RXPromise* promise = [[RXPromise alloc] init];
    
    [promise rejectWithReason:@"Fail"];
    
    STAssertTrue(promise.isPending == NO, @"");
    STAssertTrue(promise.isCancelled == NO, @"");
    STAssertTrue(promise.isFulfilled == NO, @"");
    STAssertTrue(promise.isRejected == YES, @"");
    STAssertTrue( [promise.get isKindOfClass:[NSError class]], @"" );
    STAssertTrue([[promise.get userInfo][@"reason"] isKindOfClass:[NSString class]], @"");
    STAssertTrue([[promise.get userInfo][@"reason"] isEqualToString:@"Fail"], @"");
    
    [promise fulfillWithValue:@"NO"];
    STAssertTrue(promise.isPending == NO, @"");
    STAssertTrue(promise.isCancelled == NO, @"");
    STAssertTrue(promise.isFulfilled == NO, @"");
    STAssertTrue(promise.isRejected == YES, @"");
    STAssertTrue( [promise.get isKindOfClass:[NSError class]], @"" );
    STAssertTrue([[promise.get userInfo][@"reason"] isKindOfClass:[NSString class]], @"");
    STAssertTrue([[promise.get userInfo][@"reason"] isEqualToString:@"Fail"], @"");
    
    [promise rejectWithReason:@"Fail!"];
    STAssertTrue(promise.isPending == NO, @"");
    STAssertTrue(promise.isCancelled == NO, @"");
    STAssertTrue(promise.isFulfilled == NO, @"");
    STAssertTrue(promise.isRejected == YES, @"");
    STAssertTrue( [promise.get isKindOfClass:[NSError class]], @"" );
    STAssertTrue([[promise.get userInfo][@"reason"] isKindOfClass:[NSString class]], @"");
    STAssertTrue([[promise.get userInfo][@"reason"] isEqualToString:@"Fail"], @"");
    
    [promise cancelWithReason:@"Cancelled"];
    STAssertTrue(promise.isPending == NO, @"");
    STAssertTrue(promise.isCancelled == NO, @"");
    STAssertTrue(promise.isFulfilled == NO, @"");
    STAssertTrue(promise.isRejected == YES, @"");
    STAssertTrue( [promise.get isKindOfClass:[NSError class]], @"");
    STAssertTrue([[promise.get userInfo][@"reason"] isKindOfClass:[NSString class]], @"");
    STAssertTrue([[promise.get userInfo][@"reason"] isEqualToString:@"Fail"], @"");
}

-(void)testStateCancelled
{
    RXPromise* promise = [[RXPromise alloc] init];
    
    [promise cancelWithReason:@"Cancelled"];
    
    STAssertTrue(promise.isPending == NO, @"");
    STAssertTrue(promise.isCancelled == YES, @"");
    STAssertTrue(promise.isFulfilled == NO, @"");
    STAssertTrue(promise.isRejected == YES, @"");
    STAssertTrue( [promise.get isKindOfClass:[NSError class]], @"" );
    STAssertTrue([[promise.get userInfo][@"reason"] isKindOfClass:[NSString class]], @"");
    STAssertTrue([promise.get code] == -1, @"");
    STAssertTrue([[promise.get userInfo][@"reason"] isEqualToString:@"Cancelled"], @"");
    
    [promise fulfillWithValue:@"NO"];
    STAssertTrue(promise.isPending == NO, @"");
    STAssertTrue(promise.isCancelled == YES, @"");
    STAssertTrue(promise.isFulfilled == NO, @"");
    STAssertTrue(promise.isRejected == YES, @"");
    STAssertTrue( [promise.get isKindOfClass:[NSError class]], @"" );
    STAssertTrue([[promise.get userInfo][@"reason"] isKindOfClass:[NSString class]], @"");
    STAssertTrue([promise.get code] == -1, @"");
    STAssertTrue([[promise.get userInfo][@"reason"] isEqualToString:@"Cancelled"], @"");
    
    [promise rejectWithReason:@"Fail!"];
    STAssertTrue(promise.isPending == NO, @"");
    STAssertTrue(promise.isCancelled == YES, @"");
    STAssertTrue(promise.isFulfilled == NO, @"");
    STAssertTrue(promise.isRejected == YES, @"");
    STAssertTrue( [promise.get isKindOfClass:[NSError class]], @"" );
    STAssertTrue([[promise.get userInfo][@"reason"] isKindOfClass:[NSString class]], @"");
    STAssertTrue([promise.get code] == -1, @"");
    STAssertTrue([[promise.get userInfo][@"reason"] isEqualToString:@"Cancelled"], @"");
    
    [promise cancelWithReason:@"Cancelled"];
    STAssertTrue(promise.isPending == NO, @"");
    STAssertTrue(promise.isCancelled == YES, @"");
    STAssertTrue(promise.isFulfilled == NO, @"");
    STAssertTrue(promise.isRejected == YES, @"");
    STAssertTrue( [promise.get isKindOfClass:[NSError class]], @"" );
    STAssertTrue([[promise.get userInfo][@"reason"] isKindOfClass:[NSString class]], @"");
    STAssertTrue([promise.get code] == -1, @"");
    STAssertTrue([[promise.get userInfo][@"reason"] isEqualToString:@"Cancelled"], @"");
}

-(void) testBasicSuccess
{
    // Check whether a promise fires its handlers in due time:
    
    @autoreleasepool {
        
        dispatch_semaphore_t finished_sem = dispatch_semaphore_create(0);
        
        asyncOp(@"A", 1, nil, 0.01).then(^id(id){ dispatch_semaphore_signal(finished_sem); return nil; }, nil);
        
        // The operation is finished after about 0.01 s. Thus, the handler should
        // start to execute after about 0.01 seconds. Given a reasonable delay:
        STAssertTrue(dispatch_semaphore_wait(finished_sem, dispatch_time(DISPATCH_TIME_NOW, 1*NSEC_PER_SEC)) == 0,
        @"success callback not called after 1 second");
    }
}

-(void) testBasicChaining
{
    RXPromise* p = async(0.01, @"A")
    .then(^(id){return async(0.01, @"B");}, nil)
    .then(^(id){return async(0.01, @"C");}, nil)
    .then(^(id){return async(0.01, @"D");}, nil);
    
    // Promise `p` shall have the state of the last async function, unless an error occurred:    
    id result = p.get;
    STAssertTrue( [result isEqualToString:@"D"],  @"result shall have the result of the last async function - which is @\"D\"" );
    STAssertTrue( p.isFulfilled, @"");
    STAssertFalse( p.isCancelled, @"");
    STAssertFalse( p.isRejected, @"");
}

-(void) testBasicChainingWithBoundPromise
{
    // A bound promise shall effectively be transparent to the user.
    RXPromise* p = async_bind(0.01, @"A")
    .then(^(id){return async_bind(0.01, @"B");}, nil)
    .then(^(id){return async_bind(0.01, @"C");}, nil)
    .then(^(id){return async_bind(0.01, @"D");}, nil);
    
    // Promise `p` shall have the state of the last async function, unless an error occurred:
    id result = p.get;
    STAssertTrue( [result isEqualToString:@"D"],  @"result shall have the result of the last async function - which is @\"D\"" );
    STAssertTrue( p.isFulfilled, @"");
    STAssertFalse( p.isCancelled, @"");
    STAssertFalse( p.isRejected, @"");
}



-(void) testBasicChainingWithImmediateNilResult
{
    RXPromise* p = async(0.01, @"A")
    .then(^(id){return async(0.01, @"B");}, nil)
    .then(^(id){return async(0.01, @"C");}, nil)
    .then(^id(id){return nil;}, nil);
    
    // Promise `p` shall have the state of the last async function, unless an error occurred:
    id result = p.get;
    STAssertTrue( result == nil, @"result shall have the result of the last async function - which is nil" );
    STAssertTrue( p.isFulfilled, @"");
    STAssertFalse( p.isCancelled, @"");
    STAssertFalse( p.isRejected, @"");
}


-(void) testBasicChainingWithImmediateNilResultBoundPromise
{
    // A bound promise shall be transparent to the user.
    RXPromise* p = async_bind(0.01, @"A")
    .then(^(id){return async_bind(0.01, @"B");}, nil)
    .then(^(id){return async_bind(0.01, @"C");}, nil)
    .then(^id(id){return nil;}, nil);
    
    // Promise `p` shall have the state of the last async function, unless an error occurred:
    id result = p.get;
    STAssertTrue( result == nil, @"result shall have the result of the last async function - which is nil" );
    STAssertTrue( p.isFulfilled, @"");
    STAssertFalse( p.isCancelled, @"");
    STAssertFalse( p.isRejected, @"");
}


-(void) testBasicChainingWithImmediateResult
{
    RXPromise* p = async(0.01, @"A")
    .then(^(id){return async(0.01, @"B");}, nil)
    .then(^(id){return async(0.01, @"C");}, nil)
    .then(^id(id){return @"OK";}, nil);
    
    // Promise `p` shall have the state of the last async function, unless an error occurred:
    id result = p.get;
    STAssertTrue( [result isEqualToString:@"OK"], @"result shall have the result of the last async function - which is @\"OK\"" );
    STAssertTrue( p.isFulfilled, @"");
    STAssertFalse( p.isCancelled, @"");
    STAssertFalse( p.isRejected, @"");
}

-(void) testBasicChainingWithImmediateResultWithBoundPromise
{
    // A bound promise shall be transparent to the user.
    RXPromise* p = async_bind(0.01, @"A")
    .then(^(id){return async_bind(0.01, @"B");}, nil)
    .then(^(id){return async_bind(0.01, @"C");}, nil)
    .then(^id(id){return @"OK";}, nil);
    
    // Promise `p` shall have the state of the last async function, unless an error occurred:
    id result = p.get;
    STAssertTrue( [result isEqualToString:@"OK"], @"result shall have the result of the last async function - which is @\"OK\"" );
    STAssertTrue( p.isFulfilled, @"");
    STAssertFalse( p.isCancelled, @"");
    STAssertFalse( p.isRejected, @"");
}



-(void) testBasicChainingWithFailure
{
    RXPromise* p = async(0.01, @"A")
    .then(^(id){return async(0.01, @"B");}, nil)
    .then(^(id){return async_fail(0.01, @"C:Failure");}, nil)
    .then(^(id){return async(0.01, @"D");}, nil);
    
    id result = p.get;
    STAssertTrue( [result isKindOfClass:[NSError class]], @"");
    STAssertTrue( [[result userInfo][@"reason"] isEqualToString:@"C:Failure"], @"" );
    STAssertFalse( p.isFulfilled, @"");
    STAssertFalse( p.isCancelled, @"");
    STAssertTrue( p.isRejected, @"");
}

-(void) testBasicChainingWithFailureWithBoundPromise
{
    // A bound promise shall be transparent to the user.
    RXPromise* p = async_bind(0.01, @"A")
    .then(^(id){return async_bind(0.01, @"B");}, nil)
    .then(^(id){return async_bind_fail(0.01, @"C:Failure");}, nil)
    .then(^(id){return async_bind(0.01, @"D");}, nil);
    
    id result = p.get;
    STAssertTrue( [result isKindOfClass:[NSError class]], @"");
    STAssertTrue( [[result userInfo][@"reason"] isEqualToString:@"C:Failure"], @"" );
    STAssertFalse( p.isFulfilled, @"");
    STAssertFalse( p.isCancelled, @"");
    STAssertTrue( p.isRejected, @"");
}



-(void) testBasicChainingWithImmediateError
{
    RXPromise* p = async(0.01, @"A")
    .then(^(id){return async(0.01, @"B");}, nil)
    .then(^(id){return async(0.01, @"C");}, nil)
    .then(^(id){return [NSError errorWithDomain:@"Test" code:10 userInfo:nil];}, nil);
    
    id result = p.get;
    STAssertTrue( [result isKindOfClass:[NSError class]], @"" );
    STAssertEquals(10, (int)[result code], @"");
    STAssertFalse( p.isFulfilled, @"");
    STAssertFalse( p.isCancelled, @"");
    STAssertTrue( p.isRejected, @"");
}

-(void) testBasicChainingWithImmediateErrorWithBoundPromise
{
    RXPromise* p = async_bind(0.01, @"A")
    .then(^(id){return async_bind(0.01, @"B");}, nil)
    .then(^(id){return async_bind(0.01, @"C");}, nil)
    .then(^(id){return [NSError errorWithDomain:@"Test" code:10 userInfo:nil];}, nil);
    
    id result = p.get;
    STAssertTrue( [result isKindOfClass:[NSError class]], @"" );
    STAssertEquals(10, (int)[result code], @"");
    STAssertFalse( p.isFulfilled, @"");
    STAssertFalse( p.isCancelled, @"");
    STAssertTrue( p.isRejected, @"");
}



//    TEST_F(RXPromiseTest, Test2)
//    {
//        RXPromise* p = async(1, @"A")
//        .then(^(id){
//                return async(1, @"B");
//        }, nil)
//        .then(^(id){
//                return async(1, @"C");
//        }, nil)
//        .then(^(id){
//            return async(1, @"D");
//        }, nil);
//
//        id result = p.get;
//        STAssertTrue( [result isKindOfClass:[NSString class]] );
//        STAssertTrue( [p.get isEqualToString:@"A"] );
//    }



- (void) testChainingTestForwardResult
{
    // As an exercise we only keep a reference to the root promise. The root
    // promise will be fulfilled when the first async task finishes. That is,
    // it can't be used to tell us when all tasks have been completed.
    
    // Test whether the result will be forwarded and the handlers exexcute in
    // order.
    
    dispatch_semaphore_t finished_sem = dispatch_semaphore_create(0);
    NSMutableString* s = [[NSMutableString alloc] init];
    RXPromise* p = async(0.01, @"A");
    p.then(^(id result){ [s appendString:result]; return async(0.01, @"B");},nil)
    .then(^(id result){ [s appendString:result]; return async(0.01, @"C");},nil)
    .then(^(id result){ [s appendString:result]; return async(0.01, @"D");},nil)
    .then(^id(id result){
        [s appendString:result];
        dispatch_semaphore_signal(finished_sem);
        return nil;
    },nil);
    
    dispatch_semaphore_wait(finished_sem, DISPATCH_TIME_FOREVER);
    STAssertTrue( [s isEqualToString:@"ABCD"], @"" );
    STAssertFalse(p.isPending, @"");
    STAssertTrue(p.isFulfilled, @"");
    STAssertFalse(p.isCancelled, @"");
    STAssertFalse(p.isRejected, @"");
    STAssertTrue( [p.get isEqualToString:@"A"], @"" );
    dispatch_release(finished_sem);
}

- (void) testChainingTestForwardResultWithBoundPromise
{
    // As an exercise we only keep a reference to the root promise. The root
    // promise will be fulfilled when the first async task finishes. That is,
    // it can't be used to tell us when all tasks have been completed.
    
    // Test whether the result will be forwarded and the handlers exexcute in
    // order.
    
    dispatch_semaphore_t finished_sem = dispatch_semaphore_create(0);
    NSMutableString* s = [[NSMutableString alloc] init];
    RXPromise* p = async_bind(0.01, @"A");
    p.then(^(id result){ [s appendString:result]; return async_bind(0.01, @"B");},nil)
    .then(^(id result){ [s appendString:result]; return async_bind(0.01, @"C");},nil)
    .then(^(id result){ [s appendString:result]; return async_bind(0.01, @"D");},nil)
    .then(^id(id result){
        [s appendString:result];
        dispatch_semaphore_signal(finished_sem);
        return nil;
    },nil);
    
    dispatch_semaphore_wait(finished_sem, DISPATCH_TIME_FOREVER);
    STAssertTrue( [s isEqualToString:@"ABCD"], @"" );
    STAssertFalse(p.isPending, @"");
    STAssertTrue(p.isFulfilled, @"");
    STAssertFalse(p.isCancelled, @"");
    STAssertFalse(p.isRejected, @"");
    STAssertTrue( [p.get isEqualToString:@"A"], @"" );
    dispatch_release(finished_sem);
}


-(void) testChainingStates {
    
    // Keep all references to the promises.
    // Test if promises do have the correct state when they
    // enter the handler.
    
    RXPromise* p0, *p1, *p2, *p3, *p4;
    p0 = async(0.1);
    
    NSMutableString* s = [[NSMutableString alloc] init];
    
    p1 = p0.then(^(id){
        // Note: accessing p1 in this handler is not safe!
        STAssertFalse(p0.isPending, @"");
        STAssertTrue(p0.isFulfilled, @"");
        STAssertFalse(p0.isCancelled, @"");
        STAssertFalse(p0.isRejected, @"");
        [s appendString:@"A"];
        return async(0.01);
    },^id(NSError* error){
        STFail(@"p1 error handler called");
        return error;
    });
    p2 = p1.then(^(id){
        STAssertFalse(p1.isPending, @"");
        STAssertTrue(p1.isFulfilled, @"");
        STAssertFalse(p1.isCancelled, @"");
        STAssertFalse(p1.isRejected, @"");
        [s appendString:@"B"];
        return async(0.01);
    },^id(NSError* error){
        STFail(@"p2 error handler called");
        return error;
    });
    p3 = p2.then(^(id){
        STAssertFalse(p2.isPending, @"");
        STAssertTrue(p2.isFulfilled, @"");
        STAssertFalse(p2.isCancelled, @"");
        STAssertFalse(p2.isRejected, @"");
        [s appendString:@"C"];
        return async(0.01);
    },^id(NSError* error){
        STFail(@"p3 error handler called");
        return error;
    });
    p4 = p3.then(^(id){
        STAssertFalse(p3.isPending, @"");
        STAssertTrue(p3.isFulfilled, @"");
        STAssertFalse(p3.isCancelled, @"");
        STAssertFalse(p3.isRejected, @"");
        [s appendString:@"D"];
        return async(0.01);
    },^id(NSError* error){
        STFail(@"p4 error handler called");
        return error;
    });
    
    // p0 will resolve after 0.1 seconds, so hurry to check all promises:
    STAssertTrue(p0.isPending, @"");
    STAssertTrue(p1.isPending, @"");
    STAssertTrue(p2.isPending, @"");
    STAssertTrue(p3.isPending, @"");
    STAssertTrue(p4.isPending, @"");
    
    // wait until p4 has been resolved:
    id result = p4.get;
    STAssertTrue([result isEqualToString:@"OK"], @"");  // note: @"OK" is the default value for success.
    STAssertFalse(p4.isPending, @"");
    STAssertTrue(p4.isFulfilled, @"");
    STAssertFalse(p4.isCancelled, @"");
    STAssertFalse(p4.isRejected, @"");
    STAssertTrue([s isEqualToString:@"ABCD"], @"");
}



-(void) testBasicFailureWithoutErrorHandler
{
    // Check whether a promise fires its handlers in due time:
    
    @autoreleasepool {
        
        semaphore finished_sem;
        semaphore& semRef = finished_sem;
        
        RXPromise* promise0 = async_fail(0.01, @"Failure");
        RXPromise* promise1 = promise0.then(^id(id){
            semRef.signal();
            return nil;
        }, nil);
        
        // The operation is finished with a failure after about 0.01 s. Thus, the
        // success handler should not be called, and the semaphore must timeout:
        STAssertFalse(finished_sem.wait(0.10), @"success callback called after 0.10 second");
        STAssertFalse(promise0.isPending, @"");
        STAssertFalse(promise0.isFulfilled, @"");
        STAssertFalse(promise0.isCancelled, @"");
        STAssertTrue(promise0.isRejected, @"");
        id result0 = promise0.get;
        STAssertTrue([result0 isKindOfClass:[NSError class]], [result0 description]);
        
        STAssertFalse(promise1.isPending, @"");
        STAssertFalse(promise1.isFulfilled, @"");
        STAssertFalse(promise1.isCancelled, @"");
        STAssertTrue(promise1.isRejected, @"");
        id result1 = promise1.get;
        STAssertTrue([result1 isKindOfClass:[NSError class]], result1);
        
    }
}



-(void) testChainingStatesWithP0Fails {
    
    // Test if promises do have the correct state when they enter the handler,
    // if this is the expected handler and if they forward the error correctly:
    
    // Keep all references to the promises.
    NSMutableString* e = [[NSMutableString alloc] init];
    RXPromise* p0, *p1, *p2, *p3, *p4;
    p0 = async_fail(0.2, @"A:ERROR");
    
    p1 = p0.then(^id(id){
        STFail(@"p1 success handler called");
        return async(0.01);
    },^id(NSError* error){
        // Note: accessing p1 in this handler is not correct, since the
        // handler will determince how the returned promise will be resolved!
        STAssertTrue([error isKindOfClass:[NSError class]], @"");
        STAssertTrue([error.userInfo[@"reason"] isEqualToString:@"A:ERROR"], @"");
        STAssertFalse(p0.isPending, @"");
        STAssertFalse(p0.isFulfilled, @"");
        STAssertFalse(p0.isCancelled, @"");
        STAssertTrue(p0.isRejected, @"");
        [e appendString:@"a"];
        return error;
    });
    p2 = p1.then(^id(id){
        STFail(@"p1 success handler called");
        return async(0.01);
    },^id(NSError* error){
        STAssertTrue([error isKindOfClass:[NSError class]], @"");
        STAssertTrue([error.userInfo[@"reason"] isEqualToString:@"A:ERROR"], @"");
        STAssertFalse(p1.isPending, @"");
        STAssertFalse(p1.isFulfilled, @"");
        STAssertFalse(p1.isCancelled, @"");
        STAssertTrue(p1.isRejected, @"");
        
        STAssertFalse(p0.isPending, @"");
        STAssertFalse(p0.isFulfilled, @"");
        STAssertFalse(p0.isCancelled, @"");
        STAssertTrue(p0.isRejected, @"");
        [e appendString:@"b"];
        return error;
    });
    p3 = p2.then(^id(id){
        STFail(@"p1 success handler called");
        return async(0.01);
    },^id(NSError* error){
        STAssertTrue([error isKindOfClass:[NSError class]], @"");
        STAssertTrue([error.userInfo[@"reason"] isEqualToString:@"A:ERROR"], @"");
        STAssertFalse(p2.isPending, @"");
        STAssertFalse(p2.isFulfilled, @"");
        STAssertFalse(p2.isCancelled, @"");
        STAssertTrue(p2.isRejected, @"");
        STAssertFalse(p1.isPending, @"");
        STAssertFalse(p1.isFulfilled, @"");
        STAssertFalse(p1.isCancelled, @"");
        STAssertTrue(p1.isRejected, @"");
        STAssertFalse(p0.isPending, @"");
        STAssertFalse(p0.isFulfilled, @"");
        STAssertFalse(p0.isCancelled, @"");
        STAssertTrue(p0.isRejected, @"");
        [e appendString:@"c"];
        return error;
    });
    p4 = p3.then(^id(id){
        STFail(@"p1 success handler called");
        return async(0.01);
    },^id(NSError* error){
        STAssertTrue([error isKindOfClass:[NSError class]], @"");
        STAssertTrue([error.userInfo[@"reason"] isEqualToString:@"A:ERROR"], @"");
        STAssertFalse(p3.isPending, @"");
        STAssertFalse(p3.isFulfilled, @"");
        STAssertFalse(p3.isCancelled, @"");
        STAssertTrue(p3.isRejected, @"");
        STAssertFalse(p2.isPending, @"");
        STAssertFalse(p2.isFulfilled, @"");
        STAssertFalse(p2.isCancelled, @"");
        STAssertTrue(p2.isRejected, @"");
        STAssertFalse(p1.isPending, @"");
        STAssertFalse(p1.isFulfilled, @"");
        STAssertFalse(p1.isCancelled, @"");
        STAssertTrue(p1.isRejected, @"");
        STAssertFalse(p0.isPending, @"");
        STAssertFalse(p0.isFulfilled, @"");
        STAssertFalse(p0.isCancelled, @"");
        STAssertTrue(p0.isRejected, @"");
        [e appendString:@"d"];
        return error;
    });
    
    // p0 will resolve after 0.2 seconds, so hurry to check all promises:
    STAssertTrue(p0.isPending, @"");
    STAssertTrue(p1.isPending, @"");
    STAssertTrue(p2.isPending, @"");
    STAssertTrue(p3.isPending, @"");
    STAssertTrue(p4.isPending, @"");
    
    // p4 will be resolved shortly after, as the error gets forwarded quickly:
    id result = p4.get;
    STAssertTrue([result isKindOfClass:[NSError class]], @"");
    STAssertTrue([[result userInfo][@"reason"] isEqualToString:@"A:ERROR"], @"");
    STAssertFalse(p4.isPending, @"");
    STAssertFalse(p4.isFulfilled, @"");
    STAssertFalse(p4.isCancelled, @"");
    STAssertTrue(p4.isRejected, @"");
    STAssertTrue([e isEqualToString:@"abcd"], @"");
}



-(void) testChainingStatesWithP1Fails {
    
    // Test if promises do have the correct state when they enter the handler,
    // if this is the expected handler and if they forward the error correctly:
    
    // Keep all references to the promises.
    
    NSMutableString* s = [[NSMutableString alloc] init];
    NSMutableString* e = [[NSMutableString alloc] init];
    
    
    RXPromise* p0, *p1, *p2, *p3, *p4;
    p0 = async(0.1);
    
    p1 = p0.then(^id(id){
        STAssertFalse(p0.isPending, @"");
        STAssertTrue(p0.isFulfilled, @"");
        STAssertFalse(p0.isCancelled, @"");
        STAssertFalse(p0.isRejected, @"");
        [s appendString:@"A"];
        return async_fail(0.01, @"B:ERROR");;
        
    },^id(NSError* error){
        STFail(@"p1 success handler called");
        return error;
    });
    p2 = p1.then(^id(id){
        STFail(@"p1 success handler called");
        return async(0.01);
    },^id(NSError* error){
        STAssertTrue([error isKindOfClass:[NSError class]], @"");
        STAssertTrue([error.userInfo[@"reason"] isEqualToString:@"B:ERROR"], @"");
        STAssertFalse(p1.isPending, @"");
        STAssertFalse(p1.isFulfilled, @"");
        STAssertFalse(p1.isCancelled, @"");
        STAssertTrue(p1.isRejected, @"");
        
        STAssertFalse(p0.isPending, @"");
        STAssertTrue(p0.isFulfilled, @"");
        STAssertFalse(p0.isCancelled, @"");
        STAssertFalse(p0.isRejected, @"");
        [e appendString:@"b"];
        return error;
    });
    p3 = p2.then(^id(id){
        STFail(@"p1 success handler called");
        return async(0.01);
    },^id(NSError* error){
        STAssertTrue([error isKindOfClass:[NSError class]], @"");
        STAssertTrue([error.userInfo[@"reason"] isEqualToString:@"B:ERROR"], @"");
        STAssertFalse(p2.isPending, @"");
        STAssertFalse(p2.isFulfilled, @"");
        STAssertFalse(p2.isCancelled, @"");
        STAssertTrue(p2.isRejected, @"");
        STAssertFalse(p1.isPending, @"");
        STAssertFalse(p1.isFulfilled, @"");
        STAssertFalse(p1.isCancelled, @"");
        STAssertTrue(p1.isRejected, @"");
        STAssertFalse(p0.isPending, @"");
        STAssertTrue(p0.isFulfilled, @"");
        STAssertFalse(p0.isCancelled, @"");
        STAssertFalse(p0.isRejected, @"");
        [e appendString:@"c"];
        return error;
    });
    p4 = p3.then(^id(id){
        STFail(@"p1 success handler called");
        return async(0.01);
    },^id(NSError* error){
        STAssertTrue([error isKindOfClass:[NSError class]], @"");
        STAssertTrue([error.userInfo[@"reason"] isEqualToString:@"B:ERROR"], @"");
        STAssertFalse(p3.isPending, @"");
        STAssertFalse(p3.isFulfilled, @"");
        STAssertFalse(p3.isCancelled, @"");
        STAssertTrue(p3.isRejected, @"");
        STAssertFalse(p2.isPending, @"");
        STAssertFalse(p2.isFulfilled, @"");
        STAssertFalse(p2.isCancelled, @"");
        STAssertTrue(p2.isRejected, @"");
        STAssertFalse(p1.isPending, @"");
        STAssertFalse(p1.isFulfilled, @"");
        STAssertFalse(p1.isCancelled, @"");
        STAssertTrue(p1.isRejected, @"");
        STAssertFalse(p0.isPending, @"");
        STAssertTrue(p0.isFulfilled, @"");
        STAssertFalse(p0.isCancelled, @"");
        STAssertFalse(p0.isRejected, @"");
        [e appendString:@"d"];
        return error;
    });
    
    // p0 will resolve after 0.2 seconds, so hurry to check all promises:
    STAssertTrue(p0.isPending, @"");
    STAssertTrue(p1.isPending, @"");
    STAssertTrue(p2.isPending, @"");
    STAssertTrue(p3.isPending, @"");
    STAssertTrue(p4.isPending, @"");
    
    // p4 will be resolved shortly after, as the error gets forwarded quickly:
    id result = p4.get;
    STAssertTrue([result isKindOfClass:[NSError class]], @"");
    STAssertTrue([[result userInfo][@"reason"] isEqualToString:@"B:ERROR"], @"");
    STAssertFalse(p4.isPending, @"");
    STAssertFalse(p4.isFulfilled, @"");
    STAssertFalse(p4.isCancelled, @"");
    STAssertTrue(p4.isRejected, @"");
    STAssertTrue([s isEqualToString:@"A"], @"");
    STAssertTrue([e isEqualToString:@"bcd"], @"");
}


-(void) testThenMustReturnBeforeHandlersWillBeCalled {
    
    // Actually, this is tricky to test and verify correctly due to
    // avoiding race conditions. The code below seems correct, though.
    // A possible improvement would be to run it in a loop in
    // order to provoke a possibly race.
    
    dispatch_queue_t serial_queue = dispatch_queue_create("serial_queue", 0);
    
    for (int i = 0; i < 100; ++i) {
        semaphore finished;
        semaphore& finishedRef = finished;
        
        RXPromise* promise1 = [[RXPromise alloc] init];
        __block RXPromise* promise2;
        
        bool returnedFromThen = false;
        bool& returnedFromThenRef = returnedFromThen;
        dispatch_async(serial_queue, ^{
            [promise1 fulfillWithValue:@"Finished"];
        });
        dispatch_async(serial_queue, ^{
            promise2 = promise1.then(^(id value){
                dispatch_sync(serial_queue, ^{
                    STAssertTrue(returnedFromThenRef, @"");
                });
                STAssertTrue([value isEqualToString:@"Finished"], @"");
                finishedRef.signal();
                return @"OK";
            }, nil);
            returnedFromThenRef = true;
        });
        
        STAssertTrue(finishedRef.wait(1), @"");
        STAssertTrue(promise2 != nil, @"");
        STAssertTrue([promise2.get isEqualToString:@"OK"],[promise2.get description]);
    }
    
    dispatch_release(serial_queue);
}



-(void) testParallelOPsMustExecuteSerially
{
    // The handlers must be executed serially in the same order as they
    // have been scheduled.
    
    semaphore finished_sem;
    semaphore& semRef = finished_sem;
    
    NSMutableString* s = [[NSMutableString alloc] init];
    
    RXPromise* p0; //, *p00, *p01, *p02, *p04;
    
    
    p0 = async(0.01, @"A:success");
    p0.then(^id(id result){
        STAssertTrue([result isEqualToString:@"A:success"], @"");
        STAssertFalse(p0.isPending, @"");
        STAssertTrue(p0.isFulfilled, @"");
        STAssertFalse(p0.isCancelled, @"");
        STAssertFalse(p0.isRejected, @"");
        STAssertTrue( [s isEqualToString:@""], @"");
        [s appendString:@"A"];
        return nil;
    }, nil);
    p0.then(^id(id result){
        STAssertTrue([result isEqualToString:@"A:success"], @"");
        STAssertFalse(p0.isPending, @"");
        STAssertTrue(p0.isFulfilled, @"");
        STAssertFalse(p0.isCancelled, @"");
        STAssertFalse(p0.isRejected, @"");
        STAssertTrue( [s isEqualToString:@"A"], @"" );
        [s appendString:@"B"];
        return nil;
    }, nil);
    p0.then(^id(id result){
        STAssertTrue([result isEqualToString:@"A:success"], @"");
        STAssertFalse(p0.isPending, @"");
        STAssertTrue(p0.isFulfilled, @"");
        STAssertFalse(p0.isCancelled, @"");
        STAssertFalse(p0.isRejected, @"");
        STAssertTrue( [s isEqualToString:@"AB"], @"" );
        [s appendString:@"C"];
        return nil;
    }, nil);
    p0.then(^id(id result){
        STAssertTrue([result isEqualToString:@"A:success"], @"");
        STAssertFalse(p0.isPending, @"");
        STAssertTrue(p0.isFulfilled, @"");
        STAssertFalse(p0.isCancelled, @"");
        STAssertFalse(p0.isRejected, @"");
        STAssertTrue( [s isEqualToString:@"ABC"], @"" );
        [s appendString:@"D"];
        semRef.signal();
        return nil;
    }, ^(NSError* error){
        semRef.signal();
        return error;
    });
    
    STAssertTrue(finished_sem.wait(1), @"success or error callback not called after 1 second");
    STAssertTrue( [s isEqualToString:@"ABCD"], @"" );
}



-(void) testSpawnParallelOPs
{
    // An async operation is started which returns a promise p0.
    // Upon success it spwans 4 parallel operations, which return
    // primise p00, p01, p02 and p03. Each async operation is expected to
    // succeed.
    
    
    NSMutableString* s = [[NSMutableString alloc] init];
    
    RXPromise* p0, *p00, *p01, *p02, *p03;
    
    // RXPromise* pAll = [RXPromise promiseAll: p00, p01, p02, p03];
    
    
    p0 = async(0.01, @"0:success");
    p00 = p0.then(^id(id result){
        STAssertTrue([result isEqualToString:@"0:success"], @"");
        STAssertFalse(p0.isPending, @"");
        STAssertTrue(p0.isFulfilled, @"");
        STAssertFalse(p0.isCancelled, @"");
        STAssertFalse(p0.isRejected, @"");
        STAssertTrue( [s isEqualToString:@""], @"" );
        [s appendString:@"A"];
        return async(0.01, @"00:success");
    }, nil);
    p01 = p0.then(^id(id result){
        STAssertTrue([result isEqualToString:@"0:success"], @"");
        STAssertFalse(p0.isPending, @"");
        STAssertTrue(p0.isFulfilled, @"");
        STAssertFalse(p0.isCancelled, @"");
        STAssertFalse(p0.isRejected, @"");
        STAssertTrue( [s isEqualToString:@"A"], @"" );
        [s appendString:@"B"];
        return async(0.01, @"01:success");
    }, nil);
    p02 = p0.then(^id(id result){
        STAssertTrue([result isEqualToString:@"0:success"], @"");
        STAssertFalse(p0.isPending, @"");
        STAssertTrue(p0.isFulfilled, @"");
        STAssertFalse(p0.isCancelled, @"");
        STAssertFalse(p0.isRejected, @"");
        STAssertTrue( [s isEqualToString:@"AB"], @"" );
        [s appendString:@"C"];
        return async(0.01, @"02:success");
    }, nil);
    p03 = p0.then(^id(id result){
        STAssertTrue([result isEqualToString:@"0:success"], @"");
        STAssertFalse(p0.isPending, @"");
        STAssertTrue(p0.isFulfilled, @"");
        STAssertFalse(p0.isCancelled, @"");
        STAssertFalse(p0.isRejected, @"");
        STAssertTrue( [s isEqualToString:@"ABC"], @"" );
        [s appendString:@"D"];
        return async(0.01, @"03:success");
    }, ^(NSError* error){
        return error;
    });
    
    p00.then(^id(id result){
        STAssertTrue([result isEqualToString:@"00:success"], @"");
        return nil;
    }, ^id(NSError* error){
        STFail(@"p00 error handler called");
        return nil;
    });
    
    p01.then(^id(id result){
        STAssertTrue([result isEqualToString:@"01:success"], @"");
        return nil;
    }, ^id(NSError* error){
        STFail(@"p01 error handler called");
        return nil;
    });
    
    p02.then(^id(id result){
        STAssertTrue([result isEqualToString:@"02:success"], @"");
        return nil;
    }, ^id(NSError* error){
        STFail(@"p02 error handler called");
        return nil;
    });
    
    p03.then(^id(id result){
        STAssertTrue([result isEqualToString:@"03:success"], @"");
        return nil;
    }, ^id(NSError* error){
        STFail(@"p03 error handler called");
        return nil;
    });
    
    [p00 wait], [p01 wait], [p02 wait], [p03 wait];
    
    STAssertFalse(p00.isPending, @"");
    STAssertTrue(p00.isFulfilled, @"");
    STAssertFalse(p00.isCancelled, @"");
    STAssertFalse(p00.isRejected, @"");
    STAssertTrue([p00.get isEqualToString:@"00:success"], @"");
    
    STAssertFalse(p01.isPending, @"");
    STAssertTrue(p01.isFulfilled, @"");
    STAssertFalse(p01.isCancelled, @"");
    STAssertFalse(p01.isRejected, @"");
    STAssertTrue([p01.get isEqualToString:@"01:success"], @"");
    
    STAssertFalse(p02.isPending, @"");
    STAssertTrue(p02.isFulfilled, @"");
    STAssertFalse(p02.isCancelled, @"");
    STAssertFalse(p02.isRejected, @"");
    STAssertTrue([p02.get isEqualToString:@"02:success"], @"");
    
    STAssertFalse(p03.isPending, @"");
    STAssertTrue(p03.isFulfilled, @"");
    STAssertFalse(p03.isCancelled, @"");
    STAssertFalse(p03.isRejected, @"");
    STAssertTrue([p03.get isEqualToString:@"03:success"], @"");
    
    STAssertTrue( [s isEqualToString:@"ABCD"], s);
}


-(void) testChainedOPsWithFailure
{
    // This runs four chained operations A, B, C and D. Operation "C" fails
    // in the middle.
    // As an exercise, we don't keep any promises.
    // We expect that operation A and B succeeded, C failed, and D has not
    // been invoked at all. We check this with examining the effect of the
    // success handlers and rely on the fact that the last success handler
    // must timeout.
    // Actually, we can't test whether operation D has not been invoked - we
    // would need to keep the promises that each operation returns.
    
    @autoreleasepool {
        
        NSOperationQueue* queue = [[NSOperationQueue alloc] init];
        queue.maxConcurrentOperationCount = 4;
        
        semaphore finished_sem;
        semaphore& semRef = finished_sem;
        
        std::string s;
        std::string& sr = s;
        
        asyncOp(@"A", 1, queue, 0.01)
        .then(^id(id){
            STAssertTrue(sr == "", @"");
            sr.append("A");
            return asyncOp(@"B", 1, queue, 0.01);
        }, nil)
        .then(^id(id){
               STAssertTrue(sr == "A", @"");
               sr.append("B");
               return asyncOp(@"C", 3, queue, 0.01, 2, @"Failure at step 2");
           }, nil)
        .then(^id(id){
              STAssertTrue(sr == "AB", @"");
              sr.append("C");
              return asyncOp(@"D", 1, queue, 0.01);
          }, nil)
        .then(^id(id){
             STAssertTrue(sr == "ABC", @"");
             sr.append("D");
             semRef.signal(); return nil;
         }, nil);
        
        // We expect the finished_sem to timeout:
        STAssertFalse(finished_sem.wait(0.5), @"success callback called after 0.5 second");
        STAssertTrue(s == "AB", @"");
        
        // We do not have any promises to check.
    }
}


-(void) testChainedOPsWithFailureWithErrorHandlers
{
    // This runs four chained operations A, B, C and D. Operation "C" fails
    // in the middle.
    // As an exercise, we don't keep any promises.
    // We expect that operation A and B succeeded, C failed, and D has not
    // been invoked at all. We check this with examining the effect of the
    // success handlers and rely on the fact that the last success handler
    // must timeout.
    // Actually, we can't test whether operation D has not been invoked - we
    // would need to keep the promises that each operation returns.
    
    @autoreleasepool {
        
        NSOperationQueue* queue = [[NSOperationQueue alloc] init];
        queue.maxConcurrentOperationCount = 4;
        
        semaphore finished_sem;
        semaphore& semRef = finished_sem;
        
        NSMutableString* s = [[NSMutableString alloc] init];
        NSMutableString* e = [[NSMutableString alloc] init];
        
        asyncOp(@"A", 1, queue, 0.01)
        .then(^id(id){
            STAssertTrue([s isEqualToString:@""], @"");
            [s appendString:@"A"];
            return asyncOp(@"B", 1, queue, 0.01);
        }, ^id(NSError *error) {
            [e appendString:@"a"];
            semRef.signal();
            return error;
        })
        .then(^id(id){
            STAssertTrue([s isEqualToString:@"A"], @"");
            [s appendString:@"B"];
            return asyncOp(@"C", 3, queue, 0.01, 2, @"Failure at step 2");
        },^id(NSError *error) {
            [e appendString:@"b"];
            semRef.signal();
            return error;
        })
        .then(^id(id){
          STAssertTrue([s isEqualToString:@"AB"], @"");
          [s appendString:@"C"];
          return asyncOp(@"D", 1, queue, 0.01);
        }, ^id(NSError *error) {
            [e appendString:@"c"];
            semRef.signal();
            return error;
        })
        .then(^id(id){
            STAssertTrue([s isEqualToString:@"ABC"], @"");
            [s appendString:@"D"];
            semRef.signal(); return nil;
        }, ^id(NSError *error) {
            [e appendString:@"d"];
            semRef.signal();
            return error;
        });
        
        STAssertTrue(finished_sem.wait(0.5), @"any callback not called after 0.5 second");
        usleep(100);
        STAssertTrue([@"AB" isEqualToString:s], @"");
        STAssertTrue([@"cd" isEqualToString:e], @"");
        
        // We do not have any promises to check.
    }
}


-(void) testTree
{
    // This runs a tree of async operations.
    
    @autoreleasepool {
        
        semaphore finished_sem;
        
        std::string s0;
        std::string& sr0 = s0;
        std::string s1;
        std::string& sr1 = s1;
        std::string es;
        std::string& esr = es;
        
        RXPromise* promise0 = async(0.01); // op0
        
        RXPromise* promise00 = promise0.then(^id(id result) {
            sr0.append("S0->"); sr1.append("____");
            return async(0.04); // op00
        }, ^id(NSError *error) {
            esr.append("E0->"); return error;
        });
        RXPromise* promise000 = promise00.then(^id(id result) {
            sr0.append("S00->"); sr1.append("_____");
            return async(0.02); // op000;
        }, ^id(NSError *error) {
            esr.append("E00"); return error;
        });
        promise000.then(^id(id result) {
            sr0.append("S000.");  sr1.append("_____");
            return nil;
        }, ^id(NSError *error) {
            esr.append("E000"); return error;
        });
        
        
        RXPromise* promise01 = promise0.then(^id(id result) {
            sr1.append("S1->"); sr0.append("____");
            return async(0.02); // op01
        }, ^id(NSError *error) {
            esr.append("E1"); return error;
        });
        RXPromise* promise010 = promise01.then(^id(id result) {
            sr1.append("S10->");  sr0.append("_____");
            return async(0.06); // op010;
        }, ^id(NSError *error) {
            esr.append("E10"); return error;
        });
        promise010.then(^id(id result) {
            sr1.append("S100."); sr0.append("_____");
            return nil;
        }, ^id(NSError *error) {
            esr.append("E100"); return error;
        });
        
        STAssertFalse(finished_sem.wait(0.5), @"expected to timeout after 0.5 s");
        STAssertTrue(es == "", @"");
    }
}


-(void)testChainCancel1 {
    
    // Given a chain of four tasks, cancel the root promise when it is still
    // pending.
    // As a result, the pending children promises shall be cancelled with the
    // error returned from the root promise.
    
    // Keep all references to the promises.
    // Test if promises do have the correct state when they
    // enter the handler.
    
    
    RXPromise* p0, *p1, *p2, *p3, *p4;
    
    p0 = async(1000);  // takes a while to finish
    
    NSMutableString* e = [[NSMutableString alloc] init];
    
    p1 = p0.then(^(id){
        STFail(@"p1 success handler called");
        return async(0.01);
    },^id(NSError* error){
        STAssertFalse(p0.isPending, @"");
        STAssertFalse(p0.isFulfilled, @"");
        STAssertTrue(p0.isCancelled, @"");
        STAssertTrue(p0.isRejected, @"");
        [e appendString:@"1"];
        return error;
    });
    p2 = p1.then(^(id){
        STFail(@"p2 success handler called");
        return async(0.01);
    },^id(NSError* error){
        STAssertFalse(p1.isPending, @"");
        STAssertFalse(p1.isFulfilled, @"");
        STAssertTrue(p1.isCancelled, @"");
        STAssertTrue(p1.isRejected, @"");
        [e appendString:@"2"];
        return error;
    });
    p3 = p2.then(^(id){
        STFail(@"p3 success handler called");
        return async(0.01);
    },^id(NSError* error){
        STAssertFalse(p1.isPending, @"");
        STAssertFalse(p1.isFulfilled, @"");
        STAssertTrue(p1.isCancelled, @"");
        STAssertTrue(p1.isRejected, @"");
        [e appendString:@"3"];
        return error;
    });
    p4 = p3.then(^(id){
        STFail(@"p4 success handler called");
        return async(0.01);
    },^id(NSError* error){
        STAssertFalse(p1.isPending, @"");
        STAssertFalse(p1.isFulfilled, @"");
        STAssertTrue(p1.isCancelled, @"");
        STAssertTrue(p1.isRejected, @"");
        [e appendString:@"4"];
        return error;
    });
    
    double delayInSeconds = 0.1;
    dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayInSeconds * NSEC_PER_SEC));
    dispatch_after(popTime, dispatch_get_global_queue(0, 0), ^(void){
        [p0 cancel];
    });
    
    // p0 will resolve with a cancel after 0.2 seconds, so hurry to check all promises:
    STAssertTrue(p0.isPending, @"");
    STAssertTrue(p1.isPending, @"");
    STAssertTrue(p2.isPending, @"");
    STAssertTrue(p3.isPending, @"");
    STAssertTrue(p4.isPending, @"");
    
    // wait until p4 has been resolved:
    id result = p4.get;
    STAssertTrue([e isEqualToString:@"1234"], e);
    
    STAssertTrue([result isKindOfClass:[NSError class]], @"");
    STAssertFalse(p4.isPending, @"");
    STAssertFalse(p4.isFulfilled, @"");
    STAssertTrue(p4.isCancelled, @""); // p4 MUST be "cancelled"
    STAssertTrue(p4.isRejected, @"");
    
    result = p3.get;
    STAssertTrue([result isKindOfClass:[NSError class]], @"");
    STAssertFalse(p3.isPending, @"");
    STAssertFalse(p3.isFulfilled, @"");
    STAssertTrue(p3.isCancelled, @"");  // p3 MUST be "cancelled"
    STAssertTrue(p3.isRejected, @"");
    
    result = p2.get;
    STAssertTrue([result isKindOfClass:[NSError class]], @"");
    STAssertFalse(p2.isPending, @"");
    STAssertFalse(p2.isFulfilled, @"");
    STAssertTrue(p2.isCancelled, @"");  // p2 MUST be "cancelled"
    STAssertTrue(p2.isRejected, @"");
    
    result = p1.get;
    STAssertTrue([result isKindOfClass:[NSError class]], @"");
    STAssertFalse(p1.isPending, @"");
    STAssertFalse(p1.isFulfilled, @"");
    STAssertTrue(p1.isCancelled, @"");  // p1 MUST be "cancelled"
    STAssertTrue(p1.isRejected, @"");
    
    result = p0.get;
    STAssertTrue([result isKindOfClass:[NSError class]], @"");
    STAssertFalse(p0.isPending, @"");
    STAssertFalse(p0.isFulfilled, @"");
    STAssertTrue(p0.isCancelled, @"");  // p0 MUST be cancelled.
    STAssertTrue(p0.isRejected, @"");
}



-(void)testChainCancel1WithBoundPromise {
    
    // Given a chain of four tasks, cancel the root promise when it is still
    // pending.
    // As a result, the pending children promises shall be cancelled with the
    // error returned from the root promise.
    
    // Keep all references to the promises.
    // Test if promises do have the correct state when they
    // enter the handler.
    
    
    RXPromise* p0, *p1, *p2, *p3, *p4;
    
    p0 = async_bind(1000);  // takes a while to finish
    
    NSMutableString* e = [[NSMutableString alloc] init];
    
    p1 = p0.then(^(id){
        STFail(@"p1 success handler called");
        return async_bind(0.01);
    },^id(NSError* error){
        STAssertFalse(p0.isPending, @"");
        STAssertFalse(p0.isFulfilled, @"");
        STAssertTrue(p0.isCancelled, @"");
        STAssertTrue(p0.isRejected, @"");
        [e appendString:@"1"];
        return error;
    });
    p2 = p1.then(^(id){
        STFail(@"p2 success handler called");
        return async_bind(0.01);
    },^id(NSError* error){
        STAssertFalse(p1.isPending, @"");
        STAssertFalse(p1.isFulfilled, @"");
        STAssertTrue(p1.isCancelled, @"");
        STAssertTrue(p1.isRejected, @"");
        [e appendString:@"2"];
        return error;
    });
    p3 = p2.then(^(id){
        STFail(@"p3 success handler called");
        return async_bind(0.01);
    },^id(NSError* error){
        STAssertFalse(p1.isPending, @"");
        STAssertFalse(p1.isFulfilled, @"");
        STAssertTrue(p1.isCancelled, @"");
        STAssertTrue(p1.isRejected, @"");
        [e appendString:@"3"];
        return error;
    });
    p4 = p3.then(^(id){
        STFail(@"p4 success handler called");
        return async_bind(0.01);
    },^id(NSError* error){
        STAssertFalse(p1.isPending, @"");
        STAssertFalse(p1.isFulfilled, @"");
        STAssertTrue(p1.isCancelled, @"");
        STAssertTrue(p1.isRejected, @"");
        [e appendString:@"4"];
        return error;
    });
    
    double delayInSeconds = 0.1;
    dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayInSeconds * NSEC_PER_SEC));
    dispatch_after(popTime, dispatch_get_global_queue(0, 0), ^(void){
        [p0 cancel];
    });
    
    // p0 will resolve with a cancel after 0.2 seconds, so hurry to check all promises:
    STAssertTrue(p0.isPending, @"");
    STAssertTrue(p1.isPending, @"");
    STAssertTrue(p2.isPending, @"");
    STAssertTrue(p3.isPending, @"");
    STAssertTrue(p4.isPending, @"");
    
    // wait until p4 has been resolved:
    id result = p4.get;
    STAssertTrue([e isEqualToString:@"1234"], e);
    
    STAssertTrue([result isKindOfClass:[NSError class]], @"");
    STAssertFalse(p4.isPending, @"");
    STAssertFalse(p4.isFulfilled, @"");
    STAssertTrue(p4.isCancelled, @""); // p4 MUST be "cancelled"
    STAssertTrue(p4.isRejected, @"");
    
    result = p3.get;
    STAssertTrue([result isKindOfClass:[NSError class]], @"");
    STAssertFalse(p3.isPending, @"");
    STAssertFalse(p3.isFulfilled, @"");
    STAssertTrue(p3.isCancelled, @"");  // p3 MUST be "cancelled"
    STAssertTrue(p3.isRejected, @"");
    
    result = p2.get;
    STAssertTrue([result isKindOfClass:[NSError class]], @"");
    STAssertFalse(p2.isPending, @"");
    STAssertFalse(p2.isFulfilled, @"");
    STAssertTrue(p2.isCancelled, @"");  // p2 MUST be "cancelled"
    STAssertTrue(p2.isRejected, @"");
    
    result = p1.get;
    STAssertTrue([result isKindOfClass:[NSError class]], @"");
    STAssertFalse(p1.isPending, @"");
    STAssertFalse(p1.isFulfilled, @"");
    STAssertTrue(p1.isCancelled, @"");  // p1 MUST be "cancelled"
    STAssertTrue(p1.isRejected, @"");
    
    result = p0.get;
    STAssertTrue([result isKindOfClass:[NSError class]], @"");
    STAssertFalse(p0.isPending, @"");
    STAssertFalse(p0.isFulfilled, @"");
    STAssertTrue(p0.isCancelled, @"");  // p0 MUST be cancelled.
    STAssertTrue(p0.isRejected, @"");
}




-(void) testChainCancel2 {
    
    // Given a chain of four tasks, cancel the root promise when it is
    // fulfilled and all other taks are pending.
    
    // Keep all references to the promises.
    // Test if promises do have the correct state when they
    // enter the handler.
    
    
    RXPromise* p0, *p1, *p2, *p3, *p4;
    
    p0 = async(0.01);  // will be finished quickly
    
    NSMutableString* e = [[NSMutableString alloc] init];
    NSMutableString* s = [[NSMutableString alloc] init];
    
    p1 = p0.then(^(id){
        STAssertFalse(p0.isPending, @"");
        STAssertTrue(p0.isFulfilled, @"");
        STAssertFalse(p0.isCancelled, @"");
        STAssertFalse(p0.isRejected, @"");
        [s appendString:@"1"];
        return async(1000); // takes a while to finish
    },^id(NSError* error){
        STFail(@"p1 error handler called");
        return error;
    });
    p2 = p1.then(^(id){
        STFail(@"p2 success handler called");
        return async(0.01);
    },^id(NSError* error){
        STAssertFalse(p1.isPending, @"");
        STAssertFalse(p1.isFulfilled, @"");
        STAssertTrue(p1.isCancelled, @"");
        STAssertTrue(p1.isRejected, @"");
        [e appendString:@"2"];
        return error;
    });
    p3 = p2.then(^(id){
        STFail(@"p3 success handler called");
        return async(0.01);
    },^id(NSError* error){
        STAssertFalse(p1.isPending, @"");
        STAssertFalse(p1.isFulfilled, @"");
        STAssertTrue(p1.isCancelled, @"");
        STAssertTrue(p1.isRejected, @"");
        [e appendString:@"3"];
        return error;
    });
    p4 = p3.then(^(id){
        STFail(@"p4 success handler called");
        return async(0.01);
    },^id(NSError* error){
        STAssertFalse(p1.isPending, @"");
        STAssertFalse(p1.isFulfilled, @"");
        STAssertTrue(p1.isCancelled, @"");
        STAssertTrue(p1.isRejected, @"");
        [e appendString:@"4"];
        return error;
    });
    
    double delayInSeconds = 0.2;
    dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayInSeconds * NSEC_PER_SEC));
    dispatch_after(popTime, dispatch_get_global_queue(0, 0), ^(void){
        [p0 cancel];
    });
    
    // wait until p4 has been resolved:
    id result = p4.get;
    STAssertTrue([s isEqualToString:@"1"], s);
    STAssertTrue([e isEqualToString:@"234"], e);
    
    STAssertTrue([result isKindOfClass:[NSError class]], @"");
    STAssertFalse(p4.isPending, @"");
    STAssertFalse(p4.isFulfilled, @"");
    STAssertTrue(p4.isCancelled, @"p4 MUST be cancelled");
    STAssertTrue(p4.isRejected, @"");
    
    result = p3.get;
    STAssertTrue([result isKindOfClass:[NSError class]], @"");
    STAssertFalse(p3.isPending, @"");
    STAssertFalse(p3.isFulfilled, @"");
    STAssertTrue(p3.isCancelled, @"p3 MUST be cancelled");
    STAssertTrue(p3.isRejected, @"");
    
    result = p2.get;
    STAssertTrue([result isKindOfClass:[NSError class]], @"");
    STAssertFalse(p2.isPending, @"");
    STAssertFalse(p2.isFulfilled, @"");
    STAssertTrue(p2.isCancelled, @"");  // p2 MUST be "cancelled"
    STAssertTrue(p2.isRejected, @"");
    
    result = p1.get;
    STAssertTrue([result isKindOfClass:[NSError class]], @"");
    STAssertFalse(p1.isPending, @"");
    STAssertFalse(p1.isFulfilled, @"");
    STAssertTrue(p1.isCancelled, @"");  // p1 MUST be "cancelled"
    STAssertTrue(p1.isRejected, @"");
    
    result = p0.get;
    STAssertFalse([result isKindOfClass:[NSError class]], @"");
    STAssertFalse(p0.isPending, @"");
    STAssertTrue(p0.isFulfilled, @"");   // P0 MUST not be cancelled
    STAssertFalse(p0.isCancelled, @"");  // p0 MUST be fulfilled.
    STAssertFalse(p0.isRejected, @"");
}

-(void) testChainCancel2WithBoundPromise {
    
    // Given a chain of four tasks, cancel the root promise when it is
    // fulfilled and all other taks are pending.
    
    // Keep all references to the promises.
    // Test if promises do have the correct state when they
    // enter the handler.
    
    
    RXPromise* p0, *p1, *p2, *p3, *p4;
    
    p0 = async_bind(0.01);  // will be finished quickly
    
    NSMutableString* e = [[NSMutableString alloc] init];
    NSMutableString* s = [[NSMutableString alloc] init];
    
    p1 = p0.then(^(id){
        STAssertFalse(p0.isPending, @"");
        STAssertTrue(p0.isFulfilled, @"");
        STAssertFalse(p0.isCancelled, @"");
        STAssertFalse(p0.isRejected, @"");
        [s appendString:@"1"];
        return async_bind(1000); // takes a while to finish
    },^id(NSError* error){
        STFail(@"p1 error handler called");
        return error;
    });
    p2 = p1.then(^(id){
        STFail(@"p2 success handler called");
        return async_bind(0.01);
    },^id(NSError* error){
        STAssertFalse(p1.isPending, @"");
        STAssertFalse(p1.isFulfilled, @"");
        STAssertTrue(p1.isCancelled, @"");
        STAssertTrue(p1.isRejected, @"");
        [e appendString:@"2"];
        return error;
    });
    p3 = p2.then(^(id){
        STFail(@"p3 success handler called");
        return async_bind(0.01);
    },^id(NSError* error){
        STAssertFalse(p1.isPending, @"");
        STAssertFalse(p1.isFulfilled, @"");
        STAssertTrue(p1.isCancelled, @"");
        STAssertTrue(p1.isRejected, @"");
        [e appendString:@"3"];
        return error;
    });
    p4 = p3.then(^(id){
        STFail(@"p4 success handler called");
        return async_bind(0.01);
    },^id(NSError* error){
        STAssertFalse(p1.isPending, @"");
        STAssertFalse(p1.isFulfilled, @"");
        STAssertTrue(p1.isCancelled, @"");
        STAssertTrue(p1.isRejected, @"");
        [e appendString:@"4"];
        return error;
    });
    
    double delayInSeconds = 0.2;
    dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayInSeconds * NSEC_PER_SEC));
    dispatch_after(popTime, dispatch_get_global_queue(0, 0), ^(void){
        [p0 cancel];
    });
    
    // wait until p4 has been resolved:
    id result = p4.get;
    STAssertTrue([s isEqualToString:@"1"], s);
    STAssertTrue([e isEqualToString:@"234"], e);
    
    STAssertTrue([result isKindOfClass:[NSError class]], @"");
    STAssertFalse(p4.isPending, @"");
    STAssertFalse(p4.isFulfilled, @"");
    STAssertTrue(p4.isCancelled, @"p4 MUST be cancelled");
    STAssertTrue(p4.isRejected, @"");
    
    result = p3.get;
    STAssertTrue([result isKindOfClass:[NSError class]], @"");
    STAssertFalse(p3.isPending, @"");
    STAssertFalse(p3.isFulfilled, @"");
    STAssertTrue(p3.isCancelled, @"p3 MUST be cancelled");
    STAssertTrue(p3.isRejected, @"");
    
    result = p2.get;
    STAssertTrue([result isKindOfClass:[NSError class]], @"");
    STAssertFalse(p2.isPending, @"");
    STAssertFalse(p2.isFulfilled, @"");
    STAssertTrue(p2.isCancelled, @"");  // p2 MUST be "cancelled"
    STAssertTrue(p2.isRejected, @"");
    
    result = p1.get;
    STAssertTrue([result isKindOfClass:[NSError class]], @"");
    STAssertFalse(p1.isPending, @"");
    STAssertFalse(p1.isFulfilled, @"");
    STAssertTrue(p1.isCancelled, @"");  // p1 MUST be "cancelled"
    STAssertTrue(p1.isRejected, @"");
    
    result = p0.get;
    STAssertFalse([result isKindOfClass:[NSError class]], @"");
    STAssertFalse(p0.isPending, @"");
    STAssertTrue(p0.isFulfilled, @"");   // P0 MUST not be cancelled
    STAssertFalse(p0.isCancelled, @"");  // p0 MUST be fulfilled.
    STAssertFalse(p0.isRejected, @"");
}


-(void) testTreeCancel1
{
    // Given a tree of promises with a root promise having three children,
    // where each childred chains another one (actually two but this last
    // one isn't exposed), cancel the root promise when it is still pending:
    //
    //        p0  ->  p00  ->  p000  -> (p_0)
    //           |
    //            ->  p01  ->  p010  -> (p_1)
    //           |
    //            ->  p02  ->  p020  -> (p_2)
    
    @autoreleasepool {
        
        semaphore finished_sem;
        
        NSMutableString*  s0 = [[NSMutableString alloc] init];
        NSMutableString*  s1 = [[NSMutableString alloc] init];
        NSMutableString*  s2 = [[NSMutableString alloc] init];
        
        RXPromise* p0 = async(1000); // op0
        
        RXPromise* p00 = p0.then(^id(id result) {
            [s0 appendString:@"0F"];
            return async(0.04);
        }, ^id(NSError *error) {
            [s0 appendString:@"0R"];
            if (p0.isCancelled) {
                [s0 appendString:@"C"];
            }
            return error;
        });
        RXPromise* p000 = p00.then(^id(id result) {
            [s0 appendString:@"00F"];
            return async(0.02);
        }, ^id(NSError *error) {
            [s0 appendString:@"00R"];
            if (p00.isCancelled) {
                [s0 appendString:@"C"];
            }
            return error;
        });
        RXPromise* p_0 = p000.then(^id(id result) {
            [s0 appendString:@"000F"];
            return nil;
        }, ^id(NSError *error) {
            [s0 appendString:@"000R"];
            if (p000.isCancelled) {
                [s0 appendString:@"C"];
            }
            return error;
        });
        
        
        RXPromise* p01 = p0.then(^id(id result) {
            [s1 appendString:@"0F"];
            return async(0.04); // op00
        }, ^id(NSError *error) {
            [s1 appendString:@"0R"];
            if (p0.isCancelled) {
                [s1 appendString:@"C"];
            }
            return error;
        });
        RXPromise* p010 = p01.then(^id(id result) {
            [s1 appendString:@"01F"];
            return async(0.02);
        }, ^id(NSError *error) {
            [s1 appendString:@"01R"];
            if (p01.isCancelled) {
                [s1 appendString:@"C"];
            }
            return error;
        });
        RXPromise* p_1 = p010.then(^id(id result) {
            [s1 appendString:@"010F"];
            return nil;
        }, ^id(NSError *error) {
            [s1 appendString:@"010R"];
            if (p010.isCancelled) {
                [s1 appendString:@"C"];
            }
            return error;
        });
        
        
        RXPromise* p02 = p0.then(^id(id result) {
            [s2 appendString:@"0F"];
            return async(0.04);
        }, ^id(NSError *error) {
            [s2 appendString:@"0R"];
            if (p0.isCancelled) {
                [s2 appendString:@"C"];
            }
            return error;
        });
        RXPromise* p020 = p02.then(^id(id result) {
            [s2 appendString:@"02F"];
            return async(0.02);
        }, ^id(NSError *error) {
            [s2 appendString:@"02R"];
            if (p02.isCancelled) {
                [s2 appendString:@"C"];
            }
            return error;
        });
        RXPromise* p_2 = p020.then(^id(id result) {
            [s2 appendString:@"020F"];
            return nil;
        }, ^id(NSError *error) {
            [s2 appendString:@"020R"];
            if (p020.isCancelled) {
                [s2 appendString:@"C"];
            }
            return error;
        });
        
        double delayInSeconds = 0.2;
        dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayInSeconds * NSEC_PER_SEC));
        dispatch_after(popTime, dispatch_get_global_queue(0, 0), ^(void){
            [p0 cancel];
        });
        
        // wait for the leaves to be resolved:
        [p_0 wait]; [p_1 wait]; [p_2 wait];
        
        STAssertTrue([s0 isEqualToString:@"0RC00RC000RC"], s0);
        STAssertTrue([s1 isEqualToString:@"0RC01RC010RC"], s1);
        STAssertTrue([s2 isEqualToString:@"0RC02RC020RC"], s2);
    }
}

-(void) testTreeCancel1WithBoundPromise
{
    // Given a tree of promises with a root promise having three children,
    // where each childred chains another one (actually two but this last
    // one isn't exposed), cancel the root promise when it is still pending:
    //
    //        p0  ->  p00  ->  p000  -> (p_0)
    //           |
    //            ->  p01  ->  p010  -> (p_1)
    //           |
    //            ->  p02  ->  p020  -> (p_2)
    
    @autoreleasepool {
        
        semaphore finished_sem;
        
        NSMutableString*  s0 = [[NSMutableString alloc] init];
        NSMutableString*  s1 = [[NSMutableString alloc] init];
        NSMutableString*  s2 = [[NSMutableString alloc] init];
        
        RXPromise* p0 = async_bind(1000); // op0
        
        RXPromise* p00 = p0.then(^id(id result) {
            [s0 appendString:@"0F"];
            return async_bind(0.04);
        }, ^id(NSError *error) {
            [s0 appendString:@"0R"];
            if (p0.isCancelled) {
                [s0 appendString:@"C"];
            }
            return error;
        });
        RXPromise* p000 = p00.then(^id(id result) {
            [s0 appendString:@"00F"];
            return async_bind(0.02);
        }, ^id(NSError *error) {
            [s0 appendString:@"00R"];
            if (p00.isCancelled) {
                [s0 appendString:@"C"];
            }
            return error;
        });
        RXPromise* p_0 = p000.then(^id(id result) {
            [s0 appendString:@"000F"];
            return nil;
        }, ^id(NSError *error) {
            [s0 appendString:@"000R"];
            if (p000.isCancelled) {
                [s0 appendString:@"C"];
            }
            return error;
        });
        
        
        RXPromise* p01 = p0.then(^id(id result) {
            [s1 appendString:@"0F"];
            return async_bind(0.04); // op00
        }, ^id(NSError *error) {
            [s1 appendString:@"0R"];
            if (p0.isCancelled) {
                [s1 appendString:@"C"];
            }
            return error;
        });
        RXPromise* p010 = p01.then(^id(id result) {
            [s1 appendString:@"01F"];
            return async_bind(0.02);
        }, ^id(NSError *error) {
            [s1 appendString:@"01R"];
            if (p01.isCancelled) {
                [s1 appendString:@"C"];
            }
            return error;
        });
        RXPromise* p_1 = p010.then(^id(id result) {
            [s1 appendString:@"010F"];
            return nil;
        }, ^id(NSError *error) {
            [s1 appendString:@"010R"];
            if (p010.isCancelled) {
                [s1 appendString:@"C"];
            }
            return error;
        });
        
        
        RXPromise* p02 = p0.then(^id(id result) {
            [s2 appendString:@"0F"];
            return async_bind(0.04);
        }, ^id(NSError *error) {
            [s2 appendString:@"0R"];
            if (p0.isCancelled) {
                [s2 appendString:@"C"];
            }
            return error;
        });
        RXPromise* p020 = p02.then(^id(id result) {
            [s2 appendString:@"02F"];
            return async_bind(0.02);
        }, ^id(NSError *error) {
            [s2 appendString:@"02R"];
            if (p02.isCancelled) {
                [s2 appendString:@"C"];
            }
            return error;
        });
        RXPromise* p_2 = p020.then(^id(id result) {
            [s2 appendString:@"020F"];
            return nil;
        }, ^id(NSError *error) {
            [s2 appendString:@"020R"];
            if (p020.isCancelled) {
                [s2 appendString:@"C"];
            }
            return error;
        });
        
        double delayInSeconds = 0.2;
        dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayInSeconds * NSEC_PER_SEC));
        dispatch_after(popTime, dispatch_get_global_queue(0, 0), ^(void){
            [p0 cancel];
        });
        
        // wait for the leaves to be resolved:
        [p_0 wait]; [p_1 wait]; [p_2 wait];
        
        STAssertTrue([s0 isEqualToString:@"0RC00RC000RC"], s0);
        STAssertTrue([s1 isEqualToString:@"0RC01RC010RC"], s1);
        STAssertTrue([s2 isEqualToString:@"0RC02RC020RC"], s2);
    }
}



-(void) testTreeCancel2
{
    // Given a tree of promises with a root promise having three children p00,
    // p01 and p02, where each childred is a chain of three, cancel the root
    // promise when it is already resolved and p00, p01 and p02 are pending.
    //
    //        p0  ->  p00  ->  p000  -> p_0
    //           |
    //            ->  p01  ->  p010  -> p_1
    //           |
    //            ->  p02  ->  p020  -> p_2
    
    @autoreleasepool {
        
        semaphore finished_sem;
        
        NSMutableString*  s0 = [[NSMutableString alloc] init];
        NSMutableString*  s1 = [[NSMutableString alloc] init];
        NSMutableString*  s2 = [[NSMutableString alloc] init];
        
        RXPromise* p0 = async(0.01); // op0
        
        RXPromise* p00 = p0.then(^id(id result) {
            [s0 appendString:@"0F"];
            return async(10);
        }, ^id(NSError *error) {
            [s0 appendString:@"0R"];
            if (p0.isCancelled) {
                [s0 appendString:@"C"];
            }
            return error;
        });
        RXPromise* p000 = p00.then(^id(id result) {
            [s0 appendString:@"00F"];
            return async(10);
        }, ^id(NSError *error) {
            [s0 appendString:@"00R"];
            if (p00.isCancelled) {
                [s0 appendString:@"C"];
            }
            return error;
        });
        RXPromise* p_0 = p000.then(^id(id result) {
            [s0 appendString:@"000F"];
            return nil;
        }, ^id(NSError *error) {
            [s0 appendString:@"000R"];
            if (p000.isCancelled) {
                [s0 appendString:@"C"];
            }
            return error;
        });
        
        
        
        RXPromise* p01 = p0.then(^id(id result) {
            [s1 appendString:@"0F"];
            return async(10); // op00
        }, ^id(NSError *error) {
            [s1 appendString:@"0R"];
            if (p0.isCancelled) {
                [s1 appendString:@"C"];
            }
            return error;
        });
        RXPromise* p010 = p01.then(^id(id result) {
            [s1 appendString:@"01F"];
            return async(10);
        }, ^id(NSError *error) {
            [s1 appendString:@"01R"];
            if (p01.isCancelled) {
                [s1 appendString:@"C"];
            }
            return error;
        });
        RXPromise* p_1 = p010.then(^id(id result) {
            [s1 appendString:@"010F"];
            return nil;
        }, ^id(NSError *error) {
            [s1 appendString:@"010R"];
            if (p010.isCancelled) {
                [s1 appendString:@"C"];
            }
            return error;
        });
        
        
        
        RXPromise* p02 = p0.then(^id(id result) {
            [s2 appendString:@"0F"];
            return async(10);
        }, ^id(NSError *error) {
            [s2 appendString:@"0R"];
            if (p0.isCancelled) {
                [s2 appendString:@"C"];
            }
            return error;
        });
        RXPromise* p020 = p02.then(^id(id result) {
            [s2 appendString:@"02F"];
            return async(10);
        }, ^id(NSError *error) {
            [s2 appendString:@"02R"];
            if (p02.isCancelled) {
                [s2 appendString:@"C"];
            }
            return error;
        });
        RXPromise* p_2 = p020.then(^id(id result) {
            [s2 appendString:@"020F"];
            return nil;
        }, ^id(NSError *error) {
            [s2 appendString:@"020R"];
            if (p020.isCancelled) {
                [s2 appendString:@"C"];
            }
            return error;
        });
        
        double delayInSeconds = 0.2;
        dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayInSeconds * NSEC_PER_SEC));
        dispatch_after(popTime, dispatch_get_global_queue(0, 0), ^(void){
            [p0 cancel];
        });
        
        // wait for the leaves to be resolved and handlers have been returned:
        [p_0 wait]; [p_1 wait]; [p_2 wait];
        
        STAssertTrue([s0 isEqualToString:@"0F00RC000RC"], s0);
        STAssertTrue([s1 isEqualToString:@"0F01RC010RC"], s1);
        STAssertTrue([s2 isEqualToString:@"0F02RC020RC"], s2);
    }
}

-(void) testTreeCancel2WithBoundPromise
{
    // Given a tree of promises with a root promise having three children p00,
    // p01 and p02, where each childred is a chain of three, cancel the root
    // promise when it is already resolved and p00, p01 and p02 are pending.
    //
    //        p0  ->  p00  ->  p000  -> p_0
    //           |
    //            ->  p01  ->  p010  -> p_1
    //           |
    //            ->  p02  ->  p020  -> p_2
    
    @autoreleasepool {
        
        semaphore finished_sem;
        
        NSMutableString*  s0 = [[NSMutableString alloc] init];
        NSMutableString*  s1 = [[NSMutableString alloc] init];
        NSMutableString*  s2 = [[NSMutableString alloc] init];
        
        RXPromise* p0 = async_bind(0.01); // op0
        
        RXPromise* p00 = p0.then(^id(id result) {
            [s0 appendString:@"0F"];
            return async_bind(10);
        }, ^id(NSError *error) {
            [s0 appendString:@"0R"];
            if (p0.isCancelled) {
                [s0 appendString:@"C"];
            }
            return error;
        });
        RXPromise* p000 = p00.then(^id(id result) {
            [s0 appendString:@"00F"];
            return async_bind(10);
        }, ^id(NSError *error) {
            [s0 appendString:@"00R"];
            if (p00.isCancelled) {
                [s0 appendString:@"C"];
            }
            return error;
        });
        RXPromise* p_0 = p000.then(^id(id result) {
            [s0 appendString:@"000F"];
            return nil;
        }, ^id(NSError *error) {
            [s0 appendString:@"000R"];
            if (p000.isCancelled) {
                [s0 appendString:@"C"];
            }
            return error;
        });
        
        
        
        RXPromise* p01 = p0.then(^id(id result) {
            [s1 appendString:@"0F"];
            return async_bind(10); // op00
        }, ^id(NSError *error) {
            [s1 appendString:@"0R"];
            if (p0.isCancelled) {
                [s1 appendString:@"C"];
            }
            return error;
        });
        RXPromise* p010 = p01.then(^id(id result) {
            [s1 appendString:@"01F"];
            return async_bind(10);
        }, ^id(NSError *error) {
            [s1 appendString:@"01R"];
            if (p01.isCancelled) {
                [s1 appendString:@"C"];
            }
            return error;
        });
        RXPromise* p_1 = p010.then(^id(id result) {
            [s1 appendString:@"010F"];
            return nil;
        }, ^id(NSError *error) {
            [s1 appendString:@"010R"];
            if (p010.isCancelled) {
                [s1 appendString:@"C"];
            }
            return error;
        });
        
        
        
        RXPromise* p02 = p0.then(^id(id result) {
            [s2 appendString:@"0F"];
            return async_bind(10);
        }, ^id(NSError *error) {
            [s2 appendString:@"0R"];
            if (p0.isCancelled) {
                [s2 appendString:@"C"];
            }
            return error;
        });
        RXPromise* p020 = p02.then(^id(id result) {
            [s2 appendString:@"02F"];
            return async_bind(10);
        }, ^id(NSError *error) {
            [s2 appendString:@"02R"];
            if (p02.isCancelled) {
                [s2 appendString:@"C"];
            }
            return error;
        });
        RXPromise* p_2 = p020.then(^id(id result) {
            [s2 appendString:@"020F"];
            return nil;
        }, ^id(NSError *error) {
            [s2 appendString:@"020R"];
            if (p020.isCancelled) {
                [s2 appendString:@"C"];
            }
            return error;
        });
        
        double delayInSeconds = 0.2;
        dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayInSeconds * NSEC_PER_SEC));
        dispatch_after(popTime, dispatch_get_global_queue(0, 0), ^(void){
            [p0 cancel];
        });
        
        // wait for the leaves to be resolved and handlers have been returned:
        [p_0 wait]; [p_1 wait]; [p_2 wait];
        
        STAssertTrue([s0 isEqualToString:@"0F00RC000RC"], s0);
        STAssertTrue([s1 isEqualToString:@"0F01RC010RC"], s1);
        STAssertTrue([s2 isEqualToString:@"0F02RC020RC"], s2);
    }
}





@end
