//
//  RXPromiseTest.mm
//  RXPromiseTest
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

#if !defined(DEBUG_LOG)
#warning DEBUG_LOG not defined
#endif

#import <XCTest/XCTest.h>

#import <RXPromise/RXPromise.h>
#import <RXPromise/RXPromise+RXExtension.h>
#include <libkern/OSAtomic.h>

#import "RXTimer.h"
#include <dispatch/dispatch.h>
#include <atomic>
#include <memory>
#include <algorithm>  // std::min
#include <string>
#include <array>
#include <cstdio>
#include <vector>

#include "DLog.h"

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


- (void) doWork
{
    if (self.isCancelled) {
        self.result = [NSString stringWithFormat:@"Operation %@ cancelled with work items left: %ld",
                       _label, (long)(_workCount - _step)];
        [self terminate];
        return;
    }
    if (_step == _failAtStep) {
        self.result = _failureReason;
        [self terminate];
    }
    if (_step == _workCount) {
        self.result = [NSString stringWithFormat:@"Operation %@ finished with result: %ld",
                       _label, (long)(_workCount)];
        [self terminate];
        return;
    }
    dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(_timeInterval * NSEC_PER_SEC));
    dispatch_after(popTime, _workerQueue, ^(void){
#if defined (LOG_VERBOSE)
        printf("%p: %ld\n", self, (long)_workCount);
#endif
        _step++;
        //[self.promise setProgress:[NSNumber numberWithInteger:_workCount]];
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

namespace mock {
    
    
    typedef void (^completion_t)(std::string const& result);
    
    enum class completion_mode {
        Succeed,
        Fail
    };
    

    namespace detail {
        
        class async_task;
        
        using shared_task = std::shared_ptr<async_task>;
        
        template <typename... Args>
        static shared_task make_shared_task(Args... args) {
            return std::make_shared<async_task>(std::forward<Args>(args)...);
        }
        
        
        class async_task {
        public:
            async_task(double duration, id result, completion_mode mode = completion_mode::Succeed)
            :   _duration (duration),
                _result (result),
                _mode (mode),
                _is_cancelled(false),
                _is_started(false)
            {
            };
            
            ~async_task() {
                //dispatch_release(_timer);
            }
            
            async_task(const async_task&) = delete;
            async_task(async_task&&) = delete;
            async_task& operator=(const async_task&) = delete;
            async_task& operator=(async_task&&) = delete;
            
            
            
            NS_RETURNS_RETAINED
            static RXPromise* start(shared_task task, completion_t completion = nullptr)  {
                return start(task, completion);
            }
            
            NS_RETURNS_RETAINED
            static RXPromise* start(shared_task task, dispatch_queue_t queue, completion_t completion = nullptr)  {
                assert(task.get() != nullptr);
                RXPromise* promise;
                async_task& op = *task.get();
                bool started = false;
                if (op._is_started.compare_exchange_strong(started, true)) {
                    promise = [[RXPromise alloc] init];
                    op._weakPromise = promise;
                    run(task, queue, completion);
                }
                return promise;
            }
            
            
        private:
            
            
            void cancel() {
                _is_cancelled = 1;
            }
            
            
            static void run(shared_task task, dispatch_queue_t queue, completion_t completion) {
                async_task& op = *task.get();
                if (queue == nil) {
                    queue = dispatch_get_global_queue(0, 0);
                    assert(queue);
                }
                op._timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, queue);
                dispatch_source_set_event_handler(op._timer, ^{
                    do_work(task, queue, completion);
                });
                dispatch_time_t interval = std::min(op._interval, static_cast<dispatch_time_t>((op._duration*0.1*NSEC_PER_SEC)));
                dispatch_source_set_timer(op._timer, DISPATCH_TIME_NOW, interval, op._leeway);
                op._end_time = dispatch_time(DISPATCH_TIME_NOW, op._duration*NSEC_PER_SEC);
                dispatch_resume(op._timer);
            }
            
            static void do_work(shared_task task, dispatch_queue_t queue, completion_t completion) {
                async_task& op = *task.get();
                bool finished = dispatch_time(DISPATCH_TIME_NOW, 0) >= op._end_time;
                RXPromise* strongPromise = op._weakPromise;
                if (finished or op._is_cancelled or strongPromise == nil or strongPromise.isCancelled) {
                    dispatch_source_cancel(op._timer);
                    std::string completion_msg;
                    if (op._is_cancelled) {
                        [strongPromise cancelWithReason:@"cancelled"];
                        completion_msg = "cancelled, no subscribers";
                    }
                    else if (strongPromise == nil or strongPromise.isCancelled) {
                        completion_msg = "cancelled";
                    }
                    else {
                        if (op._mode == completion_mode::Succeed) {
                            [strongPromise fulfillWithValue:op._result];
                            completion_msg = "finished";
                        }
                        else {
                            [strongPromise rejectWithReason:op._result];
                            completion_msg = "failed";
                        }
                    }
                    if (completion) {
                        completion(completion_msg);
                    }
                    //printf("\n");
                }
                else {
                    //printf(".");
                }
            }
            
        private:
            __weak RXPromise*   _weakPromise;
            id                  _result;
            double              _duration;
            std::atomic<bool>    _is_started;
            std::atomic<bool>    _is_cancelled;
            completion_mode     _mode;
            // timer
            dispatch_time_t     _end_time;
            dispatch_source_t   _timer;
            uint64_t            _interval = 0.01 * NSEC_PER_SEC;
            uint64_t            _leeway = 0;
        };

    }
    
    NS_RETURNS_RETAINED
    RXPromise* async(double duration, id result = @"OK",
                     completion_t completion = nullptr)
    {
        RXPromise* returnedPromise = detail::async_task::start(detail::make_shared_task(duration, result), nullptr, completion);
        assert(returnedPromise);
        return returnedPromise;
    }
    
    NS_RETURNS_RETAINED
    RXPromise* async(double duration, id result,
                     dispatch_queue_t queue, completion_t completion = nullptr)
    {
        RXPromise* returnedPromise = detail::async_task::start(detail::make_shared_task(duration, result), queue, completion);
        assert(returnedPromise);
        return returnedPromise;
    }
    
    
    
    NS_RETURNS_RETAINED
    RXPromise* async_fail(double duration, id reason = @"Failure",
                          completion_t completion = nullptr)
    {
        RXPromise* returnedPromise = detail::async_task::start(detail::make_shared_task(duration, reason, completion_mode::Fail), nullptr, completion);
        assert(returnedPromise);
        return returnedPromise;
    }
    
    
    NS_RETURNS_RETAINED
    RXPromise* async_fail(double duration, id reason,
                          dispatch_queue_t queue, completion_t completion)
    {
        RXPromise* returnedPromise = detail::async_task::start(detail::make_shared_task(duration, reason, completion_mode::Fail), queue, completion);
        assert(returnedPromise);
        return returnedPromise;
    }
    
    // use a bound promise
    NS_RETURNS_RETAINED
    static RXPromise* async_bind(double duration, id result = @"OK",
                                 dispatch_queue_t queue = nullptr, completion_t completion = nullptr)
    {
        RXPromise* promise = [RXPromise new];
        double delayInSeconds = 0.01;
        dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayInSeconds * NSEC_PER_SEC));
        dispatch_after(popTime, dispatch_get_global_queue(0, 0), ^(void){
            [promise bind:async(duration, result, queue, completion)];
        });
        return promise;
    }
    
    // use a bound promise
    NS_RETURNS_RETAINED
    static RXPromise* async_bind_fail(double duration, id reason = @"Failure",
                                      dispatch_queue_t queue = nullptr, completion_t completion = nullptr)
    {
        RXPromise* promise = [RXPromise new];
        double delayInSeconds = 0.01;
        dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayInSeconds * NSEC_PER_SEC));
        dispatch_after(popTime, dispatch_get_global_queue(0, 0), ^(void){
            [promise bind:mock::async_fail(duration, reason, queue, completion)];
        });
        return promise;
    }
    
    
    
} // namespace mock



__attribute((ns_returns_retained))
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









#pragma mark -





@interface RXPromiseTest : XCTestCase

@end

@implementation RXPromiseTest

- (void)setUp
{
    [super setUp];
    // Put setup code here. This method is called before the invocation of each test method in the class.
}

- (void)tearDown
{
    // Put teardown code here. This method is called after the invocation of each test method in the class.
    [super tearDown];
}



#pragma mark - Test Mock

- (void) disable_testAsyncMockAccuracy {
    dispatch_time_t t0 = dispatch_time(DISPATCH_TIME_NOW, 0);
    double duration = 0.1;
    [mock::async(duration, @"Finished").then(^id(id result){
        dispatch_time_t t1 = dispatch_time(DISPATCH_TIME_NOW, 0);
        XCTAssertEqualWithAccuracy(0.1*NSEC_PER_SEC, (t1 - t0), 0.1*duration*NSEC_PER_SEC, @"");
        NSLog(@"Async task accuracy: expected duration %.4f, actual duration: %.4f", duration, (double)(t1 - t0)/NSEC_PER_SEC);
        return nil;
    }, nil) wait];
}

- (void) disable_testAsyncMockCancelation {
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    dispatch_time_t t0 = dispatch_time(DISPATCH_TIME_NOW, 0);
    double duration = 1000;
    RXPromise* promise = mock::async(duration, @"Finished")
    .then(^id(id result){
        XCTFail(@"unexpected");
        dispatch_semaphore_signal(sem);
        return nil;
    },
    ^id(NSError*error) {
        dispatch_time_t t1 = dispatch_time(DISPATCH_TIME_NOW, 0);
        XCTAssertEqualWithAccuracy(0, (t1 - t0), 0.01*NSEC_PER_SEC, @"");
        NSLog(@"Async task cancellation: expected duration %.4f, actual duration: %.4f", 0.0, (double)(t1 - t0)/NSEC_PER_SEC);
        dispatch_semaphore_signal(sem);
        return nil;
    });
    [promise.parent cancel];
    dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
}



#pragma mark - API

-(void) testPromiseAPI {
    
    RXPromise* promise = [[RXPromise alloc] init];
    XCTAssertTrue( [promise respondsToSelector:@selector(then)], @"A promise must have a property 'then'" );
    XCTAssertTrue( [[promise then] isKindOfClass:NSClassFromString(@"NSBlock")], @"property 'then' must return a block");    
}


#pragma mark - Initial Invariants

-(void)testPromiseShouldInitiallyBeInPendingState
{
    @autoreleasepool {
        
        RXPromise* promise = [[RXPromise alloc] init];
        
        XCTAssertTrue(promise.isPending == YES, @"promise.isPending == YES");
        XCTAssertTrue(promise.isCancelled == NO, @"promise.isCancelled == NO");
        XCTAssertTrue(promise.isFulfilled == NO, @"promise.isFulfilled == NO");
        XCTAssertTrue(promise.isRejected == NO, @"promise.isRejected == NO");
        
        promise.then(^id(id result) {
            return nil;
        }, nil);
        
        XCTAssertTrue(promise.isPending == YES, @"promise.isPending == YES");
        XCTAssertTrue(promise.isCancelled == NO, @"promise.isCancelled == NO");
        XCTAssertTrue(promise.isFulfilled == NO, @"promise.isFulfilled == NO");
        XCTAssertTrue(promise.isRejected == NO, @"promise.isRejected == NO");
    }
}

-(void)testInitiallyResolvedPromiseShouldBeInFulfilledState {
    @autoreleasepool {
        
        RXPromise* promise1 =  [RXPromise promiseWithResult:nil];
        XCTAssertTrue(promise1.isPending == NO, @"promise.isPending == NO");
        XCTAssertTrue(promise1.isCancelled == NO, @"promise.isCancelled == NO");
        XCTAssertTrue(promise1.isFulfilled == YES, @"promise.isFulfilled == YES");
        XCTAssertTrue(promise1.isRejected == NO, @"promise.isRejected == NO");
        
        RXPromise* promise2 =  [RXPromise promiseWithResult:@"OK"];
        XCTAssertTrue(promise2.isPending == NO, @"promise.isPending == NO");
        XCTAssertTrue(promise2.isCancelled == NO, @"promise.isCancelled == NO");
        XCTAssertTrue(promise2.isFulfilled == YES, @"promise.isFulfilled == YES");
        XCTAssertTrue(promise2.isRejected == NO, @"promise.isRejected == NO");
    }
}

-(void)testInitiallyResolvedPromiseShouldBeInRejectedState {
    @autoreleasepool {
        NSError* error = [[NSError alloc] init];
        RXPromise* promise1 = [RXPromise promiseWithResult:error];
        XCTAssertTrue(promise1.isPending == NO, @"promise.isPending == NO");
        XCTAssertTrue(promise1.isCancelled == NO, @"promise.isCancelled == NO");
        XCTAssertTrue(promise1.isFulfilled == NO, @"promise.isFulfilled == NO");
        XCTAssertTrue(promise1.isRejected == YES, @"promise.isRejected == YES");
        
    }
}




#pragma mark - Once

-(void) testStateFulfilledOnce
{
    RXPromise* promise = [[RXPromise alloc] init];
    
    [promise fulfillWithValue:@"OK"];
    
    // Note: fulfillWithValue is asynchronous. That is, we need to yield to be
    // sure that the promise actually has been resolved.
    int count = 4;
    while (count--) {
        usleep(100); // yield
    }
    
    XCTAssertTrue(promise.isPending == NO, @"promise.isPending == NO");
    XCTAssertTrue(promise.isCancelled == NO, @"promise.isCancelled == NO");
    XCTAssertTrue(promise.isFulfilled == YES, @"promise.isFulfilled == YES");
    XCTAssertTrue(promise.isRejected == NO, @"promise.isRejected == NO");
    XCTAssertTrue( [promise.get isKindOfClass:[NSString class]], @"[promise.get isKindOfClass:[NSString class]]");
    XCTAssertTrue( [promise.get isEqualToString:@"OK"], @"%@", [promise.get description]);
    
    [promise fulfillWithValue:@"NO"];
    XCTAssertTrue(promise.isPending == NO, @"");
    XCTAssertTrue(promise.isCancelled == NO, @"");
    XCTAssertTrue(promise.isFulfilled == YES, @"");
    XCTAssertTrue(promise.isRejected == NO, @"");
    XCTAssertTrue( [promise.get isKindOfClass:[NSString class]], @"");
    XCTAssertTrue( [promise.get isEqualToString:@"OK"], @"%@", [promise.get description]);
    
    [promise rejectWithReason:@"Fail!"];
    XCTAssertTrue(promise.isPending == NO, @"");
    XCTAssertTrue(promise.isCancelled == NO, @"");
    XCTAssertTrue(promise.isFulfilled == YES, @"");
    XCTAssertTrue(promise.isRejected == NO, @"");
    XCTAssertTrue( [promise.get isKindOfClass:[NSString class]], @"" );
    XCTAssertTrue( [promise.get isEqualToString:@"OK"], @"%@", [promise.get description] );
    
    [promise cancelWithReason:@"Cancelled"];
    XCTAssertTrue(promise.isPending == NO, @"");
    XCTAssertTrue(promise.isCancelled == NO, @"");
    XCTAssertTrue(promise.isFulfilled == YES, @"");
    XCTAssertTrue(promise.isRejected == NO, @"");
    XCTAssertTrue( [promise.get isKindOfClass:[NSString class]], @"" );
    XCTAssertTrue( [promise.get isEqualToString:@"OK"], @"%@", [promise get] );
}


-(void)testStateRejectedOnce
{
    RXPromise* promise = [[RXPromise alloc] init];
    
    [promise rejectWithReason:@"Fail"];
    // Note: fulfillWithValue is asynchronous. That is, we need to yield to be
    // sure that the promise actually has been resolved.
    int count = 4;
    while (count--) {
        usleep(100); // yield
    }
    
    XCTAssertTrue(promise.isPending == NO, @"");
    XCTAssertTrue((promise.isPending == NO), @"promise.isPending: %d", (int)promise.isPending);
    XCTAssertTrue((promise.isCancelled == NO), @"");
    XCTAssertTrue((promise.isFulfilled == NO), @"");
    XCTAssertTrue((promise.isRejected == YES), @"");
    XCTAssertTrue( [promise.get isKindOfClass:[NSError class]], @"" );
    XCTAssertTrue([[promise.get userInfo][NSLocalizedFailureReasonErrorKey] isKindOfClass:[NSString class]], @"");
    XCTAssertTrue([[promise.get userInfo][NSLocalizedFailureReasonErrorKey] isEqualToString:@"Fail"], @"");
    
    [promise fulfillWithValue:@"NO"];
    XCTAssertTrue(promise.isPending == NO, @"");
    XCTAssertTrue(promise.isCancelled == NO, @"");
    XCTAssertTrue(promise.isFulfilled == NO, @"");
    XCTAssertTrue(promise.isRejected == YES, @"");
    XCTAssertTrue( [promise.get isKindOfClass:[NSError class]], @"" );
    XCTAssertTrue([[promise.get userInfo][NSLocalizedFailureReasonErrorKey] isKindOfClass:[NSString class]], @"");
    XCTAssertTrue([[promise.get userInfo][NSLocalizedFailureReasonErrorKey] isEqualToString:@"Fail"], @"");
    
    [promise rejectWithReason:@"Fail!"];
    XCTAssertTrue(promise.isPending == NO, @"");
    XCTAssertTrue(promise.isCancelled == NO, @"");
    XCTAssertTrue(promise.isFulfilled == NO, @"");
    XCTAssertTrue(promise.isRejected == YES, @"");
    XCTAssertTrue( [promise.get isKindOfClass:[NSError class]], @"" );
    XCTAssertTrue([[promise.get userInfo][NSLocalizedFailureReasonErrorKey] isKindOfClass:[NSString class]], @"");
    XCTAssertTrue([[promise.get userInfo][NSLocalizedFailureReasonErrorKey] isEqualToString:@"Fail"], @"");
    
    [promise cancelWithReason:@"Cancelled"];
    XCTAssertTrue(promise.isPending == NO, @"");
    XCTAssertTrue(promise.isCancelled == NO, @"");
    XCTAssertTrue(promise.isFulfilled == NO, @"");
    XCTAssertTrue(promise.isRejected == YES, @"");
    XCTAssertTrue( [promise.get isKindOfClass:[NSError class]], @"");
    XCTAssertTrue([[promise.get userInfo][NSLocalizedFailureReasonErrorKey] isKindOfClass:[NSString class]], @"");
    XCTAssertTrue([[promise.get userInfo][NSLocalizedFailureReasonErrorKey] isEqualToString:@"Fail"], @"");
}


-(void)testStateCancelledOnce
{
    RXPromise* promise = [[RXPromise alloc] init];
    
    [promise cancelWithReason:@"Cancelled"];
    // Note: fulfillWithValue is asynchronous. That is, we need to yield to be
    // sure that the promise actually has been resolved.
    int count = 10;
    while (count--) {
        usleep(100); // yield
    }
    
    XCTAssertTrue(promise.isPending == NO, @"");
    XCTAssertTrue(promise.isPending == NO, @"promise.isPending: %d", (int)promise.isPending);
    XCTAssertTrue(promise.isCancelled == YES, @"");
    XCTAssertTrue(promise.isFulfilled == NO, @"");
    XCTAssertTrue(promise.isRejected == YES, @"");
    XCTAssertTrue([promise.get isKindOfClass:[NSError class]], @"" );
    XCTAssertTrue([[promise.get userInfo][NSLocalizedFailureReasonErrorKey] isKindOfClass:[NSString class]], @"");
    XCTAssertTrue([promise.get code] == -1, @"");
    XCTAssertTrue([[promise.get userInfo][NSLocalizedFailureReasonErrorKey] isEqualToString:@"Cancelled"], @"");
    
    [promise fulfillWithValue:@"NO"];
    XCTAssertTrue(promise.isPending == NO, @"");
    XCTAssertTrue(promise.isCancelled == YES, @"");
    XCTAssertTrue(promise.isFulfilled == NO, @"");
    XCTAssertTrue(promise.isRejected == YES, @"");
    XCTAssertTrue([promise.get isKindOfClass:[NSError class]], @"" );
    XCTAssertTrue([[promise.get userInfo][NSLocalizedFailureReasonErrorKey] isKindOfClass:[NSString class]], @"");
    XCTAssertTrue([promise.get code] == -1, @"");
    XCTAssertTrue([[promise.get userInfo][NSLocalizedFailureReasonErrorKey] isEqualToString:@"Cancelled"], @"");
    
    [promise rejectWithReason:@"Fail!"];
    XCTAssertTrue(promise.isPending == NO, @"");
    XCTAssertTrue(promise.isCancelled == YES, @"");
    XCTAssertTrue(promise.isFulfilled == NO, @"");
    XCTAssertTrue(promise.isRejected == YES, @"");
    XCTAssertTrue( [promise.get isKindOfClass:[NSError class]], @"" );
    XCTAssertTrue([[promise.get userInfo][NSLocalizedFailureReasonErrorKey] isKindOfClass:[NSString class]], @"");
    XCTAssertTrue([promise.get code] == -1, @"");
    XCTAssertTrue([[promise.get userInfo][NSLocalizedFailureReasonErrorKey] isEqualToString:@"Cancelled"], @"");
    
    [promise cancelWithReason:@"Cancelled"];
    XCTAssertTrue(promise.isPending == NO, @"");
    XCTAssertTrue(promise.isCancelled == YES, @"");
    XCTAssertTrue(promise.isFulfilled == NO, @"");
    XCTAssertTrue(promise.isRejected == YES, @"");
    XCTAssertTrue( [promise.get isKindOfClass:[NSError class]], @"" );
    XCTAssertTrue([[promise.get userInfo][NSLocalizedFailureReasonErrorKey] isKindOfClass:[NSString class]], @"");
    XCTAssertTrue([promise.get code] == -1, @"");
    XCTAssertTrue([[promise.get userInfo][NSLocalizedFailureReasonErrorKey] isEqualToString:@"Cancelled"], @"");
}


#pragma mark - Livetime

- (void) testPromiseMustNotBeDeallocatedIfHandlersSetupAndNotResolved {
    // Requirement:
    //
    // A promise MUST be retained when handlers will be registered and released
    // when a handler is finally run due to resolving the promise. This implies,
    // that a promise MUST eventually be resolved in order to prevent leaks.
    //
    // Rationale:
    //
    // An asynchronouns result provider creates its promise and keeps a reference
    // to it. When it finally resolves it, it may also immediately releases the
    // promise. If registering the handlers were only keeping a weak reference to
    // the promise, the promise may now deallocate before the handler actually run.
    // When the handler runs, they would miss the promise where they get the state
    // and result information. Thus, a promise must be retained when handlers
    // will be registered.
    
    __weak RXPromise* weakPromise;
    @autoreleasepool {
        @autoreleasepool {
            @autoreleasepool {
                RXPromise* promise = [RXPromise new];
                weakPromise = promise;
                promise.then(^id(id result) {
                    return nil;
                }, nil);
            }
            int count = 10;
            while (count--) {
                usleep(1000); // yield
            }
        }
        //XCTAssertTrue(weakPromise != nil, @"");
        [weakPromise cancel];
        int count = 10;
        while (count--) {
            usleep(1000); // yield
        }
    }
    XCTAssertTrue(weakPromise == nil, @"");
}


- (void) testBoundPromiseShouldBeDeallocatedAfterResolving {
    
    __weak RXPromise* weakOther;
    __weak RXPromise* weakPromise;
    
    @autoreleasepool {
        RXPromise* promise = [[RXPromise alloc] init];
        weakPromise = promise;
        @autoreleasepool {
            RXPromise* other = [[RXPromise alloc] init];
            weakOther = other;
            [promise bind:other];
            [other fulfillWithValue:@"OK"];
            [other get];
            other = nil;
            int count = 10;
            while (count--) usleep(100);
            XCTAssertTrue(weakOther == nil, @"other promise must be deallocated");
        }
    }
    int count = 5;
    while (count--)
        usleep(100);
    
    XCTAssertTrue(weakPromise == nil, @"promise must be deallocated");
}


- (void) testParentPromisesMustBeRetained {
    NSMutableString* s = [[NSMutableString alloc] init];
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    mock::async(0.1, @"A")
    .then(^id(id result) {
        [s appendString:@"A"];
        return mock::async(0.05, @"B");
    }, nil)
    .then(^id(id result) {
        [s appendString:@"B"];
        return mock::async(0.05, @"C");
    }, nil)
    .then(^id(id result) {
        [s appendString:@"C"];
        return mock::async(0.05, @"D");
    }, nil)
    .then(^id(id result) {
        [s appendString:@"D"];
        return mock::async(0.05, @"E");
    }, nil)
    .then(^id(id result) {
        [s appendString:@"E"];
        dispatch_semaphore_signal(sem);
        return nil;
    }, nil);
    
    XCTAssertTrue(0 == dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 1*NSEC_PER_SEC)), @"");
    XCTAssertTrue([@"ABCDE" isEqualToString:s], @"");
}

- (void)testPromiseWithDeallocHandler {
    
    typedef RXPromise* (^task_t)(void);
    
    // Create an asynchronous task which will just keep a weak reference to its
    // associated task. This task well never finish, unless there are no
    // subscribers - or a timeout occurred.
    // Returns a root promise which is not retained by the asychronous task.
    
    dispatch_semaphore_t finishedSem = dispatch_semaphore_create(0);
    
    task_t block = ^RXPromise*() {
        dispatch_semaphore_t subscriberSem = dispatch_semaphore_create(0);
        RXPromise* promise = [RXPromise promiseWithDeallocHandler:^{
            dispatch_semaphore_signal(subscriberSem);
        }];
        XCTAssertNotNil(promise, @"");
        __weak RXPromise* weakPromise = promise;
        dispatch_async(dispatch_get_global_queue(0, 0), ^{
            
            double delayInSeconds = 3.0;
            dispatch_time_t timeout = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayInSeconds * NSEC_PER_SEC));
            if (dispatch_semaphore_wait(subscriberSem, timeout) == 0) {
                // Expected: task has no subscribers
            }
            else {
                XCTFail(@"async task timeout");
            }
            RXPromise* strongPromise = weakPromise;
            XCTAssertNil(strongPromise, @"");
            if (strongPromise) {
                [strongPromise rejectWithReason:@"should have no subscribers"];
            }
            dispatch_semaphore_signal(finishedSem);
        });
        
        return promise;
    };
    
    // Keep a subscriber for 0.1 seconds:
    @autoreleasepool {
        [block() setTimeout:0.1]
        .then(^id(id result) {
            return nil;
        }, ^id(NSError* error) {
            return nil;
        });
    }
    
    // When we reach here, the async task should terminate since there are no
    // subscribers anymore.
    
    double delayInSeconds = 3.0;
    dispatch_time_t timeout = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayInSeconds * NSEC_PER_SEC));
    if (dispatch_semaphore_wait(finishedSem, timeout) == 0) {
        // Expected: after 0.1 sec, no subscribers exist and the async task should terminate
    }
    else {
        XCTFail(@"Unexpected: timeout");
    }
}


#pragma mark - bind

- (void) testBoundPromiseShouldAdoptFulfillment {

    __weak RXPromise* weakOther;
    RXPromise* promise = [[RXPromise alloc] init];

    @autoreleasepool {
        RXPromise* other = [[RXPromise alloc] init];
        weakOther = other;
        [promise bind:other];
        [other fulfillWithValue:@"OK"];
        other = nil;
    }
    id result = promise.get;
    XCTAssertTrue(promise.isPending == NO, @"");
    XCTAssertTrue(promise.isCancelled == NO, @"");
    XCTAssertTrue(promise.isFulfilled == YES, @"");
    XCTAssertTrue(promise.isRejected == NO, @"");
    XCTAssertTrue(weakOther == nil, @"other promise must be deallocated");
    XCTAssertTrue( [result isEqualToString:@"OK"],  @"promise shall assimilate the result of the bound promise - which is @\"OK\"" );

}

- (void) testBoundPromiseShouldAdoptRejection {
    
    __weak RXPromise* weakOther;
    RXPromise* promise = [[RXPromise alloc] init];
    
    @autoreleasepool {
        RXPromise* other = [[RXPromise alloc] init];
        weakOther = other;
        [promise bind:other];
        [other rejectWithReason:@"FAIL"];
        other = nil;
    }
    id result = promise.get;
    XCTAssertTrue(promise.isPending == NO, @"");
    XCTAssertTrue(promise.isCancelled == NO, @"");
    XCTAssertTrue(promise.isFulfilled == NO, @"");
    XCTAssertTrue(promise.isRejected == YES, @"");
    XCTAssertTrue(weakOther == nil, @"other promise must be deallocated");
    XCTAssertTrue([result isKindOfClass:[NSError class]], @"");
    XCTAssertTrue( [[result userInfo][NSLocalizedFailureReasonErrorKey] isEqualToString:@"FAIL"],  @"promise shall assimilate the result of the bound promise" );
    
}

- (void) testBoundPromiseShouldAdoptCancellation {
    
    __weak RXPromise* weakOther;
    RXPromise* promise = [[RXPromise alloc] init];
    
    @autoreleasepool {
        RXPromise* other = [[RXPromise alloc] init];
        weakOther = other;
        [promise bind:other];
        [other cancel];
        other = nil;
    }
    id result = promise.get;
    XCTAssertTrue(promise.isPending == NO, @"");
    XCTAssertTrue(promise.isCancelled == YES, @"");
    XCTAssertTrue(promise.isFulfilled == NO, @"");
    XCTAssertTrue(promise.isRejected == YES, @"");
    XCTAssertTrue(weakOther == nil, @"other promise must be deallocated");
    XCTAssertTrue([result isKindOfClass:[NSError class]], @"");
    XCTAssertTrue( [result code] == -1, @""); /* cancelled */
}

- (void) testMultipleBindAtoCandBtoC {
//    
//         /--< A
//    C - /
//        \
//         \--< B
//    
//    - C will adopt A OR B, which ever will be resolved first.
//    - If C will be fulfilled through A, B SHALL not be affected.
//    - If C will be rejected through A, B SHALL not be affected.
//    - If C receives a cancel message, C will forward cancellation to A AND B.
    
    
    RXPromise* a = [[RXPromise alloc] init];
    RXPromise* b = [[RXPromise alloc] init];
    RXPromise* c = [[RXPromise alloc] init];
    
    [c bind:a];
    [c bind:b];
    
    [a fulfillWithValue:@"OK"];

    id ra = a.get;
    id rc = c.get;
    [b setTimeout:0.1];
    [b.then(^id(id result) {
        XCTFail(@"success handler not expected");
        return nil;
    }, ^id(NSError* error) {
        XCTAssertTrue(error.code == -1001, @"");
        return nil;
    }) wait];
    
    XCTAssertTrue(ra == rc, @"");
    
    XCTAssertTrue(a.isPending == NO, @"");
    XCTAssertTrue(a.isCancelled == NO, @"");
    XCTAssertTrue(a.isFulfilled == YES, @"");
    XCTAssertTrue(a.isRejected == NO, @"");

    XCTAssertTrue(c.isPending == NO, @"");
    XCTAssertTrue(c.isCancelled == NO, @"");
    XCTAssertTrue(c.isFulfilled == YES, @"");
    XCTAssertTrue(c.isRejected == NO, @"");

    XCTAssertTrue(b.isPending == NO, @"");
    XCTAssertTrue(b.isCancelled == NO, @"");
    XCTAssertTrue(b.isFulfilled == NO, @"");
    XCTAssertTrue(b.isRejected == YES, @"");  // timeout
}



#pragma mark - Success / Failure

-(void) testBasicSuccess
{
    // Check whether a promise fires its handlers in due time:
    
    @autoreleasepool {
        
        dispatch_semaphore_t finished_sem = dispatch_semaphore_create(0);
        
        asyncOp(@"A", 1, nil, 0.01)
        .then(^id(id) {
            dispatch_semaphore_signal(finished_sem);
            return nil;
        },
        ^id(NSError* error) {
            XCTFail(@"error handler must not be called");
            dispatch_semaphore_signal(finished_sem);
            return nil;
        });
        
        // The operation is finished after about 0.01 s. Thus, the handler should
        // start to execute after about 0.01 seconds. Given a reasonable delay:
        XCTAssertTrue(dispatch_semaphore_wait(finished_sem, dispatch_time(DISPATCH_TIME_NOW, 1*NSEC_PER_SEC)) == 0,
        @"success callback not called after 1 second");
    }
}

-(void) testBasicSuccessWithQueue
{
    // Check whether a promise fires its handlers in due time:
    
    @autoreleasepool {
        // Note: When `thenOn`'s block is invoked, the handler is invoked on the
        // specified queue via a dispatch_barrier_sync. This means, write access
        // to shared resources occuring within the handler is thread safe.
        const char* QueueID = "com.test.queue.id";
        dispatch_queue_t concurrentQueue = dispatch_queue_create("my.concurrent.queue", DISPATCH_QUEUE_CONCURRENT);
        dispatch_queue_set_specific(concurrentQueue, QueueID, (__bridge void*)concurrentQueue, NULL);
        
        dispatch_semaphore_t finished_sem = dispatch_semaphore_create(0);
        
        asyncOp(@"A", 1, nil, 0.01).thenOn(concurrentQueue, ^id(id){
            XCTAssertTrue( dispatch_get_specific(QueueID) == (__bridge void *)(concurrentQueue), @"");
            dispatch_semaphore_signal(finished_sem); return nil;
        }, ^id(NSError* error){
            XCTFail(@"error handler must not be called");
            return nil;
        });
        
        // The operation is finished after about 0.01 s. Thus, the handler should
        // start to execute after about 0.01 seconds. Given a reasonable delay:
        XCTAssertTrue(dispatch_semaphore_wait(finished_sem, dispatch_time(DISPATCH_TIME_NOW, 1*NSEC_PER_SEC)) == 0,
                     @"success callback not called after 1 second");
    }
}

-(void) testBasicFailure
{
    // Check whether a promise fires its error handler in due time:
    
    @autoreleasepool {
        
        dispatch_semaphore_t finished_sem = dispatch_semaphore_create(0);
        
        mock::async_fail(.01).then(^id(id){
            XCTFail(@"success handler must not be called");
            return nil;
        }, ^id(NSError* error){
            dispatch_semaphore_signal(finished_sem);
            return nil;
        });
        
        // The operation is finished after about 0.01 s. Thus, the handler should
        // start to execute after about 0.01 seconds. Given a reasonable delay:
        XCTAssertTrue(dispatch_semaphore_wait(finished_sem, dispatch_time(DISPATCH_TIME_NOW, 1*NSEC_PER_SEC)) == 0,
                     @"error callback not called after 1 second");
    }
}

-(void) testBasicFailureWithQueue
{
    // Check whether a promise fires its error handler in due time:
    
    @autoreleasepool {
        
        // Note: When `thenOn`'s block is invoked, the handler is invoked on the
        // specified queue via a dispatch_barrier_sync. This means, write access
        // to shared resources occuring within the handler is thread safe.
        const char* QueueID = "com.test.queue.id";
        dispatch_queue_t concurrentQueue = dispatch_queue_create("my.concurrent.queue", DISPATCH_QUEUE_CONCURRENT);
        dispatch_queue_set_specific(concurrentQueue, QueueID, (__bridge void*)concurrentQueue, NULL);
        
        dispatch_semaphore_t finished_sem = dispatch_semaphore_create(0);
        
        mock::async_fail(.01).thenOn(concurrentQueue, ^id(id){
            XCTFail(@"success handler must not be called");
            return nil;
        }, ^id(NSError* error){
            XCTAssertTrue( dispatch_get_specific(QueueID) == (__bridge void *)(concurrentQueue), @"");
            dispatch_semaphore_signal(finished_sem);
            return nil;
        });
        
        // The operation should be finished after about 0.01 s. Thus, the handler should
        // start to execute after about 0.01 seconds. Given a reasonable delay:
        XCTAssertTrue(dispatch_semaphore_wait(finished_sem, dispatch_time(DISPATCH_TIME_NOW, 1*NSEC_PER_SEC)) == 0,
                     @"error callback not called after 1 second");
    }
}

-(void) testBasicFailureWithoutErrorHandler
{
    // Check whether a promise fires its handlers in due time:
    
    @autoreleasepool {
        
        semaphore finished_sem;
        semaphore& semRef = finished_sem;
        
        RXPromise* promise0 = mock::async_fail(0.01, @"Failure");
        RXPromise* promise1 = promise0.then(^id(id){
            semRef.signal();
            return nil;
        }, nil);
        
        // The operation is finished with a failure after about 0.01 s. Thus, the
        // success handler should not be called, and the semaphore must timeout:
        XCTAssertFalse(finished_sem.wait(0.10), @"success callback called after 0.10 second");
        XCTAssertFalse(promise0.isPending, @"");
        XCTAssertFalse(promise0.isFulfilled, @"");
        XCTAssertFalse(promise0.isCancelled, @"");
        XCTAssertTrue(promise0.isRejected, @"");
        id result0 = promise0.get;
        XCTAssertTrue([result0 isKindOfClass:[NSError class]], @"%@", [result0 description]);
        
        XCTAssertFalse(promise1.isPending, @"");
        XCTAssertFalse(promise1.isFulfilled, @"");
        XCTAssertFalse(promise1.isCancelled, @"");
        XCTAssertTrue(promise1.isRejected, @"");
        id result1 = promise1.get;
        XCTAssertTrue([result1 isKindOfClass:[NSError class]], @"%@", result1);
        
    }
}




#pragma mark - Chaining

-(void) testBasicChaining1
{
    // Keep a reference the last promise
    
    RXPromise* p = mock::async(0.01, @"A")
    .then(^id(id result){ return result; }, nil);
    
    // Promise `p` shall have the state of the return value of the last handler (which is @"A"), unless an error occurred:
    id result = p.get;
    XCTAssertTrue( [result isEqualToString:@"A"],  @"result shall have the result of the last async function - which is @\"A\"" );
    XCTAssertTrue( p.isFulfilled, @"");
    XCTAssertFalse( p.isCancelled, @"");
    XCTAssertFalse( p.isRejected, @"");
}


-(void) testBasicChaining2
{
    RXPromise* p = mock::async(0.01, @"A")
    .then(^id(id result){
        return mock::async(0.01, @"B");
    }, nil)
    .then(^id(id result){
        return result;
    }, nil);
    
    // Promise `p` shall have the state of the return value of the last handler (which is @"B"), unless an error occurred:
    id result = p.get;
    XCTAssertTrue( [result isEqualToString:@"B"],  @"result shall have the result of the last async function - which is @\"B\"" );
    XCTAssertTrue( p.isFulfilled, @"");
    XCTAssertFalse( p.isCancelled, @"");
    XCTAssertFalse( p.isRejected, @"");
}


-(void) testBasicChaining3
{
    RXPromise* p = mock::async(0.01, @"A")
    .then(^id(id result){return mock::async(0.01, @"B");}, nil)
    .then(^id(id result){return mock::async(0.01, @"C");}, nil)
    .then(^id(id result){return result; }, nil);
    
    // Promise `p` shall have the state of the return value of the last handler (which is @"C"), unless an error occurred:
    id result = p.get;
    XCTAssertTrue( [result isEqualToString:@"C"],  @"result shall have the result of the last async function - which is @\"C\"" );
    XCTAssertTrue( p.isFulfilled, @"");
    XCTAssertFalse( p.isCancelled, @"");
    XCTAssertFalse( p.isRejected, @"");
}


-(void) testBasicChaining4
{
    RXPromise* p = mock::async(0.01, @"A")
    .then(^id(id result){return mock::async(0.01, @"B");}, nil)
    .then(^id(id result){return mock::async(0.01, @"C");}, nil)
    .then(^id(id result){return mock::async(0.01, @"D");}, nil)
    .then(^id(id result){return result; }, nil);
    
    // Promise `p` shall have the state of the return value of the last handler (which is @"D"), unless an error occurred:
    id result = p.get;
    XCTAssertTrue( [result isEqualToString:@"D"],  @"result shall have the result of the last async function - which is @\"D\"" );
    XCTAssertTrue( p.isFulfilled, @"");
    XCTAssertFalse( p.isCancelled, @"");
    XCTAssertFalse( p.isRejected, @"");
}


-(void) testBasicChainingWithBoundPromise
{
    // A bound promise shall effectively be transparent to the user.
    RXPromise* p = mock::async_bind(0.01, @"A")
    .then(^(id){return mock::async_bind(0.01, @"B");}, nil)
    .then(^(id){return mock::async_bind(0.01, @"C");}, nil)
    .then(^(id){return mock::async_bind(0.01, @"D");}, nil);
    
    // Promise `p` shall have the state of the last async function, unless an error occurred:
    id result = p.get;
    XCTAssertTrue( [result isEqualToString:@"D"],  @"result shall have the result of the last async function - which is @\"D\"" );
    XCTAssertTrue( p.isFulfilled, @"");
    XCTAssertFalse( p.isCancelled, @"");
    XCTAssertFalse( p.isRejected, @"");
}


-(void) testBasicChainingWithImmediateNilResult
{
    RXPromise* p = mock::async(0.01, @"A")
    .then(^(id){return mock::async(0.01, @"B");}, nil)
    .then(^(id){return mock::async(0.01, @"C");}, nil)
    .then(^id(id){return nil;}, nil);
    
    // Promise `p` shall have the state of the last async function, unless an error occurred:
    id result = p.get;
    XCTAssertTrue( result == nil, @"result shall have the result of the last async function - which is nil" );
    XCTAssertTrue( p.isFulfilled, @"");
    XCTAssertFalse( p.isCancelled, @"");
    XCTAssertFalse( p.isRejected, @"");
}


-(void) testBasicChainingWithImmediateNilResultBoundPromise
{
    // A bound promise shall be transparent to the user.
    RXPromise* p = mock::async_bind(0.01, @"A")
    .then(^(id){return mock::async_bind(0.01, @"B");}, nil)
    .then(^(id){return mock::async_bind(0.01, @"C");}, nil)
    .then(^id(id){return nil;}, nil);
    
    // Promise `p` shall have the state of the last async function, unless an error occurred:
    id result = p.get;
    XCTAssertTrue( result == nil, @"result shall have the result of the last async function - which is nil" );
    XCTAssertTrue( p.isFulfilled, @"");
    XCTAssertFalse( p.isCancelled, @"");
    XCTAssertFalse( p.isRejected, @"");
}


-(void) testBasicChainingWithImmediateResult
{
    RXPromise* p = mock::async(0.01, @"A")
    .then(^(id){return mock::async(0.01, @"B");}, nil)
    .then(^(id){return mock::async(0.01, @"C");}, nil)
    .then(^id(id){return @"OK";}, nil);
    
    // Promise `p` shall have the state of the last async function, unless an error occurred:
    id result = p.get;
    XCTAssertTrue( [result isEqualToString:@"OK"], @"result shall have the result of the last async function - which is @\"OK\"" );
    XCTAssertTrue( p.isFulfilled, @"");
    XCTAssertFalse( p.isCancelled, @"");
    XCTAssertFalse( p.isRejected, @"");
}


-(void) testBasicChainingWithImmediateResultWithBoundPromise
{
    // A bound promise shall be transparent to the user.
    RXPromise* p = mock::async_bind(0.01, @"A")
    .then(^(id){return mock::async_bind(0.01, @"B");}, nil)
    .then(^(id){return mock::async_bind(0.01, @"C");}, nil)
    .then(^id(id){return @"OK";}, nil);
    
    // Promise `p` shall have the state of the last async function, unless an error occurred:
    id result = p.get;
    XCTAssertTrue( [result isEqualToString:@"OK"], @"result shall have the result of the last async function - which is @\"OK\"" );
    XCTAssertTrue( p.isFulfilled, @"");
    XCTAssertFalse( p.isCancelled, @"");
    XCTAssertFalse( p.isRejected, @"");
}


-(void) testBasicChainingWithFailure
{
    RXPromise* p = mock::async(0.01, @"A")
    .then(^(id){return mock::async(0.01, @"B");}, nil)
    .then(^(id){return mock::async_fail(0.01, @"C:Failure");}, nil)
    .then(^(id){return mock::async(0.01, @"D");}, nil);
    
    id result = p.get;
    XCTAssertTrue( [result isKindOfClass:[NSError class]], @"");
    XCTAssertTrue( [[result userInfo][NSLocalizedFailureReasonErrorKey] isEqualToString:@"C:Failure"], @"" );
    XCTAssertFalse( p.isFulfilled, @"");
    XCTAssertFalse( p.isCancelled, @"");
    XCTAssertTrue( p.isRejected, @"");
}


-(void) testBasicChainingWithFailureWithBoundPromise
{
    // A bound promise shall be transparent to the user.
    RXPromise* p = mock::async_bind(0.01, @"A")
    .then(^(id){return mock::async_bind(0.01, @"B");}, nil)
    .then(^(id){return mock::async_bind_fail(0.01, @"C:Failure");}, nil)
    .then(^(id){return mock::async_bind(0.01, @"D");}, nil);
    
    id result = p.get;
    XCTAssertTrue( [result isKindOfClass:[NSError class]], @"");
    XCTAssertTrue( [[result userInfo][NSLocalizedFailureReasonErrorKey] isEqualToString:@"C:Failure"], @"" );
    XCTAssertFalse( p.isFulfilled, @"");
    XCTAssertFalse( p.isCancelled, @"");
    XCTAssertTrue( p.isRejected, @"");
}


-(void) testBasicChainingWithImmediateError
{
    RXPromise* p = mock::async(0.01, @"A")
    .then(^(id){return mock::async(0.01, @"B");}, nil)
    .then(^(id){return mock::async(0.01, @"C");}, nil)
    .then(^(id){return [NSError errorWithDomain:@"Test" code:10 userInfo:nil];}, nil);
    
    id result = p.get;
    XCTAssertTrue( [result isKindOfClass:[NSError class]] == YES, @"" );
    XCTAssertTrue(10 == (int)[result code], @"");
    XCTAssertFalse( p.isFulfilled, @"");
    XCTAssertFalse( p.isCancelled, @"");
    XCTAssertTrue( p.isRejected, @"");
}


-(void) testBasicChainingWithImmediateErrorWithBoundPromise
{
    RXPromise* p = mock::async_bind(0.01, @"A")
    .then(^(id){return mock::async_bind(0.01, @"B");}, nil)
    .then(^(id){return mock::async_bind(0.01, @"C");}, nil)
    .then(^(id){return [NSError errorWithDomain:@"Test" code:10 userInfo:nil];}, nil);
    
    id result = p.get;
    XCTAssertTrue( [result isKindOfClass:[NSError class]], @"" );
    XCTAssertTrue(10 == (int)[result code], @"");
    XCTAssertFalse( p.isFulfilled, @"");
    XCTAssertFalse( p.isCancelled, @"");
    XCTAssertTrue( p.isRejected, @"");
}


- (void) testChainingTestForwardResult
{
    // As an exercise we only keep a reference to the root promise. The root
    // promise will be fulfilled when the first async task finishes. That is,
    // it can't be used to tell us when all tasks have been completed.
    
    // Test whether the result will be forwarded and the handlers exexcute in
    // order.
    
    dispatch_semaphore_t finished_sem = dispatch_semaphore_create(0);
    NSMutableString* s = [[NSMutableString alloc] init];
    RXPromise* p = mock::async(0.01, @"A");
    p.then(^(id result){ [s appendString:result]; return mock::async(0.01, @"B");},nil)
    .then(^(id result){ [s appendString:result]; return mock::async(0.01, @"C");},nil)
    .then(^(id result){ [s appendString:result]; return mock::async(0.01, @"D");},nil)
    .then(^id(id result){
        [s appendString:result];
        dispatch_semaphore_signal(finished_sem);
        return nil;
    },nil);
    
    dispatch_semaphore_wait(finished_sem, DISPATCH_TIME_FOREVER);
    XCTAssertTrue( [s isEqualToString:@"ABCD"], @"" );
    XCTAssertFalse(p.isPending, @"");
    XCTAssertTrue(p.isFulfilled, @"");
    XCTAssertFalse(p.isCancelled, @"");
    XCTAssertFalse(p.isRejected, @"");
    XCTAssertTrue( [p.get isEqualToString:@"A"], @"" );
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
    RXPromise* p = mock::async_bind(0.01, @"A");
    p.then(^(id result){ [s appendString:result]; return mock::async_bind(0.01, @"B");},nil)
    .then(^(id result){ [s appendString:result]; return mock::async_bind(0.01, @"C");},nil)
    .then(^(id result){ [s appendString:result]; return mock::async_bind(0.01, @"D");},nil)
    .then(^id(id result){
        [s appendString:result];
        dispatch_semaphore_signal(finished_sem);
        return nil;
    },nil);
    
    dispatch_semaphore_wait(finished_sem, DISPATCH_TIME_FOREVER);
    XCTAssertTrue( [s isEqualToString:@"ABCD"], @"" );
    XCTAssertFalse(p.isPending, @"");
    XCTAssertTrue(p.isFulfilled, @"");
    XCTAssertFalse(p.isCancelled, @"");
    XCTAssertFalse(p.isRejected, @"");
    XCTAssertTrue( [p.get isEqualToString:@"A"], @"" );
}


-(void) testChainingStates {
    
    // Keep all references to the promises.
    // Test if promises do have the correct state when they
    // enter the handler.
    
    RXPromise* p0, *p1, *p2, *p3, *p4;
    p0 = mock::async(0.1);
    
    NSMutableString* s = [[NSMutableString alloc] init];
    
    p1 = p0.then(^(id){
        // Note: accessing p1 in this handler is not safe!
        XCTAssertFalse(p0.isPending, @"");
        XCTAssertTrue(p0.isFulfilled, @"");
        XCTAssertFalse(p0.isCancelled, @"");
        XCTAssertFalse(p0.isRejected, @"");
        [s appendString:@"A"];
        return mock::async(0.01);
    },^id(NSError* error){
        XCTFail(@"p1 error handler called");
        return error;
    });
    p2 = p1.then(^(id){
        XCTAssertFalse(p1.isPending, @"");
        XCTAssertTrue(p1.isFulfilled, @"");
        XCTAssertFalse(p1.isCancelled, @"");
        XCTAssertFalse(p1.isRejected, @"");
        [s appendString:@"B"];
        return mock::async(0.01);
    },^id(NSError* error){
        XCTFail(@"p2 error handler called");
        return error;
    });
    p3 = p2.then(^(id){
        XCTAssertFalse(p2.isPending, @"");
        XCTAssertTrue(p2.isFulfilled, @"");
        XCTAssertFalse(p2.isCancelled, @"");
        XCTAssertFalse(p2.isRejected, @"");
        [s appendString:@"C"];
        return mock::async(0.01);
    },^id(NSError* error){
        XCTFail(@"p3 error handler called");
        return error;
    });
    p4 = p3.then(^(id){
        XCTAssertFalse(p3.isPending, @"");
        XCTAssertTrue(p3.isFulfilled, @"");
        XCTAssertFalse(p3.isCancelled, @"");
        XCTAssertFalse(p3.isRejected, @"");
        [s appendString:@"D"];
        return mock::async(0.01);
    },^id(NSError* error){
        XCTFail(@"p4 error handler called");
        return error;
    });
    
    // p0 will resolve after 0.1 seconds, so hurry to check all promises:
    XCTAssertTrue(p0.isPending, @"");
    XCTAssertTrue(p1.isPending, @"");
    XCTAssertTrue(p2.isPending, @"");
    XCTAssertTrue(p3.isPending, @"");
    XCTAssertTrue(p4.isPending, @"");
    
    // wait until p4 has been resolved:
    id result = p4.get;
    XCTAssertTrue([result isEqualToString:@"OK"], @"");  // note: @"OK" is the default value for success.
    XCTAssertFalse(p4.isPending, @"");
    XCTAssertTrue(p4.isFulfilled, @"");
    XCTAssertFalse(p4.isCancelled, @"");
    XCTAssertFalse(p4.isRejected, @"");
    XCTAssertTrue([s isEqualToString:@"ABCD"], @"");
}


-(void) testChainingStatesWithP0Fails {
    
    // Test if promises do have the correct state when they enter the handler,
    // if this is the expected handler and if they forward the error correctly:
    
    // Keep all references to the promises.
    NSMutableString* e = [[NSMutableString alloc] init];
    RXPromise* p0, *p1, *p2, *p3, *p4;
    p0 = mock::async_fail(0.2, @"A:ERROR");
    
    p1 = p0.then(^id(id){
        XCTFail(@"p1 success handler called");
        return mock::async(0.01);
    },^id(NSError* error){
        // Note: accessing p1 in this handler is not correct, since the
        // handler will determince how the returned promise will be resolved!
        XCTAssertTrue([error isKindOfClass:[NSError class]], @"");
        XCTAssertTrue([error.userInfo[NSLocalizedFailureReasonErrorKey] isEqualToString:@"A:ERROR"], @"");
        XCTAssertFalse(p0.isPending, @"");
        XCTAssertFalse(p0.isFulfilled, @"");
        XCTAssertFalse(p0.isCancelled, @"");
        XCTAssertTrue(p0.isRejected, @"");
        [e appendString:@"a"];
        return error;
    });
    p2 = p1.then(^id(id){
        XCTFail(@"p1 success handler called");
        return mock::async(0.01);
    },^id(NSError* error){
        XCTAssertTrue([error isKindOfClass:[NSError class]], @"");
        XCTAssertTrue([error.userInfo[NSLocalizedFailureReasonErrorKey] isEqualToString:@"A:ERROR"], @"");
        XCTAssertFalse(p1.isPending, @"");
        XCTAssertFalse(p1.isFulfilled, @"");
        XCTAssertFalse(p1.isCancelled, @"");
        XCTAssertTrue(p1.isRejected, @"");
        
        XCTAssertFalse(p0.isPending, @"");
        XCTAssertFalse(p0.isFulfilled, @"");
        XCTAssertFalse(p0.isCancelled, @"");
        XCTAssertTrue(p0.isRejected, @"");
        [e appendString:@"b"];
        return error;
    });
    p3 = p2.then(^id(id){
        XCTFail(@"p1 success handler called");
        return mock::async(0.01);
    },^id(NSError* error){
        XCTAssertTrue([error isKindOfClass:[NSError class]], @"");
        XCTAssertTrue([error.userInfo[NSLocalizedFailureReasonErrorKey] isEqualToString:@"A:ERROR"], @"");
        XCTAssertFalse(p2.isPending, @"");
        XCTAssertFalse(p2.isFulfilled, @"");
        XCTAssertFalse(p2.isCancelled, @"");
        XCTAssertTrue(p2.isRejected, @"");
        XCTAssertFalse(p1.isPending, @"");
        XCTAssertFalse(p1.isFulfilled, @"");
        XCTAssertFalse(p1.isCancelled, @"");
        XCTAssertTrue(p1.isRejected, @"");
        XCTAssertFalse(p0.isPending, @"");
        XCTAssertFalse(p0.isFulfilled, @"");
        XCTAssertFalse(p0.isCancelled, @"");
        XCTAssertTrue(p0.isRejected, @"");
        [e appendString:@"c"];
        return error;
    });
    p4 = p3.then(^id(id){
        XCTFail(@"p1 success handler called");
        return mock::async(0.01);
    },^id(NSError* error){
        XCTAssertTrue([error isKindOfClass:[NSError class]], @"");
        XCTAssertTrue([error.userInfo[NSLocalizedFailureReasonErrorKey] isEqualToString:@"A:ERROR"], @"");
        XCTAssertFalse(p3.isPending, @"");
        XCTAssertFalse(p3.isFulfilled, @"");
        XCTAssertFalse(p3.isCancelled, @"");
        XCTAssertTrue(p3.isRejected, @"");
        XCTAssertFalse(p2.isPending, @"");
        XCTAssertFalse(p2.isFulfilled, @"");
        XCTAssertFalse(p2.isCancelled, @"");
        XCTAssertTrue(p2.isRejected, @"");
        XCTAssertFalse(p1.isPending, @"");
        XCTAssertFalse(p1.isFulfilled, @"");
        XCTAssertFalse(p1.isCancelled, @"");
        XCTAssertTrue(p1.isRejected, @"");
        XCTAssertFalse(p0.isPending, @"");
        XCTAssertFalse(p0.isFulfilled, @"");
        XCTAssertFalse(p0.isCancelled, @"");
        XCTAssertTrue(p0.isRejected, @"");
        [e appendString:@"d"];
        return error;
    });
    
    // p0 will resolve after 0.2 seconds, so hurry to check all promises:
    XCTAssertTrue(p0.isPending, @"");
    XCTAssertTrue(p1.isPending, @"");
    XCTAssertTrue(p2.isPending, @"");
    XCTAssertTrue(p3.isPending, @"");
    XCTAssertTrue(p4.isPending, @"");
    
    // p4 will be resolved shortly after, as the error gets forwarded quickly:
    id result = p4.get;
    XCTAssertTrue([result isKindOfClass:[NSError class]], @"");
    XCTAssertTrue([[result userInfo][NSLocalizedFailureReasonErrorKey] isEqualToString:@"A:ERROR"], @"");
    XCTAssertFalse(p4.isPending, @"");
    XCTAssertFalse(p4.isFulfilled, @"");
    XCTAssertFalse(p4.isCancelled, @"");
    XCTAssertTrue(p4.isRejected, @"");
    XCTAssertTrue([e isEqualToString:@"abcd"], @"");
}


-(void) testChainingStatesWithP1Fails {
    
    // Test if promises do have the correct state when they enter the handler,
    // if this is the expected handler and if they forward the error correctly:
    
    // Keep all references to the promises.
    
    NSMutableString* s = [[NSMutableString alloc] init];
    NSMutableString* e = [[NSMutableString alloc] init];
    
    
    RXPromise* p0, *p1, *p2, *p3, *p4;
    p0 = mock::async(0.1);
    
    p1 = p0.then(^id(id){
        XCTAssertFalse(p0.isPending, @"");
        XCTAssertTrue(p0.isFulfilled, @"");
        XCTAssertFalse(p0.isCancelled, @"");
        XCTAssertFalse(p0.isRejected, @"");
        [s appendString:@"A"];
        return mock::async_fail(0.01, @"B:ERROR");;
        
    },^id(NSError* error){
        XCTFail(@"p1 success handler called");
        return error;
    });
    p2 = p1.then(^id(id){
        XCTFail(@"p1 success handler called");
        return mock::async(0.01);
    },^id(NSError* error){
        XCTAssertTrue([error isKindOfClass:[NSError class]], @"");
        XCTAssertTrue([error.userInfo[NSLocalizedFailureReasonErrorKey] isEqualToString:@"B:ERROR"], @"");
        XCTAssertFalse(p1.isPending, @"");
        XCTAssertFalse(p1.isFulfilled, @"");
        XCTAssertFalse(p1.isCancelled, @"");
        XCTAssertTrue(p1.isRejected, @"");
        
        XCTAssertFalse(p0.isPending, @"");
        XCTAssertTrue(p0.isFulfilled, @"");
        XCTAssertFalse(p0.isCancelled, @"");
        XCTAssertFalse(p0.isRejected, @"");
        [e appendString:@"b"];
        return error;
    });
    p3 = p2.then(^id(id){
        XCTFail(@"p1 success handler called");
        return mock::async(0.01);
    },^id(NSError* error){
        XCTAssertTrue([error isKindOfClass:[NSError class]], @"");
        XCTAssertTrue([error.userInfo[NSLocalizedFailureReasonErrorKey] isEqualToString:@"B:ERROR"], @"");
        XCTAssertFalse(p2.isPending, @"");
        XCTAssertFalse(p2.isFulfilled, @"");
        XCTAssertFalse(p2.isCancelled, @"");
        XCTAssertTrue(p2.isRejected, @"");
        XCTAssertFalse(p1.isPending, @"");
        XCTAssertFalse(p1.isFulfilled, @"");
        XCTAssertFalse(p1.isCancelled, @"");
        XCTAssertTrue(p1.isRejected, @"");
        XCTAssertFalse(p0.isPending, @"");
        XCTAssertTrue(p0.isFulfilled, @"");
        XCTAssertFalse(p0.isCancelled, @"");
        XCTAssertFalse(p0.isRejected, @"");
        [e appendString:@"c"];
        return error;
    });
    p4 = p3.then(^id(id){
        XCTFail(@"p1 success handler called");
        return mock::async(0.01);
    },^id(NSError* error){
        XCTAssertTrue([error isKindOfClass:[NSError class]], @"");
        XCTAssertTrue([error.userInfo[NSLocalizedFailureReasonErrorKey] isEqualToString:@"B:ERROR"], @"");
        XCTAssertFalse(p3.isPending, @"");
        XCTAssertFalse(p3.isFulfilled, @"");
        XCTAssertFalse(p3.isCancelled, @"");
        XCTAssertTrue(p3.isRejected, @"");
        XCTAssertFalse(p2.isPending, @"");
        XCTAssertFalse(p2.isFulfilled, @"");
        XCTAssertFalse(p2.isCancelled, @"");
        XCTAssertTrue(p2.isRejected, @"");
        XCTAssertFalse(p1.isPending, @"");
        XCTAssertFalse(p1.isFulfilled, @"");
        XCTAssertFalse(p1.isCancelled, @"");
        XCTAssertTrue(p1.isRejected, @"");
        XCTAssertFalse(p0.isPending, @"");
        XCTAssertTrue(p0.isFulfilled, @"");
        XCTAssertFalse(p0.isCancelled, @"");
        XCTAssertFalse(p0.isRejected, @"");
        [e appendString:@"d"];
        return error;
    });
    
    // p0 will resolve after 0.2 seconds, so hurry to check all promises:
    XCTAssertTrue(p0.isPending, @"");
    XCTAssertTrue(p1.isPending, @"");
    XCTAssertTrue(p2.isPending, @"");
    XCTAssertTrue(p3.isPending, @"");
    XCTAssertTrue(p4.isPending, @"");
    
    // p4 will be resolved shortly after, as the error gets forwarded quickly:
    id result = p4.get;
    XCTAssertTrue([result isKindOfClass:[NSError class]], @"");
    XCTAssertTrue([[result userInfo][NSLocalizedFailureReasonErrorKey] isEqualToString:@"B:ERROR"], @"");
    XCTAssertFalse(p4.isPending, @"");
    XCTAssertFalse(p4.isFulfilled, @"");
    XCTAssertFalse(p4.isCancelled, @"");
    XCTAssertTrue(p4.isRejected, @"");
    XCTAssertTrue([s isEqualToString:@"A"], @"");
    XCTAssertTrue([e isEqualToString:@"bcd"], @"");
}



#pragma mark -

-(void) testSpawnParallelOPs
{
    // An async operation is started which returns a promise p0.
    // Upon success it spwans 4 parallel operations, which return
    // primise p00, p01, p02 and p03. Each async operation is expected to
    // succeed.
    
    
    char buffer[4];
    char* bp = buffer;
    
    memset(buffer, 0, sizeof(buffer));
    
    RXPromise* p0, *p00, *p01, *p02, *p03;
    
    // RXPromise* pAll = [RXPromise promiseAll: p00, p01, p02, p03];
    
    
    p0 = mock::async(0.01, @"0:success");
    
    p00 = p0.then(^id(id result){
        XCTAssertTrue([result isEqualToString:@"0:success"], @"");
        XCTAssertFalse(p0.isPending, @"");
        XCTAssertTrue(p0.isFulfilled, @"");
        XCTAssertFalse(p0.isCancelled, @"");
        XCTAssertFalse(p0.isRejected, @"");
        *bp  = 'A';
        return mock::async(0.01, @"00:success");
    }, nil);
    
    p01 = p0.then(^id(id result){
        XCTAssertTrue([result isEqualToString:@"0:success"], @"");
        XCTAssertFalse(p0.isPending, @"");
        XCTAssertTrue(p0.isFulfilled, @"");
        XCTAssertFalse(p0.isCancelled, @"");
        XCTAssertFalse(p0.isRejected, @"");
        *(bp+1)='B';
        return mock::async(0.01, @"01:success");
    }, nil);
    
    p02 = p0.then(^id(id result){
        XCTAssertTrue([result isEqualToString:@"0:success"], @"");
        XCTAssertFalse(p0.isPending, @"");
        XCTAssertTrue(p0.isFulfilled, @"");
        XCTAssertFalse(p0.isCancelled, @"");
        XCTAssertFalse(p0.isRejected, @"");
        *(bp+2)='C';
        return mock::async(0.01, @"02:success");
    }, nil);
    
    p03 = p0.then(^id(id result){
        XCTAssertTrue([result isEqualToString:@"0:success"], @"");
        XCTAssertFalse(p0.isPending, @"");
        XCTAssertTrue(p0.isFulfilled, @"");
        XCTAssertFalse(p0.isCancelled, @"");
        XCTAssertFalse(p0.isRejected, @"");
        *(bp+3)='D';
        return mock::async(0.01, @"03:success");
    }, ^(NSError* error){
        return error;
    });
    
    p00.then(^id(id result){
        XCTAssertTrue([result isEqualToString:@"00:success"], @"");
        return nil;
    }, ^id(NSError* error){
        XCTFail(@"p00 error handler called");
        return nil;
    });
    
    p01.then(^id(id result){
        XCTAssertTrue([result isEqualToString:@"01:success"], @"");
        return nil;
    }, ^id(NSError* error){
        XCTFail(@"p01 error handler called");
        return nil;
    });
    
    p02.then(^id(id result){
        XCTAssertTrue([result isEqualToString:@"02:success"], @"");
        return nil;
    }, ^id(NSError* error){
        XCTFail(@"p02 error handler called");
        return nil;
    });
    
    p03.then(^id(id result){
        XCTAssertTrue([result isEqualToString:@"03:success"], @"");
        return nil;
    }, ^id(NSError* error){
        XCTFail(@"p03 error handler called");
        return nil;
    });
    
    [p00 wait], [p01 wait], [p02 wait], [p03 wait];
    
    XCTAssertFalse(p00.isPending, @"");
    XCTAssertTrue(p00.isFulfilled, @"");
    XCTAssertFalse(p00.isCancelled, @"");
    XCTAssertFalse(p00.isRejected, @"");
    XCTAssertTrue([p00.get isEqualToString:@"00:success"], @"");
    
    XCTAssertFalse(p01.isPending, @"");
    XCTAssertTrue(p01.isFulfilled, @"");
    XCTAssertFalse(p01.isCancelled, @"");
    XCTAssertFalse(p01.isRejected, @"");
    XCTAssertTrue([p01.get isEqualToString:@"01:success"], @"");
    
    XCTAssertFalse(p02.isPending, @"");
    XCTAssertTrue(p02.isFulfilled, @"");
    XCTAssertFalse(p02.isCancelled, @"");
    XCTAssertFalse(p02.isRejected, @"");
    XCTAssertTrue([p02.get isEqualToString:@"02:success"], @"");
    
    XCTAssertFalse(p03.isPending, @"");
    XCTAssertTrue(p03.isFulfilled, @"");
    XCTAssertFalse(p03.isCancelled, @"");
    XCTAssertFalse(p03.isRejected, @"");
    XCTAssertTrue([p03.get isEqualToString:@"03:success"], @"");
    
    XCTAssertTrue( (memcmp("ABCD", buffer, sizeof(buffer)) == 0), @"" );
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
            XCTAssertTrue(sr == "", @"");
            sr.append("A");
            return asyncOp(@"B", 1, queue, 0.01);
        }, nil)
        .then(^id(id){
               XCTAssertTrue(sr == "A", @"");
               sr.append("B");
               return asyncOp(@"C", 3, queue, 0.01, 2, @"Failure at step 2");
           }, nil)
        .then(^id(id){
              XCTAssertTrue(sr == "AB", @"");
              sr.append("C");
              return asyncOp(@"D", 1, queue, 0.01);
          }, nil)
        .then(^id(id){
             XCTAssertTrue(sr == "ABC", @"");
             sr.append("D");
             semRef.signal(); return nil;
         }, nil);
        
        // We expect the finished_sem to timeout:
        XCTAssertFalse(finished_sem.wait(0.5), @"success callback called after 0.5 second");
        XCTAssertTrue(s == "AB", @"");
        
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
            XCTAssertTrue([s isEqualToString:@""], @"");
            [s appendString:@"A"];
            return asyncOp(@"B", 1, queue, 0.01);
        }, ^id(NSError *error) {
            [e appendString:@"a"];
            semRef.signal();
            return error;
        })
        .then(^id(id){
            XCTAssertTrue([s isEqualToString:@"A"], @"");
            [s appendString:@"B"];
            return asyncOp(@"C", 3, queue, 0.01, 2, @"Failure at step 2");
        },^id(NSError *error) {
            [e appendString:@"b"];
            semRef.signal();
            return error;
        })
        .then(^id(id){
          XCTAssertTrue([s isEqualToString:@"AB"], @"");
          [s appendString:@"C"];
          return asyncOp(@"D", 1, queue, 0.01);
        }, ^id(NSError *error) {
            [e appendString:@"c"];
            semRef.signal();
            return error;
        })
        .then(^id(id){
            XCTAssertTrue([s isEqualToString:@"ABC"], @"");
            [s appendString:@"D"];
            semRef.signal(); return nil;
        }, ^id(NSError *error) {
            [e appendString:@"d"];
            semRef.signal();
            return error;
        });
        
        XCTAssertTrue(finished_sem.wait(1000), @"any callback not called after 0.5 second");
        for (int i = 0; i < 10; ++i) {
            usleep(100);
        }
        XCTAssertTrue([@"AB" isEqualToString:s], @"");
        XCTAssertTrue([@"cd" isEqualToString:e], @"");
        
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
        
        RXPromise* promise0 = mock::async(0.01); // op0
        
        RXPromise* promise00 = promise0.then(^id(id result) {
            sr0.append("S0->"); sr1.append("____");
            return mock::async(0.04); // op00
        }, ^id(NSError *error) {
            esr.append("E0->"); return error;
        });
        RXPromise* promise000 = promise00.then(^id(id result) {
            sr0.append("S00->"); sr1.append("_____");
            return mock::async(0.02); // op000;
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
            return mock::async(0.02); // op01
        }, ^id(NSError *error) {
            esr.append("E1"); return error;
        });
        RXPromise* promise010 = promise01.then(^id(id result) {
            sr1.append("S10->");  sr0.append("_____");
            return mock::async(0.06); // op010;
        }, ^id(NSError *error) {
            esr.append("E10"); return error;
        });
        promise010.then(^id(id result) {
            sr1.append("S100."); sr0.append("_____");
            return nil;
        }, ^id(NSError *error) {
            esr.append("E100"); return error;
        });
        
        XCTAssertFalse(finished_sem.wait(0.5), @"expected to timeout after 0.5 s");
        XCTAssertTrue(es == "", @"");
    }
}


#pragma mark - Cancellation

-(void)testChainCancel1 {
    
    // Given a chain of four tasks, cancel the root promise when it is still
    // pending.
    // As a result, the pending children promises shall be cancelled with the
    // error returned from the root promise.
    
    // Keep all references to the promises.
    // Test if promises do have the correct state when they
    // enter the handler.
    
    
    RXPromise* p0, *p1, *p2, *p3, *p4;
    
    p0 = mock::async(1000);  // takes a while to finish
    
    NSMutableString* e = [[NSMutableString alloc] init];
    
    p1 = p0.then(^(id){
        XCTFail(@"p1 success handler called");
        return mock::async(0.01);
    },^id(NSError* error){
        XCTAssertFalse(p0.isPending, @"");
        XCTAssertFalse(p0.isFulfilled, @"");
        XCTAssertTrue(p0.isCancelled, @"");
        XCTAssertTrue(p0.isRejected, @"");
        [e appendString:@"1"];
        return error;
    });
    p2 = p1.then(^(id){
        XCTFail(@"p2 success handler called");
        return mock::async(0.01);
    },^id(NSError* error){
        XCTAssertFalse(p1.isPending, @"");
        XCTAssertFalse(p1.isFulfilled, @"");
        XCTAssertTrue(p1.isCancelled, @"");
        XCTAssertTrue(p1.isRejected, @"");
        [e appendString:@"2"];
        return error;
    });
    p3 = p2.then(^(id){
        XCTFail(@"p3 success handler called");
        return mock::async(0.01);
    },^id(NSError* error){
        XCTAssertFalse(p1.isPending, @"");
        XCTAssertFalse(p1.isFulfilled, @"");
        XCTAssertTrue(p1.isCancelled, @"");
        XCTAssertTrue(p1.isRejected, @"");
        [e appendString:@"3"];
        return error;
    });
    p4 = p3.then(^(id){
        XCTFail(@"p4 success handler called");
        return mock::async(0.01);
    },^id(NSError* error){
        XCTAssertFalse(p1.isPending, @"");
        XCTAssertFalse(p1.isFulfilled, @"");
        XCTAssertTrue(p1.isCancelled, @"");
        XCTAssertTrue(p1.isRejected, @"");
        [e appendString:@"4"];
        return error;
    });
    
    double delayInSeconds = 0.1;
    dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayInSeconds * NSEC_PER_SEC));
    dispatch_after(popTime, dispatch_get_global_queue(0, 0), ^(void){
        [p0 cancel];
    });
    
    // p0 will resolve with a cancel after 0.2 seconds, so hurry to check all promises:
    XCTAssertTrue(p0.isPending, @"");
    XCTAssertTrue(p1.isPending, @"");
    XCTAssertTrue(p2.isPending, @"");
    XCTAssertTrue(p3.isPending, @"");
    XCTAssertTrue(p4.isPending, @"");
    
    // wait until p4 has been resolved:
    id result = p4.get;
    XCTAssertTrue([e isEqualToString:@"1234"], @"%@", e);
    
    XCTAssertTrue([result isKindOfClass:[NSError class]], @"");
    XCTAssertFalse(p4.isPending, @"");
    XCTAssertFalse(p4.isFulfilled, @"");
    XCTAssertTrue(p4.isCancelled, @""); // p4 MUST be "cancelled"
    XCTAssertTrue(p4.isRejected, @"");
    
    result = p3.get;
    XCTAssertTrue([result isKindOfClass:[NSError class]], @"");
    XCTAssertFalse(p3.isPending, @"");
    XCTAssertFalse(p3.isFulfilled, @"");
    XCTAssertTrue(p3.isCancelled, @"");  // p3 MUST be "cancelled"
    XCTAssertTrue(p3.isRejected, @"");
    
    result = p2.get;
    XCTAssertTrue([result isKindOfClass:[NSError class]], @"");
    XCTAssertFalse(p2.isPending, @"");
    XCTAssertFalse(p2.isFulfilled, @"");
    XCTAssertTrue(p2.isCancelled, @"");  // p2 MUST be "cancelled"
    XCTAssertTrue(p2.isRejected, @"");
    
    result = p1.get;
    XCTAssertTrue([result isKindOfClass:[NSError class]], @"");
    XCTAssertFalse(p1.isPending, @"");
    XCTAssertFalse(p1.isFulfilled, @"");
    XCTAssertTrue(p1.isCancelled, @"");  // p1 MUST be "cancelled"
    XCTAssertTrue(p1.isRejected, @"");
    
    result = p0.get;
    XCTAssertTrue([result isKindOfClass:[NSError class]], @"");
    XCTAssertFalse(p0.isPending, @"");
    XCTAssertFalse(p0.isFulfilled, @"");
    XCTAssertTrue(p0.isCancelled, @"");  // p0 MUST be cancelled.
    XCTAssertTrue(p0.isRejected, @"");
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
    
    p0 = mock::async_bind(1000);  // takes a while to finish
    
    NSMutableString* e = [[NSMutableString alloc] init];
    
    p1 = p0.then(^(id){
        XCTFail(@"p1 success handler called");
        return mock::async_bind(0.01);
    },^id(NSError* error){
        XCTAssertFalse(p0.isPending, @"");
        XCTAssertFalse(p0.isFulfilled, @"");
        XCTAssertTrue(p0.isCancelled, @"");
        XCTAssertTrue(p0.isRejected, @"");
        [e appendString:@"1"];
        return error;
    });
    p2 = p1.then(^(id){
        XCTFail(@"p2 success handler called");
        return mock::async_bind(0.01);
    },^id(NSError* error){
        XCTAssertFalse(p1.isPending, @"");
        XCTAssertFalse(p1.isFulfilled, @"");
        XCTAssertTrue(p1.isCancelled, @"");
        XCTAssertTrue(p1.isRejected, @"");
        [e appendString:@"2"];
        return error;
    });
    p3 = p2.then(^(id){
        XCTFail(@"p3 success handler called");
        return mock::async_bind(0.01);
    },^id(NSError* error){
        XCTAssertFalse(p1.isPending, @"");
        XCTAssertFalse(p1.isFulfilled, @"");
        XCTAssertTrue(p1.isCancelled, @"");
        XCTAssertTrue(p1.isRejected, @"");
        [e appendString:@"3"];
        return error;
    });
    p4 = p3.then(^(id){
        XCTFail(@"p4 success handler called");
        return mock::async_bind(0.01);
    },^id(NSError* error){
        XCTAssertFalse(p1.isPending, @"");
        XCTAssertFalse(p1.isFulfilled, @"");
        XCTAssertTrue(p1.isCancelled, @"");
        XCTAssertTrue(p1.isRejected, @"");
        [e appendString:@"4"];
        return error;
    });
    
    double delayInSeconds = 0.1;
    dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayInSeconds * NSEC_PER_SEC));
    dispatch_after(popTime, dispatch_get_global_queue(0, 0), ^(void){
        [p0 cancel];
    });
    
    // p0 will resolve with a cancel after 0.2 seconds, so hurry to check all promises:
    XCTAssertTrue(p0.isPending, @"");
    XCTAssertTrue(p1.isPending, @"");
    XCTAssertTrue(p2.isPending, @"");
    XCTAssertTrue(p3.isPending, @"");
    XCTAssertTrue(p4.isPending, @"");
    
    // wait until p4 has been resolved:
    id result = p4.get;
    XCTAssertTrue([e isEqualToString:@"1234"], @"%@", e);
    
    XCTAssertTrue([result isKindOfClass:[NSError class]], @"");
    XCTAssertFalse(p4.isPending, @"");
    XCTAssertFalse(p4.isFulfilled, @"");
    XCTAssertTrue(p4.isCancelled, @""); // p4 MUST be "cancelled"
    XCTAssertTrue(p4.isRejected, @"");
    
    result = p3.get;
    XCTAssertTrue([result isKindOfClass:[NSError class]], @"");
    XCTAssertFalse(p3.isPending, @"");
    XCTAssertFalse(p3.isFulfilled, @"");
    XCTAssertTrue(p3.isCancelled, @"");  // p3 MUST be "cancelled"
    XCTAssertTrue(p3.isRejected, @"");
    
    result = p2.get;
    XCTAssertTrue([result isKindOfClass:[NSError class]], @"");
    XCTAssertFalse(p2.isPending, @"");
    XCTAssertFalse(p2.isFulfilled, @"");
    XCTAssertTrue(p2.isCancelled, @"");  // p2 MUST be "cancelled"
    XCTAssertTrue(p2.isRejected, @"");
    
    result = p1.get;
    XCTAssertTrue([result isKindOfClass:[NSError class]], @"");
    XCTAssertFalse(p1.isPending, @"");
    XCTAssertFalse(p1.isFulfilled, @"");
    XCTAssertTrue(p1.isCancelled, @"");  // p1 MUST be "cancelled"
    XCTAssertTrue(p1.isRejected, @"");
    
    result = p0.get;
    XCTAssertTrue([result isKindOfClass:[NSError class]], @"");
    XCTAssertFalse(p0.isPending, @"");
    XCTAssertFalse(p0.isFulfilled, @"");
    XCTAssertTrue(p0.isCancelled, @"");  // p0 MUST be cancelled.
    XCTAssertTrue(p0.isRejected, @"");
}


-(void) testChainCancel2 {
    
    // Given a chain of four tasks, cancel the root promise when it is
    // fulfilled and all other taks are pending.
    
    // Keep all references to the promises.
    // Test if promises do have the correct state when they
    // enter the handler.
    
    
    RXPromise* p0, *p1, *p2, *p3, *p4;
    
    p0 = mock::async(0.01);  // will be finished quickly
    
    NSMutableString* e = [[NSMutableString alloc] init];
    NSMutableString* s = [[NSMutableString alloc] init];
    
    p1 = p0.then(^(id){
        XCTAssertFalse(p0.isPending, @"");
        XCTAssertTrue(p0.isFulfilled, @"");
        XCTAssertFalse(p0.isCancelled, @"");
        XCTAssertFalse(p0.isRejected, @"");
        [s appendString:@"1"];
        return mock::async(1000); // takes a while to finish
    },^id(NSError* error){
        XCTFail(@"p1 error handler called");
        return error;
    });
    p2 = p1.then(^(id){
        XCTFail(@"p2 success handler called");
        return mock::async(0.01);
    },^id(NSError* error){
        XCTAssertFalse(p1.isPending, @"");
        XCTAssertFalse(p1.isFulfilled, @"");
        XCTAssertTrue(p1.isCancelled, @"");
        XCTAssertTrue(p1.isRejected, @"");
        [e appendString:@"2"];
        return error;
    });
    p3 = p2.then(^(id){
        XCTFail(@"p3 success handler called");
        return mock::async(0.01);
    },^id(NSError* error){
        XCTAssertFalse(p1.isPending, @"");
        XCTAssertFalse(p1.isFulfilled, @"");
        XCTAssertTrue(p1.isCancelled, @"");
        XCTAssertTrue(p1.isRejected, @"");
        [e appendString:@"3"];
        return error;
    });
    p4 = p3.then(^(id){
        XCTFail(@"p4 success handler called");
        return mock::async(0.01);
    },^id(NSError* error){
        XCTAssertFalse(p1.isPending, @"");
        XCTAssertFalse(p1.isFulfilled, @"");
        XCTAssertTrue(p1.isCancelled, @"");
        XCTAssertTrue(p1.isRejected, @"");
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
    XCTAssertTrue([s isEqualToString:@"1"], @"%@", s);
    XCTAssertTrue([e isEqualToString:@"234"], @"%@", e);
    
    XCTAssertTrue([result isKindOfClass:[NSError class]], @"");
    XCTAssertFalse(p4.isPending, @"");
    XCTAssertFalse(p4.isFulfilled, @"");
    XCTAssertTrue(p4.isCancelled, @"p4 MUST be cancelled");
    XCTAssertTrue(p4.isRejected, @"");
    
    result = p3.get;
    XCTAssertTrue([result isKindOfClass:[NSError class]], @"");
    XCTAssertFalse(p3.isPending, @"");
    XCTAssertFalse(p3.isFulfilled, @"");
    XCTAssertTrue(p3.isCancelled, @"p3 MUST be cancelled");
    XCTAssertTrue(p3.isRejected, @"");
    
    result = p2.get;
    XCTAssertTrue([result isKindOfClass:[NSError class]], @"");
    XCTAssertFalse(p2.isPending, @"");
    XCTAssertFalse(p2.isFulfilled, @"");
    XCTAssertTrue(p2.isCancelled, @"");  // p2 MUST be "cancelled"
    XCTAssertTrue(p2.isRejected, @"");
    
    result = p1.get;
    XCTAssertTrue([result isKindOfClass:[NSError class]], @"");
    XCTAssertFalse(p1.isPending, @"");
    XCTAssertFalse(p1.isFulfilled, @"");
    XCTAssertTrue(p1.isCancelled, @"");  // p1 MUST be "cancelled"
    XCTAssertTrue(p1.isRejected, @"");
    
    result = p0.get;
    XCTAssertFalse([result isKindOfClass:[NSError class]], @"");
    XCTAssertFalse(p0.isPending, @"");
    XCTAssertTrue(p0.isFulfilled, @"");   // P0 MUST not be cancelled
    XCTAssertFalse(p0.isCancelled, @"");  // p0 MUST be fulfilled.
    XCTAssertFalse(p0.isRejected, @"");
}


-(void) testChainCancel2WithBoundPromise {
    
    // Given a chain of four tasks, cancel the root promise when it is
    // fulfilled and all other taks are pending.
    
    // Keep all references to the promises.
    // Test if promises do have the correct state when they
    // enter the handler.
    
    
    RXPromise* p0, *p1, *p2, *p3, *p4;
    
    p0 = mock::async_bind(0.01);  // will be finished quickly
    
    NSMutableString* e = [[NSMutableString alloc] init];
    NSMutableString* s = [[NSMutableString alloc] init];
    
    p1 = p0.then(^(id){
        XCTAssertFalse(p0.isPending, @"");
        XCTAssertTrue(p0.isFulfilled, @"");
        XCTAssertFalse(p0.isCancelled, @"");
        XCTAssertFalse(p0.isRejected, @"");
        [s appendString:@"1"];
        return mock::async_bind(1000); // takes a while to finish
    },^id(NSError* error){
        XCTFail(@"p1 error handler called");
        return error;
    });
    p2 = p1.then(^(id){
        XCTFail(@"p2 success handler called");
        return mock::async_bind(0.01);
    },^id(NSError* error){
        XCTAssertFalse(p1.isPending, @"");
        XCTAssertFalse(p1.isFulfilled, @"");
        XCTAssertTrue(p1.isCancelled, @"");
        XCTAssertTrue(p1.isRejected, @"");
        [e appendString:@"2"];
        return error;
    });
    p3 = p2.then(^(id){
        XCTFail(@"p3 success handler called");
        return mock::async_bind(0.01);
    },^id(NSError* error){
        XCTAssertFalse(p1.isPending, @"");
        XCTAssertFalse(p1.isFulfilled, @"");
        XCTAssertTrue(p1.isCancelled, @"");
        XCTAssertTrue(p1.isRejected, @"");
        [e appendString:@"3"];
        return error;
    });
    p4 = p3.then(^(id){
        XCTFail(@"p4 success handler called");
        return mock::async_bind(0.01);
    },^id(NSError* error){
        XCTAssertFalse(p1.isPending, @"");
        XCTAssertFalse(p1.isFulfilled, @"");
        XCTAssertTrue(p1.isCancelled, @"");
        XCTAssertTrue(p1.isRejected, @"");
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
    XCTAssertTrue([s isEqualToString:@"1"], @"%@", s);
    XCTAssertTrue([e isEqualToString:@"234"], @"%@", e);
    
    XCTAssertTrue([result isKindOfClass:[NSError class]], @"");
    XCTAssertFalse(p4.isPending, @"");
    XCTAssertFalse(p4.isFulfilled, @"");
    XCTAssertTrue(p4.isCancelled, @"p4 MUST be cancelled");
    XCTAssertTrue(p4.isRejected, @"");
    
    result = p3.get;
    XCTAssertTrue([result isKindOfClass:[NSError class]], @"");
    XCTAssertFalse(p3.isPending, @"");
    XCTAssertFalse(p3.isFulfilled, @"");
    XCTAssertTrue(p3.isCancelled, @"p3 MUST be cancelled");
    XCTAssertTrue(p3.isRejected, @"");
    
    result = p2.get;
    XCTAssertTrue([result isKindOfClass:[NSError class]], @"");
    XCTAssertFalse(p2.isPending, @"");
    XCTAssertFalse(p2.isFulfilled, @"");
    XCTAssertTrue(p2.isCancelled, @"");  // p2 MUST be "cancelled"
    XCTAssertTrue(p2.isRejected, @"");
    
    result = p1.get;
    XCTAssertTrue([result isKindOfClass:[NSError class]], @"");
    XCTAssertFalse(p1.isPending, @"");
    XCTAssertFalse(p1.isFulfilled, @"");
    XCTAssertTrue(p1.isCancelled, @"");  // p1 MUST be "cancelled"
    XCTAssertTrue(p1.isRejected, @"");
    
    result = p0.get;
    XCTAssertFalse([result isKindOfClass:[NSError class]], @"");
    XCTAssertFalse(p0.isPending, @"");
    XCTAssertTrue(p0.isFulfilled, @"");   // P0 MUST not be cancelled
    XCTAssertFalse(p0.isCancelled, @"");  // p0 MUST be fulfilled.
    XCTAssertFalse(p0.isRejected, @"");
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
        
        RXPromise* p0 = mock::async(1000); // op0
        
        RXPromise* p00 = p0.then(^id(id result) {
            [s0 appendString:@"0F"];
            return mock::async(0.04);
        }, ^id(NSError *error) {
            [s0 appendString:@"0R"];
            if (p0.isCancelled) {
                [s0 appendString:@"C"];
            }
            return error;
        });
        RXPromise* p000 = p00.then(^id(id result) {
            [s0 appendString:@"00F"];
            return mock::async(0.02);
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
            return mock::async(0.04); // op00
        }, ^id(NSError *error) {
            [s1 appendString:@"0R"];
            if (p0.isCancelled) {
                [s1 appendString:@"C"];
            }
            return error;
        });
        RXPromise* p010 = p01.then(^id(id result) {
            [s1 appendString:@"01F"];
            return mock::async(0.02);
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
            return mock::async(0.04);
        }, ^id(NSError *error) {
            [s2 appendString:@"0R"];
            if (p0.isCancelled) {
                [s2 appendString:@"C"];
            }
            return error;
        });
        RXPromise* p020 = p02.then(^id(id result) {
            [s2 appendString:@"02F"];
            return mock::async(0.02);
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
        
        XCTAssertTrue([s0 isEqualToString:@"0RC00RC000RC"], @"%@", s0);
        XCTAssertTrue([s1 isEqualToString:@"0RC01RC010RC"], @"%@", s1);
        XCTAssertTrue([s2 isEqualToString:@"0RC02RC020RC"], @"%@", s2);
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
        
        RXPromise* p0 = mock::async_bind(1000); // op0
        
        RXPromise* p00 = p0.then(^id(id result) {
            [s0 appendString:@"0F"];
            return mock::async_bind(0.04);
        }, ^id(NSError *error) {
            [s0 appendString:@"0R"];
            if (p0.isCancelled) {
                [s0 appendString:@"C"];
            }
            return error;
        });
        RXPromise* p000 = p00.then(^id(id result) {
            [s0 appendString:@"00F"];
            return mock::async_bind(0.02);
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
            return mock::async_bind(0.04); // op00
        }, ^id(NSError *error) {
            [s1 appendString:@"0R"];
            if (p0.isCancelled) {
                [s1 appendString:@"C"];
            }
            return error;
        });
        RXPromise* p010 = p01.then(^id(id result) {
            [s1 appendString:@"01F"];
            return mock::async_bind(0.02);
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
            return mock::async_bind(0.04);
        }, ^id(NSError *error) {
            [s2 appendString:@"0R"];
            if (p0.isCancelled) {
                [s2 appendString:@"C"];
            }
            return error;
        });
        RXPromise* p020 = p02.then(^id(id result) {
            [s2 appendString:@"02F"];
            return mock::async_bind(0.02);
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
        
        XCTAssertTrue([s0 isEqualToString:@"0RC00RC000RC"], @"%@", s0);
        XCTAssertTrue([s1 isEqualToString:@"0RC01RC010RC"], @"%@", s1);
        XCTAssertTrue([s2 isEqualToString:@"0RC02RC020RC"], @"%@", s2);
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
        
        RXPromise* p0 = mock::async(0.01); // op0
        
        RXPromise* p00 = p0.then(^id(id result) {
            [s0 appendString:@"0F"];
            return mock::async(10);
        }, ^id(NSError *error) {
            [s0 appendString:@"0R"];
            if (p0.isCancelled) {
                [s0 appendString:@"C"];
            }
            return error;
        });
        RXPromise* p000 = p00.then(^id(id result) {
            [s0 appendString:@"00F"];
            return mock::async(10);
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
            return mock::async(10); // op00
        }, ^id(NSError *error) {
            [s1 appendString:@"0R"];
            if (p0.isCancelled) {
                [s1 appendString:@"C"];
            }
            return error;
        });
        RXPromise* p010 = p01.then(^id(id result) {
            [s1 appendString:@"01F"];
            return mock::async(10);
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
            return mock::async(10);
        }, ^id(NSError *error) {
            [s2 appendString:@"0R"];
            if (p0.isCancelled) {
                [s2 appendString:@"C"];
            }
            return error;
        });
        RXPromise* p020 = p02.then(^id(id result) {
            [s2 appendString:@"02F"];
            return mock::async(10);
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
        
        XCTAssertTrue([s0 isEqualToString:@"0F00RC000RC"], @"%@", s0);
        XCTAssertTrue([s1 isEqualToString:@"0F01RC010RC"], @"%@", s1);
        XCTAssertTrue([s2 isEqualToString:@"0F02RC020RC"], @"%@", s2);
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
        
        RXPromise* p0 = mock::async_bind(0.01); // op0
        
        RXPromise* p00 = p0.then(^id(id result) {
            [s0 appendString:@"0F"];
            return mock::async_bind(10);
        }, ^id(NSError *error) {
            [s0 appendString:@"0R"];
            if (p0.isCancelled) {
                [s0 appendString:@"C"];
            }
            return error;
        });
        RXPromise* p000 = p00.then(^id(id result) {
            [s0 appendString:@"00F"];
            return mock::async_bind(10);
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
            return mock::async_bind(10); // op00
        }, ^id(NSError *error) {
            [s1 appendString:@"0R"];
            if (p0.isCancelled) {
                [s1 appendString:@"C"];
            }
            return error;
        });
        RXPromise* p010 = p01.then(^id(id result) {
            [s1 appendString:@"01F"];
            return mock::async_bind(10);
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
            return mock::async_bind(10);
        }, ^id(NSError *error) {
            [s2 appendString:@"0R"];
            if (p0.isCancelled) {
                [s2 appendString:@"C"];
            }
            return error;
        });
        RXPromise* p020 = p02.then(^id(id result) {
            [s2 appendString:@"02F"];
            return mock::async_bind(10);
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
        
        XCTAssertTrue([s0 isEqualToString:@"0F00RC000RC"], @"%@", s0);
        XCTAssertTrue([s1 isEqualToString:@"0F01RC010RC"], @"%@", s1);
        XCTAssertTrue([s2 isEqualToString:@"0F02RC020RC"], @"%@", s2);
    }
}


#pragma mark - all

-(void) testAllFulfilled1
{
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    
    NSArray* expectedResults = @[ @"A", @"B", @"C", @"D", @"E", @"F", @"G", @"H"];
    
    // Run eight tasks in parallel:
    NSArray* promises = @[mock::async(0.05, @"A"),
                          mock::async(0.05, @"B"),
                          mock::async(0.05, @"C"),
                          mock::async(0.05, @"D"),
                          mock::async(0.05, @"E"),
                          mock::async(0.05, @"F"),
                          mock::async(0.05, @"G"),
                          mock::async(0.05, @"H")];
    

    RXPromise* all = [RXPromise all:promises].then(^id(id results){
        XCTAssertTrue([results isKindOfClass:[NSArray class]], @"");
        XCTAssertTrue(results != promises, @"");
        XCTAssertTrue([expectedResults isEqualToArray:results], @"");
        for (RXPromise* p in promises) {
            XCTAssertTrue(p.isFulfilled, @"");
        }
        dispatch_semaphore_signal(sem);
        return nil;
    },^id(NSError*error){
        XCTFail(@"must not be called");
        NSLog(@"ERROR: %@", error);
        return error;
    });
    
    XCTAssertTrue(0 == dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 1*NSEC_PER_SEC)), @"");
    [all wait];
}

-(void) testAllFulfilled2 {
    
    // Run eight tasks in parallel. For each task, on success execute success handler
    // on unspecified queue. Fill the results array with the return value of the handler
    // and wait until all handlers are finished.
    
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);

    // Note: we are accessing buffer from multiple threads without synchronization!
    char buffer[8] = {'X', 'X', 'X', 'X', 'X', 'X', 'X', 'X'};
    char* p = buffer;
    
    NSArray* expectedResults = @[ @"A", @"B", @"C", @"D", @"E", @"F", @"G", @"H"];
    
    // Note: The results array will contain the return value of the success handler
    NSArray* promises = @[
    mock::async(0.08, @"A").then(^id(id result){
        *p='A';
        return result;
    },nil),
    mock::async(0.07, @"B").then(^id(id result){
        *(p+1)='B';
        return result;
    },nil),
    mock::async(0.06, @"C").then(^id(id result){
        *(p+2)='C';
        return result;
    },nil),
    mock::async(0.05, @"D").then(^id(id result){
        *(p+3)='D';
        return result;
    },nil),
    mock::async(0.04, @"E").then(^id(id result){
        *(p+4)='E';
        return result;
    },nil),
    mock::async(0.03, @"F").then(^id(id result){
        *(p+5)='F';
        return result;
    },nil),
    mock::async(0.02, @"G").then(^id(id result){
        *(p+6)='G';
        return result;
    },nil),
    mock::async(0.01, @"H").then(^id(id result){
        *(p+7)='H';
        return result;
    },nil)];
    
    RXPromise* all = [RXPromise all:promises].then(^id(id results){
        // Note: when we reach here all handlers have been finished since we
        // filled the 'all' array with the promise of the handlers.
        XCTAssertTrue([results isKindOfClass:[NSArray class]], @"");
        XCTAssertTrue(results != promises, @"");
        XCTAssertTrue([expectedResults isEqualToArray:results], @"");
        // All tasks shall be completed at this time!
        for (RXPromise* p in promises) {
            XCTAssertTrue(p.isFulfilled, @"");
        }
        dispatch_semaphore_signal(sem);
        return nil;
    },^id(NSError*error){
        XCTFail(@"must not be called");
        NSLog(@"ERROR: %@", error);
        return error;
    });
    XCTAssertTrue(0 == dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 1*NSEC_PER_SEC)), @"");
    [all wait];
    // All tasks and all handlers shall be completed at this time.
    XCTAssertTrue( std::memcmp(buffer, "ABCDEFGH", sizeof(buffer)) == 0, @"");
}

-(void) testAllFulfilledWithQueue {
    
    // Run eight tasks in parallel. For each task, on success execute success handler
    // on specified serial queue `syncQueue`.
    // Fill an array with the returned promise from the tasks.
    
    // All tasks will finish almost simultaneously, thus "buffer" will likely
    // be accessed in random order and thus the characters written to it have
    // also the same order as the tasks finish.
    
    // Note: With the property's `thenOn` block is invoked, the handler is executed
    // on the specified queue. Since this queue is a serial queue, access to shared
    // resources occuring within the handler is serialized and thus thread safe.
    const char* QueueID = "test.queue_id";
    dispatch_queue_t syncQueue = dispatch_queue_create("test.sync_queue", NULL);
    dispatch_queue_set_specific(syncQueue, QueueID, (__bridge void*)syncQueue, NULL);

    // We fill the buffer in order as the tasks fininish!
    char buffer[8] = {'X'};
    __block char* p = buffer;
    
    NSArray* expectedResults = @[ @"A", @"B", @"C", @"D", @"E", @"F", @"G", @"H"];
    
    NSArray* promises = @[
    mock::async(0.2, @"A").thenOn(syncQueue, ^id(id result){
        void* q = dispatch_get_specific(QueueID);
        XCTAssertTrue((__bridge void*)syncQueue == q, @"not running on sync_queue");
        p[0]='A';
        return result;
    },nil),
    mock::async(0.01, @"B").thenOn(syncQueue, ^id(id result){
        p[1]='B';
        return result;
    },nil),
    mock::async(0.01, @"C").thenOn(syncQueue, ^id(id result){
        p[2]='C';
        return result;
    },nil),
    mock::async(0.01, @"D").thenOn(syncQueue, ^id(id result){
        p[3]='D';
        return result;
    },nil),
    mock::async(0.01, @"E").thenOn(syncQueue, ^id(id result){
        p[4]='E';
        return result;
    },nil),
    mock::async(0.01, @"F").thenOn(syncQueue, ^id(id result){
        p[5]='F';
        return result;
    },nil),
    mock::async(0.01, @"G").thenOn(syncQueue, ^id(id result){
        p[6]='G';
        return result;
    },nil),
    mock::async(0.01, @"H").thenOn(syncQueue, ^id(id result){
        p[7]='H';
        return result;
    },nil)
    ];
    
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    RXPromise* all = [RXPromise all:promises].thenOn(syncQueue, ^id(id results){
        for (RXPromise* p in promises) {
            XCTAssertTrue(p.isFulfilled, @"");
        }
        XCTAssertTrue([results isKindOfClass:[NSArray class]], @"");
        XCTAssertTrue(results != promises, @"");
        XCTAssertTrue([expectedResults isEqualToArray:results], @"");
        dispatch_semaphore_signal(sem);
        return nil;
    },^id(NSError*error){
        XCTFail(@"must not be called");
        NSLog(@"ERROR: %@", error);
        return error;
    });
    
    XCTAssertTrue(0 == dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 1*NSEC_PER_SEC)), @"");
    [all wait];
    std::sort(buffer, buffer+sizeof(buffer));
    XCTAssertTrue( std::memcmp(buffer, "ABCDEFGH", sizeof(buffer)) == 0, @"");
}

-(void) testAllOneRejected1
{
    // Since v0.11.0 if any task rejects its returned promise, all other promises
    // will be left untouched.
    
    // Run three tasks in parallel:
    NSArray* tasks = @[mock::async(0.1, @"A"),
                       mock::async_fail(0.2, @"B"),
                       mock::async(0.3, @"C")];
    
    [[RXPromise all:tasks]
    .then(^id(id result) {
        XCTFail(@"must not be called");
        return nil;
    },^id(NSError*error) {
        XCTAssertTrue([@"B" isEqualToString:error.userInfo[NSLocalizedFailureReasonErrorKey]], @"");
        
        XCTAssertTrue([tasks[0] isFulfilled], @"");
        XCTAssertTrue([tasks[1] isRejected], @"");
        [tasks[2] get];
        XCTAssertTrue([tasks[2] isFulfilled], @"");
        return error;
    }) wait];
}

-(void) testAllOneRejected2 {
    NSMutableString*  s0 = [[NSMutableString alloc] init];  // note: potentially race - if the promises do not share the same root promise
    
    NSArray* promises = @[mock::async(0.1, @"A")
                          .then(^id(id result){
                              [s0 appendString:result];
                              return result;
                          },nil),
                          mock::async_fail(0.2, @"B")
                          .then(^id(id result){
                              [s0 appendString:result];
                              return result;
                          },nil),
                          mock::async(0.3, @"C")
                          .then(^id(id result){
                              [s0 appendString:result];
                              return result;
                          },nil)];
    RXPromise* all = [RXPromise all:promises].then(^id(id result){
        XCTFail(@"must not be called");
        return nil;
    },^id(NSError*error){
        XCTAssertTrue([@"B" isEqualToString:error.userInfo[NSLocalizedFailureReasonErrorKey]], @"");
        XCTAssertTrue([s0 isEqualToString:@"A"], @"%@", s0);
        XCTAssertTrue([promises[0] isFulfilled], @"");
        XCTAssertTrue([promises[1] isRejected], @"");
        [promises[2] get];
        XCTAssertTrue([promises[2] isFulfilled], @"");
        return error;
    });
    
    [all wait];
    XCTAssertTrue([s0 isEqualToString:@"AC"], @"%@", s0);
}

-(void) testAllOneRejectedWithQueue {

    // Note: When `thenOn`'s block is invoked, the handler is invoked on the
    // specified queue.
    
    const char* QueueIDKey = "com.test.queue.id";
    static const char* concurrent_queue_id = "com.test.concurrent.queue";
    dispatch_queue_t concurrentQueue = dispatch_queue_create("com.test.concurrent.queue", DISPATCH_QUEUE_CONCURRENT);
    dispatch_queue_set_specific(concurrentQueue, QueueIDKey, (void*)concurrent_queue_id, NULL);
    
    
    // Run three tasks in parallel:
    NSArray* tasks = @[mock::async(0.1, @"A"), mock::async_fail(0.2, @"B"), mock::async(0.3, @"C")];
    
    [[RXPromise all:tasks].thenOn(concurrentQueue,
      ^id(id result) {
        XCTFail(@"must not be called");
        return nil;
    },^id(NSError*error) {
        XCTAssertTrue( dispatch_get_specific(QueueIDKey) == (void *)(concurrent_queue_id), @"");
        XCTAssertTrue([@"B" isEqualToString:error.userInfo[NSLocalizedFailureReasonErrorKey]], @"");
        
        XCTAssertTrue([tasks[0] isFulfilled], @"");
        XCTAssertTrue([tasks[1] isRejected], @"");
        [tasks[2] wait];
        XCTAssertTrue([tasks[2] isFulfilled], @"");
        return error;
    }) wait];
}

-(void) testAllCancellingReturnedPromisesMustNotCancelPromises {
    // Since v0.11.0, cancelling the returned promise of method `all:` must not
    // cancel the underlying promises given in the array
    
    NSMutableString*  s0 = [[NSMutableString alloc] init];  // note: potentially race - if the promises do not share the same root promise
    
    // Array containing the returned promises of the tasks (not the returned promises of their handlers, see `.parent`)
    
    NSArray* handlerPromises = @[mock::async(0.5, @"A")
                          .then(^id(id result) {
                              [s0 appendString:result];
                              return nil;
                          },nil),
                          mock::async_fail(100, @"B")
                          .then(^id(id result) {
                              [s0 appendString:result];
                              return nil;
                          },nil),
                          mock::async(1, @"C")
                          .then(^id(id result) {
                              [s0 appendString:result];
                              return nil;
                          },nil)];
    
    NSArray* taskPromises = @[[handlerPromises[0] parent], [handlerPromises[1] parent], [handlerPromises[2] parent]];
    RXPromise* all = [RXPromise all:taskPromises];
    
    [all setTimeout:0.2].then(^id(id result) {
        XCTFail(@"Cancelling returned promise must not cancel underlying promises");
        for (RXPromise* p in taskPromises) {
            [p cancel];
        }
        return nil;
    }, ^id(NSError* error) {
        XCTAssertTrue([taskPromises[0] isPending], @"");
        XCTAssertTrue([taskPromises[1] isPending], @"");
        XCTAssertTrue([taskPromises[2] isPending], @"");
        for (RXPromise* p in taskPromises) {
            [p cancel];
        }
        return nil;
    });
    [all cancel];
    
    [[RXPromise all:handlerPromises] wait];
}


-(void) testAllCancelWhenOnePromiseFailed {
    // Since v0.11.0, cancelling the returned promise of method `all:` must not
    // cancel the underlying promises given in the array

    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    const char* QueueID = "com.test.queue.id";
    dispatch_queue_t concurrentQueue = dispatch_queue_create("my.concurrent.queue", DISPATCH_QUEUE_CONCURRENT);
    dispatch_queue_set_specific(concurrentQueue, QueueID, (__bridge void*)concurrentQueue, NULL);
    
    NSMutableString*  s0 = [[NSMutableString alloc] init];
    
    NSArray* handlerPromises = @[mock::async(0.1, @"A")
                          .thenOn(concurrentQueue, ^id(id result) {
                              XCTAssertTrue( dispatch_get_specific(QueueID) == (__bridge void *)(concurrentQueue), @"");
                              [s0 appendString:result];
                              return nil;
                          },nil),
                          mock::async_fail(0.2, @"B")
                          .thenOn(concurrentQueue, ^id(id result) {
                              XCTAssertTrue( dispatch_get_specific(QueueID) == (__bridge void *)(concurrentQueue), @"");
                              [s0 appendString:result];
                              return nil;
                          },nil),
                          mock::async(0.3, @"C")
                          .thenOn(concurrentQueue, ^id(id result) {
                              XCTAssertTrue( dispatch_get_specific(QueueID) == (__bridge void *)(concurrentQueue), @"");
                              [s0 appendString:result];
                              return nil;
                          },nil)];
    
    RXPromise* allHandlerPromises = [RXPromise all:handlerPromises].thenOn(concurrentQueue, ^id(id result) {
        XCTFail(@"unexpected");
        return nil;
    }, ^id(NSError* error) {
        for (RXPromise* p in handlerPromises) {
            [p.parent cancel]; // cancel the underlying task promise
        }
        XCTAssertTrue([s0 isEqualToString:@"A"], @"");
        dispatch_semaphore_signal(sem);
        return error;
    });
    
    [allHandlerPromises wait];
    dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
    
    XCTAssertTrue([handlerPromises[0] isFulfilled], @"");
    XCTAssertTrue([handlerPromises[1] isRejected], @"");
    XCTAssertTrue([handlerPromises[2] isCancelled], @"");
    
    XCTAssertTrue([(RXPromise*)[handlerPromises[0] parent] isFulfilled], @"");
    XCTAssertTrue([(RXPromise*)[handlerPromises[1] parent] isRejected], @"");
    XCTAssertTrue([(RXPromise*)[handlerPromises[2] parent] isCancelled], @"");
}


#pragma mark - any

-(void) testAnyGetFirst {
    // Start `Count` tasks in parallel. Return the  result of the task which
    // finished first and cancel the remaining yet running tasks.
    // Insert the promise of each async task into an array and send class message
    // `any`. Note: do NOT put the promise of the `then`'s handler into the array!
    // When any task has been finished `any` will automatically forward a `cancel`
    // message to the remaining tasks.
    
    const char* QueueID = "test.queue.id";
    dispatch_queue_t sync_queue = dispatch_queue_create("sync.queue", NULL);
    dispatch_queue_set_specific(sync_queue, QueueID, (__bridge void*)sync_queue, NULL);
    
    const int Count = 5;
    char buffer[Count] = {'X'};
    char* p = buffer;
    
    dispatch_group_t group = dispatch_group_create();
    
    for (int i = 0; i < Count; ++i) {
        dispatch_group_enter(group);
    }
    
    NSArray* promises = @[
      mock::async(0.1, @"A").thenOn(sync_queue, ^id(id result) {
          *(p+0)='A';
          dispatch_group_leave(group);
          return nil;
      },^id(NSError*error){
          *(p+0)='a';
          dispatch_group_leave(group);
          return error;
      }).parent,
      mock::async(0.15, @"B").thenOn(sync_queue, ^id(id result) {
          *(p+1)='B';
          dispatch_group_leave(group);
          return nil;
      },^id(NSError*error){
          *(p+1)='b';
          dispatch_group_leave(group);
          return error;
      }).parent,
      mock::async(0.2, @"C").thenOn(sync_queue, ^id(id result) {
          *(p+2)='C';
          dispatch_group_leave(group);
          return nil;
      },^id(NSError*error){
          *(p+2)='c';
          dispatch_group_leave(group);
          return error;
      }).parent,
      mock::async(0.25, @"D").thenOn(sync_queue, ^id(id result) {
          *(p+3)='D';
          dispatch_group_leave(group);
          return nil;
      },^id(NSError*error){
          *(p+3)='d';
          dispatch_group_leave(group);
          return error;
      }).parent,
      mock::async(0.3, @"E").thenOn(sync_queue, ^id(id result){
          *(p+4)='E';
          dispatch_group_leave(group);
          return nil;
      },^id(NSError*error){
          *(p+4)='e';
          dispatch_group_leave(group);
          return error;
      }).parent
    ];
    
    assert([promises count] == Count);
    
    RXPromise* firstTaskHandlerPromise = [RXPromise any:promises].then(^id(id result){
        // When we reach here - executing on an unspecified queue - the first
        // task finished - yet it's handler may not be finished.
        XCTAssertTrue([result isKindOfClass:[NSString class]], @"");  // returns result of first resolved promise
        XCTAssertTrue([@"A" isEqualToString:result], @"");
        // Synchronously dispatch a block on the sync queue, which is guaranteed enqueued after
        // the task's handler:
        dispatch_sync(sync_queue, ^{
            // When we reach here the first task's handler and all other tasks and its
            // handler finished, since we enqueued this block after all others.
            printf("%c", *p);
        });
        // When we reach here - executing on an unspecified queue - the first
        // task and it's handler finished, as well as all others since we enqueued
        // the former block behind all others.
        return @"first task handler finished";
    },^id(NSError*error){
        XCTFail(@"must not be called");
        NSLog(@"ERROR: %@", error);
        return error;
    });
    
    id firstTaskHandlerPromiseValue = [firstTaskHandlerPromise get];
    // When we reach here - executing on an unspecified queue - the first
    // task and it's handler finished.
    NSLog(@"firstTaskHandlerPromise = %@", firstTaskHandlerPromiseValue);
    XCTAssertTrue( std::memcmp(buffer, "Abcde", sizeof(buffer)) == 0, @"");
    
    [[RXPromise all:promises] wait];
    // Wait until the all handlers have been invoked:
    // It's a bit tricky to wait for a number of handlers to have all finished
    // when we do not have the promises. Note, that in the Unit Test handlers write
    // into the stack! This is be fatal if the next test starts and the handlers
    // havn't finished.
    dispatch_group_wait(group, DISPATCH_TIME_FOREVER);
}

-(void) testAnyGetSecond {
    
    // Start `Count` tasks in parallel. Return the first result of any task and
    // cancel the remaining yet running tasks.
    // Insert the promise of each async task into an array and send class message
    // `any`.
    //
    // Note: We do NOT put the promise of the `then`'s handler into the array!
    // We accomplish this via statement:
    //
    //   task().then(...).parent
    //
    // which returns the task's promise, that is
    //   p = task().then(...).parent   is equivalent to
    //   p = task()
    //
    // When any task has been finished `any` will automatically forward a `cancel`
    // message to the remaining tasks.
    
    const char* QueueID = "test.queue.id";
    dispatch_queue_t sync_queue = dispatch_queue_create("sync.queue", NULL);
    dispatch_queue_set_specific(sync_queue, QueueID, (__bridge void*)sync_queue, NULL);
    
    const int Count = 5;
    char buffer[Count] = {'X', 'X', 'X', 'X', 'X'};
    char* p = buffer;
    
    __block NSString* firstResult = nil;
    
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    
    // Note that the array _promises_ contains the promises from the task's *handler*,
    // not the *task promise* itself. Despite `any` will cancel all other promises
    // once the first has been finished, it will not cancel the task promises!
    // This is due to the fact that canceling a promise will not forward the cancel
    // message to their *parent* - in order to prevent an avalange effect which
    // would result in cancelling the whole promise tree, which is usually
    // quite undesired. Thus when the task promise wont be cancelled, and the
    // task has registred a handler to its retunred promise which detetcs
    // cancellation, the task won't get notified about this and won't cancel
    // itself.
    __block NSArray* promises;
    promises = @[
          mock::async(0.2, @"A").thenOn(sync_queue, ^id(id result) {
              *(p+0)='A';
              return @"A";
          },^id(NSError*error){
              *(p+0)='a';
              return error;
          }),
          mock::async(0.1, @"B").thenOn(sync_queue, ^id(id result) {
              *(p+1)='B';
              return @"B";
          },^id(NSError*error){
              *(p+1)='b';
              return error;
          }),
          mock::async(0.3, @"C").thenOn(sync_queue, ^id(id result) {
              *(p+2)='C';
              return @"C";
          },^id(NSError*error){
              *(p+2)='c';
              return error;
          }),
          mock::async(0.4, @"D").thenOn(sync_queue, ^id(id result) {
              *(p+3)='D';
              return @"D";
          },^id(NSError*error){
              *(p+3)='d';
              return error;
          }),
          mock::async(1000.0, @"E").thenOn(sync_queue, ^id(id result){
              *(p+4)='E';
              return @"E";
          },^id(NSError*error){
              *(p+4)='e';
              return error;
          })];
    
    assert([promises count] == Count);
    
    [RXPromise any:promises].thenOn(sync_queue, ^id(id result) {
        // If we reach here, the first finished task and its handler SHALL have been
        // finished. Now, the other handler promises get cancelled, but this will not
        // cancel the task promises!
        //
        // The task which finishes first is task "B".
        // The RXPromise `any` method will forward the cancel message only after
        // the first task's handler has been finished.
        firstResult = result;
        XCTAssertTrue([result isKindOfClass:[NSString class]], @"");  // returns result of first resolved promise
        XCTAssertTrue([@"B" isEqualToString:result], @"%@", result);
        // Note: here a number of tasks may still run! We do not know WHEN the tasks
        // eventually finish and try to resolve the handler promises which are
        // already cancelled by the `any` method. So, we cancel them explictly:
        for (RXPromise* p in promises) {
            [p.parent cancel];
        }
        dispatch_async(sync_queue, ^{
            dispatch_semaphore_signal(sem);
        });
        return nil;
    },^id(NSError*error){
        XCTFail(@"must not be called");
        NSLog(@"ERROR: %@", error);
        // Note: here a number of tasks may still run! We do not know WHEN the tasks
        // eventually finish and try to resolve the handler promises which are
        // already cancelled by the `any` method. So, we cancel them explictly:
        for (RXPromise* p in promises) {
            [p.parent cancel];
        }
        dispatch_async(sync_queue, ^{
            dispatch_semaphore_signal(sem);
        });
        return error;
    });

    // Ensure the tasks are fimished:
    dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
    
    XCTAssertTrue( std::memcmp(buffer, "aBcde", sizeof(buffer)) == 0, @"");
    [[RXPromise all:promises] wait];
}



#pragma mark - API Promises APlus

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
                    XCTAssertTrue(returnedFromThenRef, @"");
                });
                XCTAssertTrue([value isEqualToString:@"Finished"], @"");
                finishedRef.signal();
                return @"OK";
            }, nil);
            returnedFromThenRef = true;
        });
        
        XCTAssertTrue(finishedRef.wait(1), @"");
        XCTAssertTrue(promise2 != nil, @"");
        XCTAssertTrue([promise2.get isEqualToString:@"OK"], @"%@", [promise2.get description]);
    }
    
}


-(void) testAPIPromisesAPlus_1 {

//    $ 1     Both onFulfilled and onRejected are optional arguments:
//            If onFulfilled is not a function, it must be ignored.
//            If onRejected is not a function, it must be ignored.

    RXPromise* promise = [RXPromise new];
    [promise fulfillWithValue:@"OK"];
    RXPromise* p1 = promise.then(nil, nil);
    [p1 wait];
    XCTAssertTrue(p1.isFulfilled == YES, @"");
    
    promise = [RXPromise new];
    [promise rejectWithReason:@"ERROR"];
    RXPromise* p2 = promise.then(nil, nil);
    [p2 wait];
    XCTAssertTrue(p2.isRejected, @"%d", p2.isRejected);
}


-(void) testAPIPromisesAPlus_2 {
    
//  §2    If onFulfilled is a function:
//  §2.1  it must be called after promise is fulfilled, with promise's value as its first argument.
//  §2.2  it must not be called before promise is fulfilled.
//  §2.3  it must not be called more than once.
    
    char buffer[] = {'X', 'X', 'X', 'X'};
    char* pb = &buffer[0];
    
    RXPromise* promise = [RXPromise new];

    promise_completionHandler_t onFulfilled = ^id(id result) {
        XCTAssertTrue(*pb == 'X', @"onFulfilled must not be called more than once.");
        char ch = (char)[(NSString*)result characterAtIndex:0];
        *pb = ch;
        XCTAssertTrue(promise.isFulfilled  && ch == 'A', @"onFulfilled must be called after promise is fulfilled, with promise's value as its first argument.");
        return nil;
    };
    
    promise.then(onFulfilled, nil);
    for (int i = 0; i < 10; ++i) {
        usleep(1000);
        XCTAssertTrue( buffer[0] == 'X', @"onFulfilled must not be called before promise is fulfilled");
    }
    [promise fulfillWithValue:@"A"];
    [promise wait];
    for (int i = 0; i < 10; ++i) {
        usleep(1000);
        [promise fulfillWithValue:@"B"];
        [promise wait];
    }
}


-(void) testAPIPromisesAPlus_3 {
    
// § 3    If onRejected is a function,
// § 3.1   it must be called after promise is rejected, with promise's reason as its first argument.
// § 3.2   it must not be called before promise is rejected.
// § 3.3   it must not be called more than once.
    
    char buffer[] = {'X', 'X', 'X', 'X'};
    char* pb = &buffer[0];
    
    RXPromise* promise = [RXPromise new];
    
    promise_errorHandler_t onRejected = ^id(NSError* error) {
        XCTAssertTrue(*pb == 'X', @"onRejected must not be called more than once.");
        char ch = (char)([error.userInfo[NSLocalizedFailureReasonErrorKey] characterAtIndex:0]);
        *pb = ch;
        XCTAssertTrue(promise.isRejected  && ch == 'A', @"onRejected must be called after promise is rejected, with promise's reason as its first argument.");
        return nil;
    };
    
    promise.then(nil, onRejected);
    for (int i = 0; i < 10; ++i) {
        usleep(1000);
        XCTAssertTrue( buffer[0] == 'X', @"onRejected must not be called before promise is rejected");
    }
    [promise rejectWithReason:@"A"];
    [promise wait];
    for (int i = 0; i < 10; ++i) {
        usleep(1000);
        [promise rejectWithReason:@"B"];
        [promise wait];
    }
}


-(void) testAPIPromisesAPlus_4
{
    // § 4 then must return before onFulfilled or onRejected is called [4.1].
    
    const char* QueueID = "test.queue.id";
    dispatch_queue_t sync_queue = dispatch_queue_create("test.sync.queue", NULL);
    dispatch_queue_set_specific(sync_queue, QueueID, (__bridge void*)sync_queue, NULL);
    
    
    char buffer[] = {'X', 'X', 'X', 'X'};
    __block const char* pb = &buffer[0];
    __block char* p = &buffer[0];
    
    
    promise_completionHandler_t onFulfilled = ^id(id result) {
        (*p++) = 'B';
        return nil;
    };
    promise_completionHandler_t onRejected = ^id(id result) {
        (*p++) = 'b';
        return nil;
    };
    
    RXPromise* promise = [RXPromise new];
    [promise fulfillWithValue:@"OK"];
    
    __block RXPromise* promise2;
    dispatch_sync(sync_queue, ^{
        promise2 = promise.thenOn(sync_queue, onFulfilled, onRejected);
        (*p++) = 'A';
        XCTAssertTrue(*pb == 'A', @"then must return before onFulfilled is called");
    });
    [promise2 wait];
    XCTAssertTrue(*pb == 'A', @"then must return before onFulfilled is called");
    
    buffer[0] = 'X';
    buffer[1] = 'X';
    p = &buffer[0];
    
    promise = [RXPromise new];
    [promise rejectWithReason:@"ERROR"];
    
    dispatch_sync(sync_queue, ^{
        promise2 = promise.thenOn(sync_queue, onFulfilled, onRejected);
        (*p++) = 'A';
        XCTAssertTrue(*pb == 'A', @"then must return before onRejected is called");
    });
    [promise2 wait];
    XCTAssertTrue(*pb == 'A', @"then must return before onRejected is called");
}

    // All handlers of a particular promise MUST run in serial in the order as
    // they have been defined. This is a requirement of the promise spec.
    //
    // If the user explicitly specifies a dedicated handler queue through using
    // the `thenOn` property the above rule may no longer hold true. The behavior
    // shall be implementation defined:
    //
    // Handlers of a particular promise with a specified handler queue run on
    // the queue with their respective property:
    //
    // a) A serial handler queue SHALL execute the handlers in serial and in order
    //    as they have been defined.
    //
    // b) A concurrent handler queue SHALL execute the handlers in parallel.
    //
    //
    // RXPromise library also gives the guarantee that all handlers for a particular
    // promise tree run in serial, unless a dedicated handler queue is specified.
    // It is desired, that handlers from different promise trees should not be
    // forced to run in serial.


-(void) testAPIPromisesAPlus_6
{
    //  §6  `then` may be called multiple times on the same promise.
    //      If/when promise is fulfilled, all respective onFulfilled callbacks
    //      must execute in the order of their originating calls to then.
    //      If/when promise is rejected, all respective onRejected callbacks must
    //      execute in the order of their originating calls to then.
    
    // Note: Since handlers run in parallel by default in RXPromise, in this
    // test RXPromise used a serial queue to verify the rule.
    
    const char* QueueID = "test.queue.id";
    dispatch_queue_t sync_queue = dispatch_queue_create("test.sync.queue", NULL);
    dispatch_queue_set_specific(sync_queue, QueueID, (__bridge void*)sync_queue, NULL);
    
    

    const int Count = 5;
    
    // Expected Result
    std::array<char, 2*Count> expectedResults;
    for (int i = 0; i < Count; ++i) {
        expectedResults[2*i] = char('a' + i);
        expectedResults[2*i+1] = char('A' + i);  // "aAbBcC..."
    };
    
    // Actual Result
    std::array<char, 2*Count> results;
    __block char* data = results.data();
    
    
    // § 6.1 fulfilled
    std::fill(results.begin(), results.end(), 'X');
    __block int c = 0;
    dispatch_semaphore_t sem1 = dispatch_semaphore_create(0);

    RXPromise* root = [RXPromise new];
    for (int i = 0; i < Count; ++i) {
        root.thenOn(sync_queue, ^id(id result) {
            *data++ = char('a'+i);
            usleep(Count*1000 - i*1000);
            *data++ = char('A'+i);
            if (++c == Count) {
                dispatch_semaphore_signal(sem1);
            }
            return nil;
        }, nil);
    }
    [root fulfillWithValue:@"OK"];
    
    XCTAssertTrue(0 == dispatch_semaphore_wait(sem1, dispatch_time(DISPATCH_TIME_NOW, 10*NSEC_PER_SEC)), @"");
    XCTAssertTrue(results == expectedResults, @"§6.1 failed");
    
    // § 6.2 rejected
    std::fill(results.begin(), results.end(), 'X');
    data = results.data();
    dispatch_semaphore_t sem2 = dispatch_semaphore_create(0);
    c = 0;
    
    root = [RXPromise new];
    for (int i = 0; i < Count; ++i) {
        root.thenOn(sync_queue, nil, ^id(NSError* error) {
            *data++ = char('a'+i);
            usleep(Count*1000 - i*1000);
            *data++ = char('A'+i);
            if (++c == Count) {
                dispatch_semaphore_signal(sem2);
            }
            return nil;
        });
    }
    [root rejectWithReason:@"Failed"];
    
    XCTAssertTrue(0 == dispatch_semaphore_wait(sem2, dispatch_time(DISPATCH_TIME_NOW, 10*NSEC_PER_SEC)), @"");
    XCTAssertTrue(results == expectedResults, @"§6.2 failed");
}


#pragma mark -

-(void) testHandlersOfDistinctPromiseTreesShouldRunConcurrently {
    
    // Handlers of promises which belong to distincts trees SHOULD be
    // executed concurrently.
    
    const int Count = 2*4;
    std::array<char, Count> results;
    std::fill(results.begin(), results.end(), 'X');
    
    std::array<char, Count> expectedResults = {'a', 'b', 'c', 'd', 'A', 'D', 'C', 'B'};
    
    __block char* data = results.data();
    
    RXPromise* root1 = mock::async(0.01, @"OK");
    RXPromise* root2 = mock::async(0.02, @"OK");
    RXPromise* root3 = mock::async(0.03, @"OK");
    RXPromise* root4 = mock::async(0.04, @"OK");
    
    NSArray* promises = @[
        root1.then(^id(id result) {
            *data++ = char('a');
            usleep(200*1000);  // 200 ms
            *data++ = char('A');
            return result;
        }, nil),

        root2.then(^id(id result) {
            *data++ = char('b');
            usleep(350*1000);  // 350 ms
            *data++ = char('B');
            return result;
        }, nil),
        
        root3.then(^id(id result) {
            *data++ = char('c');
            usleep(300*1000);  // 300 ms
            *data++ = char('C');
            return result;
        }, nil),
    
        root4.then(^id(id result) {
            *data++ = char('d');
            usleep(250*1000);  // 250 ms
            *data++ = char('D');
            return result;
        }, nil)
    ];
    
    [[RXPromise all:promises] wait];
    XCTAssertTrue(results == expectedResults, @"Handlers of promises which belong to distinct trees SHOULD be executed concurrently");
}


-(void) testHandlersOfAParticularPromiseWithDedicatedSerialQueueMustRunInSerial {
    
    // Handlers of a particular promise with a specified handler queue run on
    // the queue with their respective property:
    //
    // a) A serial handler queue SHALL execute the handlers in serial and in order
    //    as they have been defined.
    
    const char* QueueID = "com.test.queue.id";
    dispatch_queue_t sync_queue = dispatch_queue_create("my.sync.queue", NULL);
    dispatch_queue_set_specific(sync_queue, QueueID, (__bridge void*)sync_queue, NULL);

    const int Count = 10;
    std::array<char, Count> results;
    std::fill(results.begin(), results.end(), 'X');
    
    std::array<char, Count> expectedResults;
    for (int i = 0; i < Count; ++i) {
        expectedResults[i] = char('A' + i);  // "ABCDEF"
    };
    
    std::atomic_int c(0);
    std::atomic_int* pc = &c;
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    __block char* data = results.data();
    
    RXPromise* root = mock::async(0.01, @"OK");
    
    for (int i = 0; i < Count; ++i) {
        root.thenOn(sync_queue, ^id(id result) {
            XCTAssertTrue( dispatch_get_specific(QueueID) == (__bridge void *)(sync_queue), @"Handler does not execute on dedicated queue");
            usleep(Count*1000 - i*1000);
            *data++ = char('A'+i);
            if (++(*pc) == Count) {
                dispatch_semaphore_signal(sem);
            }
            return nil;
        }, nil);
    }
    
    XCTAssertTrue(0 == dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 10*NSEC_PER_SEC)), @"");
    XCTAssertTrue(results == expectedResults, @"");
    
}



-(void) testHandlersOfAParticularPromiseWithACustomConcurrentQueueMustRunInSerial {
    
    // Since v0.10.2, A handler executed on a concurrent queue must use a barrier,
    // which effectively serializes handlers.
    
    const char* QueueID = "com.test.queue.id";
    dispatch_queue_t concurrent_queue = dispatch_queue_create("my.concurrent.queue", DISPATCH_QUEUE_CONCURRENT);
    dispatch_queue_set_specific(concurrent_queue, QueueID, (__bridge void*)concurrent_queue, NULL);
    const int Count = 10;
    __block int activeCounter = 0;
    __block int counter = 0;
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    
    RXPromise* root = mock::async(0.01, @"OK");
    for (int i = 0; i < Count; ++i) {
        root.thenOn(concurrent_queue, ^id(id result) {
            XCTAssertTrue( dispatch_get_specific(QueueID) == (__bridge void *)(concurrent_queue), @"Handler does not execute on dedicated queue");
            ++activeCounter;
            ++counter;
            usleep(10*1000);
            XCTAssertTrue(activeCounter == 1, @"");
            if (counter == (Count-1)) {
                dispatch_semaphore_signal(sem);
            }
            --activeCounter;
            return nil;
        }, nil);
    }
    
    XCTAssertTrue(0 == dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 10000*NSEC_PER_SEC)), @"");
}


#pragma mark - timeout

- (void) testTimeoutShouldRejectPromiseWithTimeoutError {
    
    RXPromise* promise = [RXPromise new];
    
    [promise setTimeout:0.1];
    
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    
    promise.then(nil, ^id(NSError* error) {
        XCTAssertTrue(error != nil, @"error must not be nil");
        XCTAssertTrue([error.domain isEqualToString:@"RXPromise"], @"");
        XCTAssertTrue(error.code == -1001, @"");
        XCTAssertTrue([error.userInfo[NSLocalizedFailureReasonErrorKey] isEqualToString:@"timeout"], @"");
        dispatch_semaphore_signal(sem);
        return nil;
    });

    XCTAssertTrue(dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 0.05*NSEC_PER_SEC)) != 0, @"promise resoveld prematurely");
    XCTAssertTrue(dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 0.2*NSEC_PER_SEC)) == 0, @"test timed out");
}


#pragma mark - runLoopWait

- (void) testRunLoopWait {
    
    RXPromise* promise = [RXPromise new];
    
    NSAssert([NSThread currentThread] == [NSThread mainThread], @"this test must run on the main thread");
    
    double delayInSeconds = 0.2;
    dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayInSeconds * NSEC_PER_SEC));
    dispatch_after(popTime, dispatch_get_main_queue(), ^(void) {
        NSAssert([NSThread currentThread] == [NSThread mainThread], @"this test must run on the main thread");
        [promise fulfillWithValue:@"OK"];
    });
    
    [promise setTimeout:1];
    [promise runLoopWait];
    
    [promise.then(^id(id result) {
        XCTAssertTrue([@"OK" isEqualToString:result], @"");
        return nil;
    }, ^id(NSError* error) {
        XCTFail(@"Error handler not expeted");
        return error;
    }) wait];
}

#include <mach/mach.h>
#include <mach/mach_time.h>


- (void) disabled_testPromisePerformance
{
    NSAssert([NSThread currentThread] == [NSThread mainThread], @"this test must run on the main thread");
    
    mach_timebase_info_data_t timebase_info;
    mach_timebase_info(&timebase_info);
    double clock2ns = ((double)timebase_info.numer / (double)timebase_info.denom);
    
    
    RXPromise* promise = [RXPromise new];
    dispatch_queue_t syncQueue = dispatch_queue_create("test.sync_queue", DISPATCH_QUEUE_CONCURRENT);
    
    __block uint64_t t1;
    
    
    double delayInSeconds = 0.5;
    dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayInSeconds * NSEC_PER_SEC));
    dispatch_after(popTime, syncQueue, ^(void) {
        [promise fulfillWithValue:@"OK"];
        t1 = mach_absolute_time();
    });
    
    [promise setTimeout:5];
    [promise runLoopWait];

    NSMutableArray* promises = [[NSMutableArray alloc] init];
    
    for (int i = 0; i < 100; ++i) {
        RXPromise* p = promise.thenOn(syncQueue, ^id(id result) {
            uint64_t t2 = mach_absolute_time();
            double d = (t2-t1)*clock2ns*1e-3; // µs
            return [NSNumber numberWithDouble:d];
        }, ^id(NSError* error) {
            XCTFail(@"Error handler not expeted");
            return error;
        });
        [promises addObject:p];
        
    }
    
    [[RXPromise all:promises].thenOn(dispatch_get_main_queue(), ^id(id result) {
        uint64_t t = mach_absolute_time();
        double te = (t-t1)*clock2ns*1e-3; // µs
        NSLog(@"elapsed time: %.3f µs,\nresults: %@", te, result);
        return nil;
    }, ^id(NSError* error) {
        XCTFail(@"Error %@", error);
        return error;
    }) runLoopWait];
}



#pragma mark - Convenient Class Methods

- (void) testConvenientMethod
{
    RXPromise* p = [RXPromise promiseWithTask:^id{
        // lengthy task
        return @"OK";
    }];
    
    XCTAssertNotNil(p, @"");
    
    p.then(^id(id result) {
        XCTAssertTrue([result isKindOfClass:[NSString class]], @"");
        XCTAssertTrue([@"OK" isEqualToString:result], @"");
        return nil;
    }, ^id(NSError* error) {
        XCTFail(@"error handler not expected");
        return nil;
    });
    
    [p setTimeout:1];
    [p runLoopWait];
    [p.then(nil, ^id(NSError* error) {
        XCTFail(@"Error handler not expeted");
        return error;
    }) wait];
}

- (void) testConvenientMethodWithQueue
{
    RXPromise* p = [RXPromise promiseWithQueue:dispatch_get_main_queue() task:^id{
        XCTAssertTrue([NSThread currentThread] == [NSThread mainThread], @"");
        return @"OK";
    }];
    
    XCTAssertNotNil(p, @"");
    
    p.then(^id(id result) {
        XCTAssertTrue([result isKindOfClass:[NSString class]], @"");
        XCTAssertTrue([@"OK" isEqualToString:result], @"");
        return nil;
    }, ^id(NSError* error) {
        XCTFail(@"error handler not expected");
        return nil;
    });
    
    [p setTimeout:1];
    [p runLoopWait];
    [p.then(nil, ^id(NSError* error) {
        XCTFail(@"Error handler not expeted");
        return error;
    }) wait];
}


#pragma mark - root

- (void) testRoot
{
    RXPromise* root = [RXPromise new];
    XCTAssertTrue(root == root.root, @"");
    
    RXPromise* p2 = root.then(^id(id result) {
        return @"OK";
    }, nil);
    XCTAssertTrue(root == p2.root, @"");
    
    [p2 cancel];
    XCTAssertTrue(root == p2.root, @"");
    
}


#pragma mark - sequence


- (void) testSequence
{
    NSArray* inputs = @[@"a", @"b", @"c", @"d", @"e", @"f", @"g"];
    NSMutableString* resultString = [[NSMutableString alloc] init];
    
    RXPromise* finished = [RXPromise sequence:inputs task:^RXPromise*(id input) {
        return [RXPromise promiseWithTask:^id{
            NSString* str = [input capitalizedString];
            [resultString appendString:str];
            return @"OK";
        }];
    }];
    
    [finished runLoopWait];
    
    XCTAssertTrue([resultString isEqualToString:@"ABCDEFG"], @"");
    
}


- (void) testSequenceWithCancellation {
    typedef RXPromise* (^block_t)(NSString* input);
    
    NSArray* inputs = @[@"a", @"b", @"c", @"d", @"e", @"f", @"g", @"h", @"i", @"j"];
    // Expected result if not cancelled: @"ABCDEFGHIJ";
    
    NSMutableString* resultString = [[NSMutableString alloc] init];
    RXPromise* didCancelPromise = [RXPromise new];
    // Define a cancelable task:
    block_t task = ^(NSString* input)
    {
        RXPromise* taskPromise = [[RXPromise alloc] init];
        // Define a block which gets executed when the timer fires:
        RXTimerHandler block = ^(RXTimer* timer) {
            NSString* result = [input capitalizedString];
            [resultString appendString:result];
            NSLog(@"processed with result: %@", result);
            [taskPromise fulfillWithValue:result];
        };
        NSLog(@"processing input: %@", input);
        RXTimer* timer = [[RXTimer alloc] initWithTimeIntervalSinceNow:0.05
                                                             tolorance:0
                                                                 queue:dispatch_get_global_queue(0, 0)
                                                                 block:block];
        // Catch any errors send to the task promise, in which case we cancel the timer:
        taskPromise.then(nil, ^id(NSError*error){
            [timer cancel];
            [didCancelPromise fulfillWithValue:@"OK - did cancel"];
            return nil;
        });
        [timer start];
        return taskPromise;
    };
    RXPromise* finished = [RXPromise sequence:inputs
                                         task:^RXPromise*(id input) {
                                             return task(input);
                                         }];
    finished.then(nil, ^id(NSError*error){
        //NSLog(@"sequence failed due to: %@", error);
        return nil;
    });
    [finished setTimeout:0.125]; // expected finish after 10*0.05 (if not cancelled)
    [finished runLoopWait];
    [[didCancelPromise setTimeout:1.0].then(^id(id result){
        XCTAssertTrue([@"OK - did cancel" isEqualToString:result], @"");
        return result;
    }, ^id(NSError* error){
        XCTFail(@"unexpected timeout");
        return error;
    }) wait];
    XCTAssertTrue([resultString isEqualToString:@"AB"], @"%@", resultString);
}


- (void) testRepeat
{
    NSArray* inputs = @[@"a", @"b", @"c", @"d", @"e", @"f", @"g"];
    NSMutableString* resultString = [[NSMutableString alloc] init];
    const NSUInteger count = [inputs count];
    __block NSUInteger i = 0;
    [[RXPromise repeat:^RXPromise *{
        if (i >= count) {
            return nil;
        }
        return [RXPromise promiseWithTask:^id{
            NSString* str = [inputs[i++] capitalizedString];
            [resultString appendString:str];
            return @"OK";
        }];
    }] runLoopWait];
    
    XCTAssertTrue([resultString isEqualToString:@"ABCDEFG"], @"");
}

- (void) testRepeatWithCancellation
{
    NSMutableString* resultString = [[NSMutableString alloc] init];
    
    RXPromise* didCancelPromise = [RXPromise new];
    
    double taskDuration = 0.2;
    // Define a cancelable task:
    typedef RXPromise* (^task_t)(NSString* input);
    task_t task = ^RXPromise*(NSString* input)
    {
        RXPromise* taskPromise = [[RXPromise alloc] init];
        // Define a block which gets executed when the timer fires:
        RXTimerHandler block = ^(RXTimer* timer) {
            NSString* result = [input capitalizedString];
            [resultString appendString:result];
            NSLog(@"processed with result: %@", result);
            [taskPromise fulfillWithValue:result];
        };
        NSLog(@"processing input: %@", input);
        RXTimer* timer = [[RXTimer alloc] initWithTimeIntervalSinceNow:taskDuration
                                                             tolorance:0
                                                                 queue:dispatch_get_global_queue(0, 0)
                                                                 block:block];
        // Catch any errors - especially "cancel" - sent to the task promise,
        // in which case we cancel the timer:
        taskPromise.then(nil, ^id(NSError*error){
            [timer cancel];
            [didCancelPromise fulfillWithValue:@"OK - did cancel"];
            return nil;
        });
        [timer start];
        return taskPromise;
    };
    
    NSArray* inputs = @[@"a", @"b", @"c", @"d", @"e", @"f", @"g", @"h", @"i"];
    const NSUInteger count = [inputs count];
    __block NSUInteger i = 0;
    
    RXPromise* finished = [RXPromise repeat:^RXPromise *{
        if (i >= count) {
            return nil;
        }
        return task(inputs[i++]);
    }];

    finished.then(nil, ^id(NSError*error){
        //NSLog(@"repeat failed due to: %@", error);
        return nil;
    });
    
    [finished setTimeout:(taskDuration*2 + 0.1*taskDuration)]; // this cancels the repeat after two iterations
    [finished runLoopWait];
    
    [[didCancelPromise setTimeout:taskDuration*[inputs count]].then(^id(id result){
        XCTAssertTrue([@"OK - did cancel" isEqualToString:result], @"");
        return result;
    }, ^id(NSError* error){
        XCTFail(@"unexpected timeout");
        return error;
    }) wait];
    
    XCTAssertTrue([resultString isEqualToString:@"AB"], @"%@", resultString);
}


- (void) testConcurrentHandlerQueue {
    
    typedef RXPromise* (^task_t)(int a);
    
    
    task_t task = ^RXPromise* (int a) {
        RXPromise* promise = [[RXPromise alloc] init];
        double delayInSeconds = 1.0;
        dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayInSeconds * NSEC_PER_SEC));
        dispatch_after(popTime, dispatch_get_global_queue(0, 0), ^(void){
            [promise fulfillWithValue:[NSNumber numberWithInt:a]];
        });
        return promise;
    };
    
    const int N = 1000;
    std::vector<int> vector;
    for (int i = 1; i <= N; ++i) {
        vector.push_back(i);
    }
    
    dispatch_queue_t concurrentQueue = dispatch_queue_create("concurrentQueue", DISPATCH_QUEUE_CONCURRENT);
    __block int result = 0;
    
    dispatch_group_t group = dispatch_group_create();
    
    for (int i = 0; i < N; ++i) {
        dispatch_group_enter(group);
        task(vector[i]).thenOn(concurrentQueue, ^id(id a) {
            int x = [a intValue];
            result += x;
            dispatch_group_leave(group);
            return nil;
        }, ^id(NSError*error){
            dispatch_group_leave(group);
            return error;
        });
    }

    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    dispatch_group_notify(group, concurrentQueue, ^{
        int expectedResult = (N+1)*N/2;
        XCTAssertTrue(expectedResult == result, @"");
        dispatch_semaphore_signal(sem);
    });
    
    
    dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
    
}



@end
