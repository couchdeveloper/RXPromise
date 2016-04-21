## This file describes API changes, new features and bug fixes on a high level point of view.

# RXPromise

## Version 0.1.0 beta (22.05.2013)

* Initial Version



## Version 0.2.0 beta (29.05.2013)

#### Changes

* Improved runtime memory requirements of a promise instance.


## Version 0.3.0 beta (30.05.2013)

#### Bug Fixes

* Fixed issue with dispatch objects becoming "retainable object pointers. Compiles now for deployment targets iOS >= 6.0 and Mac OS X >= 10.8.


## Version 0.4.0 beta (31.05.2013)

#### Changes

* Added a method `bind` in the "Deferred" API.

`bind` can be used by an asynchronous result provider if it itself uses another asynchronous result provider's promise in order to resolve its own promise.

A `cancel` message will be forwarded to the bound promise.



### Version 0.4.1 beta (31.05.2013)

* Minor fixes in accompanying documents


### Version 0.4.2 beta (31.05.2013)

#### Bug Fixes

* Fixed bug in a macro used for source code compatibility for different OS versions. This should now definitely fix the OS version issue.


## Version 0.5.0 beta (1.06.2013)

#### Changes

* Created Library projects for Mac OS X (framework and static) and iOS (static)

The libraries require deployment target >= Mac OS X 10.7, respectively >= iOS 5.1

Due to moving the code into libraries, the logging mechanism became an implementation detail. Log level has been set to `DEBUG_LOGLEVEL_WARN` for Debug configurations - that is, only warning messages will be printed which may indicate an error somewhere. For Release configuration the debug log level has been set to `DEBUG_LOGLEVEL_ERROR`, which always means a really serious error.



### Version 0.5.1 beta (4.06.2013)

#### Bug Fixes

* Fixed Copy Header path for Mac OS X static library



## Version 0.6 beta (5.07.2013)

#### Changes

* The implementation became more memory efficient. However, this required to use a standard container from the C++ standard library. This has the consequence, that an application which links against the static library or incorporates the sources directly need to link against the standard C++ library by adding the compiler option "-lc++" to the "Other Linker Flags" build setting. When linking against the framework, this setting is not required.


* Added a few samples to show some advanced use cases.


* Removed the "preliminary" API for the process handler. IMO, a process handler is not appropriate for a Promise - that may be moved to the asynchronous provider.


* A few new unit tests have been added to specifically test subtle edge-cases. The implementation appears to be quite stable and no failure could have been detected.


## Version 0.7 beta (6.08.2013)

#### Changes

** BREAKING CHANGES **

 In version 0.6 and before, _all_ handlers have been executed _serially_ on a private dispatch queue.

In version 0.7 and later, the `then` property now assumes an _implicit_ execution context which is a _concurrent dispatch queue_. That means, when using the `then` property - without an explicitly specified execution context for the handlers - the handler will execute concurrently on any thread respectively on an concurrent queue. The consequence is that handlers are no more serialized and concurrent access to shared resources is no more automatically thread safe!

Concurrent access to shared resources can now be achieved through _explicitly_ specifying an execution context with the new `thenOn` property. With this property one can explicitly specify the execution context (a dispatch queue) where the handler shall be executed with the first parameter to the returned then block:

Example:

        dispatch_queue_t sync_queue = dispatch_queue_create("sync.queue", NULL);

        asyncFoo().thenOn(sync_queue, onCompletion, onError);


Here, _sync_queue_ is a serial queue, and due to this, concurrent access from within the handlers to shared resources through this queue is safe. The sync_queue may also be used from elsewhere in order to guarantee safe access, not just handlers.

The _explicit_ execution context can also be a concurrent dispatch queue.


The advantage of an implicit concurrent execution context is, that handlers now do execute independently from each other, and handlers will not have to wait until one other handler is finished. This improves CPU utilization and is less prone to unwanted blocking.

Note though, that handler still SHOULD NOT perform lengthy tasks and SHOULD NOT block. If this is the case, the handler should be wrapped into an asynchronous task.


* Added new API:  

The `thenOn` property has been added which provides a means to explicitly specify where the handlers are executed.



### Version 0.7.3 beta (31.08.2013)

#### Bug Fixes

* Fixed a bug in method bind, which erroneously fulfilled the target promise if the other promise was rejected.



## Version 0.8 beta (08.09.2013)


#### New APIs

    - (RXPromise*) setTimeout:(NSTimeInterval)timeout;

This sets a timeout for the promise. If the timeout expires before the promise has been resolved, the promise will be rejected with an error with domain: @"RXPromise", code:-1001, userInfo:@{NSLocalizedFailureReasonErrorKey: @"timeout"}



    - (void) runLoopWait;

 Runs the current run loop until after the receiver has been resolved,
 and previously queued handlers have been finished.



### Version 0.8.1 beta (08.09.2013)

#### Changes:

Added a strict requirement when using `runLoopWait`: The current thread MUST have a run loop and at least one event source. Otherwise the behavior is undefined.

Well, the main thread will always fulfill this prerequisite - but it may not be true for secondary threads unless the program to test is carefully designed and has an event source attached to the secondary thread (e.g. a NSURLConnection).
In the current implementation and in the _worst case_, the behavior *MAY* be such that `runLoopWait` MAY _busy wait_ and hog a CPU for a short time. This is entirely a cause of how `NSRunLoop` is implemented internally.



### Version 0.8.2 beta (12.09.2013)


#### Changes

 -  The logging feature - primarily a means for debugging and hunting subtle bugs - has been effectively disabled by default. The verbosity of and the "severity" of the log messages will be controlled by the macro `DEBUG_LOG`. Unless it is defined in a build setting or elsewhere, `DEBUG_LOG` will be defined in RXPromise.mm such that only errors will be logged. Defining it to 2, 3, or 4 will increase the verbosity.


 -  A few typos have been fixed in code and README.md  (Contributed by Rob Ryan)



#### Bug Fixes

A Unit Test has been fixed which potentially has reported a false positive.


#### Misc:

 Fixed a spurious Static Analyzer warning.



### Version 0.8.3 beta (13.09.2013)


#### Changes

Added a "How To Install" section in the README.md file.



## Version 0.9 beta (2013-09-20)


#### Changes

- Updated Xcode Project for Xcode 5

- Now using XCTest for Unit Tests.

- Documentation style is optimized for Xcode's 5 inline help bubbles.


#### BREAKING CHANGES

The class method

`+ (RXPromise*)all:(NSArray*)promises;`

now returns a `RXPromise` whose success handler returns an array containing the _result_ of each asynchronous task (in the corresponding order).
Before, the _results_ parameter contained the array of promises. So basically, it _was_ the same array as the array specified in parameter _promises_.


#### New APIs

- Added two convenient class methods

`+ (RXPromise*) promiseWithTask:(id(^)(void))task;`

and

`+ (RXPromise*) promiseWithQueue:(dispatch_queue_t)queue task:(id(^)(void))task;`


- Added a property `root` which returns the root promise.


- Added a class method

`+ (RXPromise*) sequence:(NSArray*)inputs task:(RXPromise* (^)(id input)) task;`

which can be used to chain a number of tasks which can be initialized from the
inputs array. The sequence method supports cancellation.



### Version 0.9.1 beta (2013-09-20)


#### Changes

Minor updates in documentation.


### Version 0.9.2 beta (2013-09-27)


#### Bug Fixes

Fixed a subtle race condition in method `setTimeout:`.


#### Changes

 -  Improved memory management in method `sequence:task:`

 -  Xcode configuration files updated for iOS 7.

 -  Added Unit Tests for iOS running on the device.




### Version 0.9.3 beta (2013-09-20)
### Version 0.9.4 beta (2013-09-20)

#### Bug Fixes

Fixed silly typos that slipped into the sources accidentally.




### Version 0.9.5 beta (2013-10-21)

#### Bug Fixes

Class `RXPromise` now can be properly subclassed. The then_block now returns a promise of the subclass, for example:

    MyPromise* promise1 = ...
    MyPromise* promise2 = promise1.then(^id(id result){ return @"OK; }, nil);


Likewise, inherited class factory methods now return on object of the subclass, for example:

  MyPromise* promise = [MyPromise all:array];




#### Changes

 -  Improved documentation in the README.md.




 #### Known Issues

 -  Due to an issue in Xcode 5, it's not possible to run *individual* unit test methods when clicking on the diamond in the gutter for an Mac OS X test bundle. This happens when the same unit test source code is shared for an iOS test bundle and a Mac OS X test bundle. The whole test runs without problems, and individual unit tests can be run from within the Test Navigation pane.



### Version 0.9.6 beta (2013-11-10)

#### Changes

- Removed LTO optimization and added 64-bit architecture from iOS static library project.




## Version 0.10.0 beta (2013-11-11)


#### Added `RXPromise+RXExtension` module


The library no longer will be comprised by a single file.

Now, the core functionality of a RXPromise remains in module `RXPromise.m` and the corresponding header file. All additional "extensions" like the class methods `+all:`, `+any:`, `+sequence:task:` and `+repeat:` have been moved into a Category "RXExtension" and into a new file: `RXPromise+RXExtension.m` along with a corresponding header file.

Using the extension methods requires to import the header file `RXPromise+RXExtension.h`.



#### New APIs

##### Added a class method `repeat:`:

    typedef RXPromise* (^rxp_nullary_task)();

    + (instancetype) repeat: (rxp_nullary_task)block;


  This class method asynchronously executes the block in a loop until either the
  tasks returns `nil` signaling the end of the repeat loop, or the returned promise
  will be rejected.

  The API is available in the RXExtension category.


##### Example

    NSArray* urls = ...;
    const NSUInteger count = [urls count];
    __block NSUInteger i = 0;
    [RXPromise repeat:^RXPromise *{
        if (i >= count) {
            return nil;
        }
        return [self fetchImageWithURL:urls[i]].then(^id(id image){
            [self cacheImage:image withURL:[urls[i]]];
            ++i;
            return nil;
        }, nil);
    }];




#### Changes

 -  Improved INSTALL documentation.




### Version 0.10.1 beta (2013-11-21)

#### Bug Fixes

Fixed import directives. This caused linker issues when including the headers and sources directly into a project.



### Version 0.10.2 beta (2013-11-28)

#### Changes


When the `thenOn` property is used to specify a *concurrent* dispatch queue where the handler will be executed, `RXPromise` will dispatch the handler blocks using a barrier as shown below:

```objective-c
if ([result isKindOfClass:[NSError class]) {
   dispatch_barrier_async(queue, error_handler(result));
}
else {
   dispatch_barrier_async(queue, success_handler(result));
}
```

When using `dispatch_barrier_async` handlers will use the queue exclusively which makes concurrent write and read access from within handlers to shared resources thread-safe.


When registering handlers with the `then` property, one should not make any assumptions about the execution context. Currently, the handlers will be executed on a private concurrent queue using `dispatch_async`. Thus, when accessing shared resources from within handlers registered with `then`, thread safety is not guaranteed.



### Version 0.10.3 beta (2013-11-28)

Fixed typos in README.



### Version 0.10.4 beta (2014-02-28)

### Bug Fixes

Fixed the implementation of the second designated initializer `initWithResult:`

#### Changes


Added Sample6 which demonstrates how an asynchronous task can be cancelled when there are no more "observers" to the promise anymore.

Added Sample7 showing how to use class method `repeat`.



### Version 0.10.5 beta (2014-03-03)

#### Supporting CocoaPods

Client Xcode projects can install the RXPromise library utilizing CocoaPods.



## Version 0.11.0 beta (2014-03-11)

#### Bug Fixes

 - Fixed a glaring bug in the class methods `all` and `any` which may have caused
  crashes.

### Breaking API Changes

- The behavior of the class methods `all:` and `any` has been changed.

 Now, the methods don't cancel any other promise in the given array if any has
 been resolved or if the returned promise has been cancelled.

 This is more consistent with the rule that a promise if cancelled shall not forward the cancellation to its parents. The promises in the given  array can be viewed as the "parents" of the returned promise. Now, canceling the returned promise won't touch the promises in the given array.

 Furthermore, not forwarding the cancel message or canceling all other promises if one has been resolved enables to use promises within the array which are part of any other promise tree, without affecting this other tree.

 Now, it is suggested to take any required action in the *handlers* of the returned promise.

 For example, cancel all other promises when one has been resolved:

        NSArray* promises = @[async(@"a"), @async(@"b")];
        [RXPromise all:promises]
        .then(^id(id result){
            for (RXPromise* p in promises) {
                [p cancel];
            }
            return nil;
        }, ^id(NSError*error){
            for (RXPromise* p in promises) {
                [p cancelWithReason:error];
            }
            return error;
        });




#### API Additions

 - Added an instance method `makeBackgroundTaskWithName`.

        /**
         Executes the asynchronous task associated to the receiver as an
         iOS Background Task.

         @discussion The receiver requests background execution time from
         the system which delays suspension of the app up until the receiver
         will be resolved or cancelled.

         Since Apps are given only a limited amount of time to finish
         background tasks, this time may expire before the task finishes.
         In this case the receiver's root will be cancelled which in turn
         propagates the cancel event to all children of the receiver,
         including the receiver.

         Tasks may want to handle the cancellation in order to execute
         additional code which orderly closes the task. This should not take
         too long, since by the time the cancel handler is called, the app is
         already very close to its time limit.

         @warning Handlers registered on child promises may not be executed
         when the app is in background.

         @param taskName The name to display in the debugger when viewing the
         background task.

         If you specify \c nil for this parameter, this method generates a
         name based on the name of the calling function or method.
        */
        - (void) makeBackgroundTaskWithName:(NSString*)taskName;



#### Unit Tests

- Fixed issues with unit tests having promises whose handlers may still execute
after the test finished and which modified the stack. This caused a crash in the subsequent test.


#### Implementation

- Method `registerWithQueue:onSuccess:onFailure:returnPromise:` has been rewritten.
Observable behavior is still the same, though.

- Changed code and added attributes to function/method declarations which now
should help the compiler during ARC optimization to avoid putting objects into the
autorelease pool.

 There is still one occurrence where the ARC optimizer cannot prevent this: when an
 object is created and returned in handlers, these objects will be put into the
 autorelease pool. This does not happen when the source code is directly included in
 the client project.




### Version 0.11.1 beta (2014-03-19)

 - Simplified implementation of class method `all` and `any`.

 - Improved setup for iOS Unit Tests.



### Version 0.11.2 beta (2014-04-01)

 - Fixed a bug in method `runLoopWait`.

 - Minimum Deployment target for Mac OS X is now 10.8.



### Version 0.11.3 beta (2014-04-05)

 - Fixed a bug where the cancel reason for promises returned by methods `repeat` and `sequence` has not been forwarded to the current task.

 - Added Unit Tests to confirm that cancel reasons get forwarded correctly.




## Version 0.12.0 beta (2014-04-09)

### API Changes

 - Additional Execution Contexts

 Now, the following kind of execution contects can be specified with the `thenOn` property:

  - dispatch_queue
  - NSOperationQueue
  - NSThread
  - NSManagedObjectContext

 For example:

 ```Objective-C
 NSOperationQueue* operationQueue = [[NSOperationQueue alloc] init];

 promise.thenOn(operationQueue, ^id(id result){
     // executing on the NSOperationQueue
     ...
     return nil;
 }, nil);
```
 - Added a property `thenOnMain` for convenience which is functional equivalent to
  `thenOn(dispatch_get_main_queue(), .., ...)`


### Bug Fixes

 - Minimum iOS deployment target (since 0.11.0) MUST be iOS 6.0

 - Fixed a Unit Test

### Documentation

- The documentation in the README.md file has been revised.

### Miscellaneous

 - Minor changes in project structure and naming of projects and targets.



## Version 0.12.1 beta (2014-05-17)

### Enhancements

 - Class extension method `all:` now stores `nil` results as a `NSNull` object into the result array.



## Version 0.13.0 beta (2014-05-17)


### Enhancements

 - Merged Pull request.

 - Added extension class method `allSettled:`.



## Version 0.13.1 beta (2014-05-18)

### Changes

-  Class method `all:` and `allSettled:` now fulfill the returned promise with an empty `NSArray` if no promise are given, instead of rejecting the promise.


## Version 0.14.0 beta (2016-03-22)

### Minimum Deployment Versions  

 - MacOS X: 10.9
 - iOS: 8.0

 Note: RXPromise can still be build for iOS 7 if a static library target will be added to the project.
