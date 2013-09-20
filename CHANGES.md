## This file describes API changes, new features and bug fixes on a high level point of view.

# RXPromise

### Version 0.1 beta (22.05.2013)

* Initial Version



### Version 0.2 beta (29.05.2013)

#### Changes

* Improved runtime memory requirements of a promise instance.


### Version 0.3 beta (30.05.2013)

#### Bug Fixes

* Fixed issue with dispatch objects becoming "retainabel object pointers. Compiles now for deployment targets iOS >= 6.0 and Mac OS X >= 10.8.


### Version 0.4 beta (31.05.2013)

#### Changes

* Added a method `bind` in the "Deferred" API.

`bind` can be used by an asynchronous result provider if it itself uses another asynchronous result provider's promise in order to resolve its own promise.

A `cancel` message will be forwarded to the bound promise.



### Version 0.4.1 beta (31.05.2013)

* Minor fixes in accompanying documents


### Version 0.4.2 beta (31.05.2013)

#### Bug Fixes

* Fixed bug in a macro used for source code compatibility for different OS versions. This should now definitely fix the OS version issue.


### Version 0.5 beta (1.06.2013)

#### Changes

* Created Library projects for Mac OS X (framework and static) and iOS (static)

The libraries require deployment target >= Mac OS X 10.7, respectively >= iOS 5.1

Due to moving the code into libraries, the logging mechanism became an implementation detail. Log level has been set to `DEBUG_LOGLEVEL_WARN` for Debug configurations - that is, only warning messages will be printed which may indicate an error somewhere. For Release configuration the debug log level has been set to `DEBUG_LOGLEVEL_ERROR`, which always means a really serious error.



### Version 0.5.1 beta (4.06.2013)

#### Bug Fixes

* Fixed Copy Header path for Mac OS X static library



### Version 0.6 beta (5.07.2013)

#### Changes 

* The implementation became more memory efficient. However, this required to use a standard container from the C++ standard library. This has the consequence, that an application which links against the static library or incorporates the sources directly need to link against the standard C++ library by adding the compiler option "-lc++" to the "Other Linker Flags" build setting. When linking against the framework, this setting is not required.


* Added a few samples to show some advanced use cases.


* Removed the "preliminary" API for the process handler. IMO, a process handler is not appropriate for a Promise - that may be moved to the asynchronous provider.


* A few new unit tests have been added to specifically test subtle edge-cases. The implementation appears to be quite stable and no failure could have been detected.


### Version 0.7 beta (6.08.2013)

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

* Fixed a bug in method bind, which errornously fulfilled the target promise if the other promise was rejected.



### Version 0.8 beta (08.09.2013)


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

 -  The logging feature - primarily a means for debugging and hunting subtle bugs - has been effectivel disabled by default. The verbosity of and the "severity" of the log messages will be controlled by the macro `DEBUG_LOG`. Unless it is defined in a build setting or elsewhere, `DEBUG_LOG` will be defined in RXPromise.mm such that only errors will be logged. Defining it to 2, 3, or 4 will increase the verbosity.


 -  A few typos have been fixed in code and README.md  (Contributed by Rob Ryan)



#### Bug Fixes

A Unit Test has been fixed which potentially has reported a false positve.


#### Misc:

 Fixed a spurious Static Analyser warning.



### Version 0.8.3 beta (13.09.2013)


#### Changes

Added a "How To Install" section in the README.md file.



### Version 0.9 beta (2013-09-20)


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
