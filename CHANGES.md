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


The advantage of an implicit concurrent execution context is, that handlers now do execute independently from each other, and will have to wait until one other handler is finished. This improves CPU utilization and is less prone to unwanted blocking.

Note though, that handler still SHOULD NOT perform lengthy tasks and SHOULD NOT block. If this is the case, the handler should be wrapped into an asynchronous task.


* Added new API:  

The `thenOn` property has been added which provides a means to explicitly specify where the handlers are executed.



