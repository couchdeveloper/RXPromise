# RXPromise

A thread safe implementation of the Promises/A+ specification in Objective-C with extensions.

If you like a more modern "Skala-like" futures and promise library implemented in Swift, you may look at [FutureLib](https://github.com/couchdeveloper/FutureLib).


## **Important Note:**
 > For breaking changes and API extensions please read the [CHANGELOG](CHANGELOG.md) document.


### A Brief Feature List:


 - Employs the asynchronous "non-blocking" style

 - Supports chained continuations

 - Supports cancellation

 - Simplifies error handling through error propagation

 - Thread-safe implementation

 - Handlers can execute on diverse execution contexts, namely `dispatch_queue`, `NSThread`, `NSOperationQueue` and `NSManagedObjectContext`.

 - `RXPromise` objects are lightweight.



### Credits

`RXPromise` has been inspired by the  [Promises/A+](https://github.com/promises-aplus/promises-spec) specification which defines an open standard for robust and interoperable implementations of promises in JavaScript.

Much of the credits go to their work and to those smart people they based their work on!

### How to Install
For install instructions, please refer to: [INSTALL](INSTALL.md)


## Contents

 1. [Introduction](#introduction)
  2. [What is a Promise](#what-is-a-promise)
  2. [Where Can We Use Promises](#where-can-we-use-promises)
  2. [A Non-Trivial Example](#a-non-trivial-example)
 1. [Understanding Promises](#understanding-promises)
  2. [The Resolver Aspect](#the-resolver-aspect)
  2. [The Promise Aspect](#the-promise-aspect)
 1. [Using a Promise at the Resolver Site](#using-a-promise-at-the-resolver-site)
  2.  [The Asynchronous Task's Responsibility](#the-asynchronous-tasks-responsibility)
  2.  [Creating a Promise](#creating-a-promise)
  2.  [Resolving a Promise](#resolving-a-promise)
  2.  [Forwarding Cancellation](#forwarding-cancellation)
 1. [Using a Promise at the Call-Site](#using-a-promise-at-the-call-site)
  2.  [Defining a Continuation](#defining-a-continuation)
  2.  [A Continuation Returns a Promise](#a-continuation-returns-a-promise)
  2.  [Chaining](#chaining)
  2.  [Branching](#branching)
  2.  [The then, thenOn and thenOnMain Property](#the-then-thenon-and-thenonmain-property)
 1. [The Execution Context](#the-execution-context)
 1. [Error Propagation](#error-propagation)
 1. [Cancellation](#cancellation)



-----
## Introduction

### What Is A Promise

In general, a promise represents the _eventual result_  of an asynchronous task,  respectively the _error reason_ when the task fails. Equal and similar concepts are also called _future_, _deferred_ or _delay_ (see also wiki article: [Futures and promises](http://en.wikipedia.org/wiki/Futures_and_promises)).

The `RXPromise` implementation strives to meet the requirements specified in the [Promises/A+ specification](https://github.com/promises-aplus/promises-spec) as close as possible. The specification was originally written for the JavaScript language but the architecture and the design can be implemented in virtually any language.

**Asynchronous non-blocking**

A `RXPromise` employs the asynchronous non-blocking style. That is, a call-site can invoke an _asynchronous_ task which _immediately_ returns a `RXPromise` object. For example, starting an asynchronous network request:

```Objective-C
RXPromise* usersPromise = [self fetchUsers];
```

The asynchronous method `fetchUsers` returns immediately and its _eventual_ result will be represented by the _returned_ object, a _promise_.

Given a promise, a call-site can obtain the result respectively the error reason and define _how_ to continue with the program _when_ the result is available through "registering" a _Continuation_.

Basically, a "Continuation" is a completion handler and an error handler, which are blocks providing the result respectively the error as a parameter. Having a promise, one or more continuations can be setup any time.

Registering a continuation will be realized with one of three properties of `RXPromise`: `then`, `thenOn` or `thenOnMain`, and providing the definitions of the handler blocks:

```Objective-C
usersPromise.then(^id(id result){
    NSLog(@"Users: %@", result);
    return nil;
},
^id(NSError* error){
    NSLog(@"Error: %@", error);
    return nil;
});
```

A more thorough explanation of the "Continuation" is given in chapter [Understanding Promises](#understanding-promises) and [Using a Promise at the Call-Site](#using-a-promise-at-the-call-site).

**Thread-Safety**

`RXPromise`'s principal methods are all *asynchronous and thread-safe*. That means, a particular implementation utilizing `RXPromise` will resemble a purely *asynchronous* and also *thread-safe* system, where no thread is ever blocked. (There are a few exceptions where certain miscellaneous methods *do* block).

**Explicit Execution Context**

The _Execution Context_ defines where the continuation (more precisely, the completion handler or the error handler) will finally execute on. When setting up a continuation for a `RXPromise` we can explicitly specify the execution context using the `thenOn` and the `thenOnMain` property. The execution context is used to ensure concurrency requirements for shared resources which will be accessed concurrently in handlers and from elsewhere. The execution context can be a dispatch queue, a `NSOperationQueue`, a `NSThread` or even a `NSManagedObjectContext`.

See also [The Execution Context](#the-execution-context).

**Cancellation**

Additionally, `RXPromise` supports *cancellation*, which is invaluable in virtual every real application.
For more details about _Cancellation_ please refer to chapter [Cancellation](#cancellation).

**Set of Helper Methods**

The library also provides a couple of useful helper methods which makes it especially easy to manage a list or a group of asynchronous operations. Please refer to the source documentation.



[Contents ^](#contents)

### Where Can We Use Promises?

Unquestionable, our coding style will become increasingly asynchronous. The Cocoa API already has a notable amount of asynchronous methods which provide completion handlers and also has numerous frameworks which support the asynchronous programming style through the delegate approach.

However, getting asynchronous problems _right_ is hard, especially when the problems get more complex.

With Promises it becomes far more easy to solve asynchronous problems. It makes it straightforward to utilize frameworks and APIs that already employ the asynchronous style. A given implementation will look like it were _synchronous_, yet the solution remains completely _asynchronous_. The code also becomes concise and - thanks to Blocks - it greatly improves the locality of the whole asynchronous problem and thus the code becomes comprehensible and easy to follow for others as well.


### A Non-trivial Example

Imagine, our objective is to implement the task described in the six steps below:

1. Asynchronously perform a login for a web service.
2. Then, if that succeeded, asynchronously fetch a list of objects as `JSON`.
3. Then, if that succeeded, parse the `JSON` response in a background thread.
4. Then, if that succeeded, create managed objects from the JSON and save them asynchronously to the persistent store, using a helper method `saveWithChildContext:` (see below).
5. Then, if this succeeded, update the UI on the main thread.
6. Catch any error from above steps.

Suppose, we have already implemented the following _asynchronous_ methods:

In the View Controller:
```objective-c
/**
  Performs login on a web service. This may ask for user credentials
  in a separate UI.
  If the operation succeeds, fulfills the returned promise with @"OK",
  otherwise rejects it with the error reason (for example the user
  cancelled login, or the authentication failed on the server).
*/
- (RXPromise*) login;  

/**
  Perform a network request to obtain a JSON which contains "Objects".
  If the operation succeeds, fulfills the returned promise with a
  `NSData` object containing the JSON, otherwise rejects it with the
  error reason.
*/
- (RXPromise*) fetchObjects;
```

A real application would also use Core Data for managing a persistent store. Our "Core Data Stack" is quite standard having a "main context" executing on the main thread, whose parent is the "root context" running on a private queue with a backing store. Assuming this Core Data stack is already setup, we implement the following method:

```objective-c
/**
  Saves the chain of managed object contexts starting with the child
  context and ending with the root context which finally writes into
  the persistent store.
  If the operation succeeds, fulfills the returned promise with the
  childContext object, otherwise rejects it with the error reason.
*/
- (RXPromise*) saveWithChildContext:(NSManagedObjectContext*)childContext;
```

Having those methods, the following _single statement_ asynchronously executes the complex task defined in the six steps above:

```objective-c
RXPromise* fetchAndSaveObjects =
[self login]
.then(^id(id result){
    return [self fetchObjects];
}, nil)
.then(^id(NSData* json){
    NSError* error;
    id jsonArray = [NSJSONSerialization JSONObjectWithData:json
                                                   options:0
                                                     error:&error];
    if (jsonArray) {
        NSAssert([jsonArray isKindOfClass:[NSArray class]]); // web service contract
        return jsonArray;  // parsing succeeded
    }
    else {
        return error;      // parsing failed
    }
}, nil)
.then(^id(NSArray* objects){
    // Parsing succeeded. Parameter objects is an array containing
    // NSDictionaries representing a type "object".

    // Create managed objects from the JSON and save them into
    // Core Data:
    NSManagedObjectContext* moc = [[NSManagedObjectContext alloc]
                      initWithConcurrencyType:NSPrivateQueueConcurrencyType];
    moc.parentContext = self.coreDataStack.managedObjectContext;
    for (NSDictionary* object in objects) {
        // note: `createWithParameters:inManagedObjectContext` executes on
        // the context's queue
        [Object createWithParameters:object inManagedObjectContext:moc];
    }
    // Finally, asynchronously save the context to the persistent
    // store and return the result (a RXPromise):
    return [self.coreDataStack saveWithChildContext:moc];
}, nil)
.thenOnMain(^id(id result){
    // Update our UI
    self.objects = [Object allInManagedObjectContext:self.coreDataStack.mainContext];
    [self.tableView reloadData];
    return @"OK";
}, nil)
.then(nil, ^id(NSError* error){
    // If something went wrong in any of the above four steps, the error
    // will be propagated down and "caught" in this error handler.

    // Just log it to the console (we could show an alert view, or
    // display the error info in a status line, too):
    NSLog(@"Error: %@", error);

    // We return "nil" in order to indicate that we "handled" the error
    // and can proceed normally:
    return nil;
});
```

The above code is a single, yet complex statement which is itself asynchronous and which is composed of several asynchronous tasks forming a _chain of continuations_.

The control and data flow should be easily recognizable: the steps are performed from top to bottom. We start with an asynchronous method and setup a continuation, that is, register a completion and an error handler, with using `then(<completion-handler, error-handler>)`. We also see that a handler block can be `nil`.

The _final_ result of the whole chain of continuations is represented through the promise `fetchAndSaveObjects`.

If any of the asynchronous tasks fails or if any handler returns an `NSError` object, the error will be "caught" in the last continuation, which is the only continuation which defines an error handler.

The promise `fetchAndSaveObjects` can also be used to _cancel_ the whole process, or a selected "promise branch". Canceling a promise will also cancel its underlying asynchronous task (the task that created this promise) if "forward cancellation" is implemented in the task.

The cancellation feature of `RXPromise` enables fine grained control over which "promise branch" will be cancelled. For more details please see [Cancellation](#cancellation).

In the next chapters we take a more thorough look at promises.


[Contents ^](#contents)

----------
## Understanding Promises

As already mentioned, a promise _represents_ the _eventual_ result of an asynchronous task. There is the _caller_  (or call-site) of the asynchronous task which is interested in the eventual result, and there is the _asynchronous task_ which evaluates this value. Both communicate through the promise object.

So, a promise has _two_ distinct aspects where we can look at it. The one side is the "Promise API" used by the _call-site_, the other side is the "Resolver API" used by the underlying task.

For each aspect there are corresponding APIs defined in class `RXPromise`.

### The Resolver Aspect

The promise, more precisely the "root promise" will usually be created by the underlying task. Initially, the promise is in the state "pending". That means, the result is not yet available. This promise will be immediately returned to the call-site.

> The promise will be created by the underlying asynchronous task. The initial state of this promise is _pending_.

The underlying task will create and return its promise like shown below:

```objective-c
- (void) task {
    RXPromise* promise = [[RXPromise alloc] init];
    dispatch_async(queue, ^{
        // evaluate the result
        ...
    }
    return promise;
}
```

When the underlying task has eventually finished its work and has a result, it SHALL _fulfill_ its promise with that result. Otherwise, if the task failed, it SHALL _reject_ its promise with the failure reason. So, _resolving_ a promise is either _fulfilling_ or _rejecting_ *).

> The underlying task MUST eventually _resolve_ the promise. *)

Fulfilling or rejecting a promise can be accomplished as shown below:

```
objective-c
if (result) {
    [promise fulfillWithValue:result];
}
else {
    [promise rejectWithReason:error];
}
```

*) Here, we need to know that a promise can also be _cancelled_.  A `cancel` message can be send from anywhere. _Canceling_ is a special form of _rejecting_ a promise (see also [Cancellation](#cancellation)). Thus, a `cancel` message _can_ resolve a promise, too. Nonetheless, any asynchronous task returning a promise MUST implement the rule above. Especially, the `RXPromise` implementation _requires_ that a promise MUST eventually be resolved.


When a promise will be resolved, it's state advances from "pending" to either "fulfilled" or "rejected". Once a promise is resolved, further attempts to resolve it have no effect. That is, once a promise has been resolved, its result respectively its error reason and state cannot change anymore.

> A promise can be resolved only _once_ and it's state becomes either _fulfilled_ or _rejected_. After resolving a promise becomes immutable.

The principal API of the resolver will comprise a few methods:

```objective-c
- (instancetype)init;
- (void) fulfillWithValue:(id)value;
- (void) rejectWithReason:(id)reason;
```

The resolver API and it's usage is defined in more detail in [Using a Promise at the Resolver Site](#using-a-promise-at-the-resolver-site)

[Contents ^](#contents)

### The Promise Aspect

On the other hand, the call-site wants to handle the eventual result and continue the program once the result is available.

In order to achieve this, we use the `then`, `thenOn` or `thenOnMain` properties which will be explained in short. To better understand promises which will be used by the call-site, we first take a look at a corresponding _asynchronous_ method:

**Asynchronous method with completion handler:**

```objective-c
typedef void (^completion_t)(NSArray* users, NSError* error);

-(void) fetchUsersWithParams:(NSDictionary*)params
                  completion:(completion_t)completion;
```

The completion handler must be _defined_ by the _call-site_. A _completion_ handler is also called the "continuation". The "continuation" is simply the code that shall be executed once the underlying task is finished.

The underlying task, on the other hand, is responsible to eventually _call_ the completion handler (once it is finished) and passing the result respectively the error to the completion handler. At the call-site, the program then "continues" with the code defined in the completion handler.

For example:

```objective-c
[self fetchUsersWithParams:params
                completion:^(NSArray* users, NSError*error){
    if (users) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.users = users;
            [self.tableView reloadData];
        });
    }
    else {
        NSLog(@"Error: %@", error);
    }
}];
```
The corresponding asynchronous method with a Promise will look as follows:

**Asynchronous style with Promise:**

```objective-c
-(RXPromise*) fetchUsersWithParams:(NSDictionary*)params;
```

This method returns a `RXPromise` object, but there is no parameter for the completion handler. Since it is asynchronous, the `RXPromise` object will be returned _immediately_.

The returned promise represents the _eventual_ result of the underlying task. Immediately after return, this promise is (most likely) not yet "resolved", that means, the underlying task is still busy evaluating the result.

At the first glance we cannot see how we would obtain the result and continue with the program when the asynchronous method finished, and how we would handle a possible error. But, no worry, this is all possible with the returned promise:

The [Promises/A+ specification](https://github.com/promises-aplus/promises-spec) proposes to use the `then` method in order to specify the _Continuation_ . The continuation has two "handlers", the _completion handler_ and the _error handler_.

That is, the "continuation" will be defined by means of the promise. In `RXPromise` we have three variants, namely the `then`, `thenOn` respectively the `thenOnMain` property in order to establish a continuation and define the completion handler and the error handler.

Given the expression `[self fetchUsersWithParams:params]` returns a promise, the example above may look as follows:

```
[self fetchUsersWithParams:params]
.thenOnMain(^id(id result{
    // result is an NSArray representing a JSON Array containing Users
    self.users = result;
    [self.tableView reloadData];
    return nil;
}, ^id(NSError* error){
    NSLog(@"Error: %@", error);
    return nil;
});
```

> The call-site registers a _Continuation_  through the property `then`, `thenOn` or `thenOnMain` and defines completion handler and error handler in order to obtain the eventual result or error of the underlying task and continue with the program. This is called a _Continuation_.

The following chapters will go into detail how to use a `RXPromise`.


[Contents ^](#contents)



-----

## Using a Promise at the Resolver Site

The relevant API for the asynchronous task are just these methods:

```objective-c
- (instancetype)init;
- (void) fulfillWithValue:(id)result;
- (void) rejectWithReason:(id)reason;
```

Additionally, there are a few convenience methods:

```objective-c
+ (instancetype) promiseWithResult:(id)result;
+ (RXPromise *)promiseWithTask:(id(^)(void))task;
+ (RXPromise *)promiseWithQueue:(dispatch_queue_t)queue task:(id(^)(void))task;
```


### The Asynchronous Task's Responsibility

An _asynchronous task_, possibly a `NSOperation` or some asynchronously dispatched block, is an object whose lifetime extends up to the point at which it has finished its task and has the result available.

Basically, the responsibility of the asynchronous are the following:

 * Create a promise in pending state
 * Resolve the promise in the asynchronous result provider
 * Optionally prepare for cancellation of the returned promise
 * Return the promise


### Creating a Promise

A promise - more precisely, the _root promise_ - will usually be created by the "asynchronous task" or a helper method wrapping this task object. And usually, *initially* a promise is in the _pending_ state. There are however situations where it makes sense to create an already resolved promise. `RXPromise` provides suitable APIs for these usage scenarios.

The method `init` will create a "pending" promise. So, mostly an asynchronous tasks would create a promise like this:

```Objective-C
     RXPromise* promise = [[RXPromise alloc] init];
```

A _resolved_ promise can be created using class convenience method `promiseWithResult:`. Whether the promise becomes _fulfilled_ or _rejected_ depends on the kind of parameter: if the parameter is a kind of `NSError`, it will be rejected, otherwise it will be fulfilled:

```Objective-C
    RXPromise* fulfilledPromise = [RXPromise promiseWithResult:@"OK"];

    RXPromise* rejectedPromise = [RXPromise promiseWithResult:error];
```

### Resolving a Promise

When the "asynchronous result provider" eventually succeeds or fails it MUST _resolve_ its associated promise. "Resolving" is either _fulfilling_ or _rejecting_ the promise with it's corresponding values, either the final result or an error.

That means, in order to resolve the promise when the task succeeded the asynchronous task must send the promise a `fulfillWithValue:` message whose parameter will be the result of the asynchronous function.

```Objective-C
    [promise fulfillWithValue:@"OK"];
```    

**Note:** The parameter _value_ may be _any_ object or `nil`, except an `NSError` object. Passing an `NSError` object as the _value_ parameter is undefined behavior.

Otherwise, if the asynchronous function fails, the asynchronous task must send the promise a `rejectWithReason:` message whose parameter will be the reason for the failure, possibly an `NSError` object.

For example:
```Objective-C
if ([users count] == 0) {
    [NSError errorWithDomain:@"User"
                        code:-100
                    userInfo:@{NSLocalizedFailureReasonErrorKey:@"there are no users"}];
    [promise rejectWithReason:error];
}
```    

The error reason "should" be a descriptive `NSError` object. However, we can use a short form as well:

```Objective-C
if ([users count] == 0) {
    [promise rejectWithReason:@"there are no users"];
}
```    
Here, `rejectWithReason:` will internally create an `NSError` object with domain `@"RXPromise"` and error code -1000, with a `userInfo` dictionary setup as follows:

 `userInfo = @{NSLocalizedFailureReasonErrorKey: reason ? reason : @""};`


### Forwarding Cancellation

A returned promise can be cancelled from elsewhere at any time.

Now, suppose the underlying asynchronous task is _cancelable_ we SHOULD also prepare for a _cancellation_ of the _returned promise_ and then _forward_ the cancel message to the underlying asynchronous task, for example sending it a `cancel` message.

This can be easily accomplished through setting up a continuation with an error handler for the returned promise which performs the cancellation of the asynchronous task.

An example how an asynchronous method could be implemented which uses a subclass of a `NSOperation` as the underlying "asynchronous result provider" is illustrated below:

```objective-c
- (RXPromise*) doSomethingAsync
{
    RXPromise* promise = [[RXPromise alloc] init];
    __weak RXPromise* weakPromise = promise;
    MyOperation* op = [MyOperation alloc] initWithCompletionHandler: ^(id result){
        [weakPromise fulfillWithValue:result];
    }
    errorHandler:^(NSError* error){
        [weakPromise rejectWithReason:error];
    }];

    [self.queue addOperation:op];

    // Forward cancellation: Cancel the operation if the returned promise
    // has been cancelled:
    promise.then(nil, ^id(NSError*error){
        [op cancel];
        return nil;
    });

    return promise;
}
```
**A few notes:**

This implementation avoids to _retain_ the returned promise through using a `__weak` qualified pointer which get captured in the completion handler of the asynchronous task. Using a `__weak` reference to the returned promise is generally a recommended practice. This style has a number of advantages in more sophisticated usage scenarios.

Since the underlying task is a subclass of `NSOperation` which is _cancelable_, the method `doSomethingAsync` sets up a continuation with an error handler. This error handler will be called when the call-site cancels the promise, or when the asynchronous task fails. As an effect, the operation will receive a `cancel` message as well. Should the operation fail and the operation's completion handler reject its promise, this "cancel" handler will also be called - but it will have no effect on the operation since it is already finished. We can be more restrictive in taking actions through inspecting the error properties and the promise' state.

In more sophisticated scenarios it makes sense to subclass a dedicated `RXPromise` for a particular class of asynchronous tasks, with the following behavior:


 - The RXPromise subclass is private and its API is only visible to its task
 - The subclass will have an ivar referencing its tasks and an init method taking the task as parameter.
 - The dealloc method of the subclass will send a cancellation message to the underlying task.
 - The `cancel` method is overridden which forwards the cancellation to the task (which in turn will cancel the promise)


With this subclass and assuming the task only weakly references the returned promise, we can accomplish that the task will be "automatically" cancelled if there are no "subscribers" of the returned promise, that is, one or potentially several clients did cancel their promise returned from registering a continuation on the root promise and got deallocated.

This is especially useful in more complex usage scenarios where a potentially heavy and long running task with potentially several observers should be cancelled - but only if there is no observer anymore interested in the result of the task.





[Contents ^](#contents)

-------
## Using a Promise at the Call-Site

As already described in [Understanding Promises](#understanding-promises) a call-site can obtain the result of the asynchronous task and continue the execution when the task is finished through setting up a _continuation_:

**Continuation:**

`then(<completion-handler>, <error-handler>)`
`thenOn(<execution-context>, <completion-handler>, <error-handler>)`
`thenOnMain(<completion-handler>, <error-handler>)`

A continuation consists of the _completion handler_ , the _error handler_ and an _execution context_. It will be registered for a promise using the `then`, `thenOn` or `thenOnMain` property.

The handlers can be `nil`, however it makes sense to have at least one handler defined in a particular continuation.

The execution context defines where the handlers get executed on. It can be a dispatch queue, a `NSThread`, a `NSOperationQueue` or a `NSManagedObjectContext`.
The execution context can be implicit (using `then`) or explicit (using `thenOn` or `thenOnMain`).

The role of the _execution context_ will be explained in more detail in [The Execution Context](#the-execution-context).

### Defining a Continuation


In the `RXPromise` library we have three forms to establish a continuation, with using either the `then`, `thenOn` or the `thenOnMain` property.  How these properties are implemented is explained in more detail later. For now, we only need to know how to _use_ them, which is illustrated below:

#### The first form:

> `then(<completion-handler>, <error-handler>)`

Example:
```objective-c
promise.then(^(id result){
    // do something with the result
    return completion_handler_result;
}, ^id(NSError* error){
    // do something with the error
    return error_handler_result;
});
```
Either the completion _or_ the error handler will be called when the promise has been _resolved_. Here, the handler will execute on a private _execution context_. :


#### The second form

> `thenOn(<execution-context>, <completion-handler>, <error-handler>)`

allows us to _explicitly_ specify an _execution context_ where the handler - either the completion handler _or_ the error handler will be executed on:

```objective-c
dispatch_queue_t sync_queue = dispatch_queue_create("sync_queue", 0);
promise.thenOn(sync_queue, ^(id result){
    // executing on the "sync_queue"
    ...
    return completion_result;
}, ^id(NSError* error){
    // executing on the "sync_queue"
    ...
    return error_result;
});
```

#### The third form:

> `thenOnMain(<completion-handler>, <error-handler>)`

is just a convenience way for executing on the main thread. It is functional equivalent to:
`thenOn(dispatch_get_main_queue(), <completion-handler>, <error-handler>)`


```objective-c
promise.thenOnMain(^(id result){
    // executing on the main thread
    ...
    return completion_result;
}, ^id(NSError* error){
    // executing on the main thread
    ...
    return error_result;
});
```


The role of the _execution context_ is explained later in more detail in chapter [The Execution Context](#the-execution-context).

> In `RXPromise` the _Continuation_  of an asynchronous task will be defined with:
>
* `then(<completion-handler>, <error-handler>)`  or
* `thenOn(<execution-context>, <completion-handler>, <error-handler>)`
* `thenOnMain(<completion-handler>, <error-handler>)`

Both, completion handler and error handler are _Blocks_. Handlers can be `nil`. In fact, both can be `nil` - but that wouldn't make much sense.



As we can see, each handler takes a parameter and returns a value.

----
#### A Continuation can be setup any time and anywhere

For example, given a promise which we obtained somewhere earlier starting a network request, we can "observe" it in a view controller and setup a continuation:

```Objective-C
- (void) viewDidAppear:(BOOL)animated
    if (self.model.fetchAllUsersPromsise && !self.busyIndicator.isAnimating) {
        [self.busyIndicator startAnimating];
        self.model.fetchAllUsersPromise.thenOn(dispatch_get_main_queue(),
        ^(id result){
            [self.busyIndicator stopAnimating];
            return nil;
        }, ^id(NSError*error){
            [self.busyIndicator stopAnimating];
            return nil;
        });
    }
    [super viewDidAppear:animated];
}
```


----
#### The Completion Handler

The completion handler is a Block with the following signature:

```
id (^completion_handler_t)(id result);
```

The completion handler has a parameter _result_ of type `id` and returns a value of type `id`.

**Note:** The completion handler will only be called with a _non-NSError_ object, or possibly `nil` as parameter.

If the associated promise has been created by an asynchronous task (that is, it's a "root promise") the parameter _result_ is identical the eventual result of the underlying task.

Otherwise, the completion handler's result parameter is identical to the _return value_ of the previous continuation. It doesn't matter whether this was the completion handler or the error handler - the respective handler simply returned a non-NSError object which will be passed through to this completion handler.

The previous handler may also return a promise. In this case, this completion handler will be called when the promise gets fulfilled, and the parameter _result_ contains the _eventual_ result of the fulfilled promise.

> The completion handler has a parameter _result_ of type `id`. When called, _result_ is either the eventual result of the task associated to the promise (if any), otherwise it's the returned value of the previous continuation.

The underlying task SHOULD specify and document what exactly the type of its result is. Furthermore, it should also specify what potentially can go wrong.

----

#### The Error Handler

The error handler is a Block with the following signature:

```
id (^error_handler_t)(NSError* error);
```

The error handler takes an `NSError` parameter and returns a value of type `id`.

In a promise, errors will be "propagated" through to subsequent continuations in the chain, until there is a continuation with a specified error handler.

This means, when an error handler will be called, it's parameter _error_ is the error returned from its asynchronous task (if any), or otherwise it's an error or the error reason from a _rejected_ promise that has been returned in a previous continuation of this chain.

We might say, an error handler "catches" an uncaught error "thrown" from  its task or a previous continuation in the same "chain". Effectively, errors will be handled like it takes place in a `try/catch` clause.

> The error handler takes an `NSError` as parameter. It "catches" an error "thrown" from its task (if any), or otherwise an error from a previous continuation.

In `RXPromise`, errors occurring in handlers will be signaled to the call-site through simply returning an `NSError` object. An asynchronous tasks signals an error through _rejecting_ their promise with an error reason.

**Caution:**
> As usual in Objective-C, throwing exceptions using the keyword `throw` or `@throw` or using the method `raise:` are not appropriate to signal errors to a call-site. In fact, throwing an exception from within a handler will lead to a crash.

See also chapter [Error Propagation](#error-propagation).

Note that either the completion _or_ the error handler will be _eventually_ called (if defined), since the underlying task MUST eventually _resolve_ its promise: that is, if the task succeeded, the completion handler will be called (if defined) and if the task failed, the error handler will be called, if defined. Otherwise if the error handler is `nil` the error will be propagated through to the next continuation and handled there. If there is no error handler defined in this continuation, it will be propagated to the next continuation (if any), and so force.

> Either the completion handler _or_ an error handler (if defined) will eventually be called.

----
#### The Return Value of a Handler

Both, completion handler and error handler shall return a value. This returned value is the result of the _handler_. The handler may even invoke another asynchronous method, which itself returns a promise and return that promise. This idiom is actually quite common, and the standard way to define a "chain of asynchronous tasks".

> **Handlers Shall Return a Value**


In certain circumstances, a handler may run into an erroneous situation and want to signal this to the call-site, instead to continue. In this case, the handler simply returns an `NSError` object, describing the details of the failure.

If the handler doesn't produce a meaningful or useful result, it should return `nil` - or perhaps something like @"OK" or @"Finished". Returning `nil` will not be considered a failure.

> Handlers SHALL always return a _value_. The value can be any object, e.g. `@"OK"`, a `RXPromise` or an `NSError` or `nil`. The only means to signal a failure during execution of the handler is through returning an `NSError` object.

The signature of both handlers is described in detail in [The **_then_**, **_thenOn_** and **_thenOnMain_** Property](#the-then-thenon-and-thenonmain-property).



#### A handler may return an _immediate_ result:
An _immediate_ result, is an non-promise object.

```objective-c
.then(^id(id users){
    User* user = users[0];
    return user;  // return the first user
}, nil)
```
If the returned value is NOT an error, the returned object will become the _result_ parameter of the handler of the next continuation (if any).


#### A handler may return a promise:

```objective-c
-(RXPromise*) saveUsers:(NSArray*) users;

...
.then(^id(id users){
    return [self saveUsers:users];
}, nil)
```
If the returned promise will be _fulfilled_, the promise's result will become the _result_ parameter of the handler of the next continuation (if any).
Otherwise, if the promise will be _rejected_ the error will _propagated_ downwards up until it will be _caught_ from an error handler.


#### A completion handler may signal an error through returning an `NSError`:

```objective-c
.then(^id(id users){
    if (![users count]) {
        return [NSError errorWithDomain:@"User"
                                code:-100
                            userInfo:@{NSLocalizedFailureReasonErrorKey:@"users is empty"}];
    }
    return users[0];
}, nil)
```
If the returned object is an `NSError`, the error will _propagated_ downwards up until it will be _caught_ from an error handler.



#### An error handler may "handle" the error and signal to proceed "normally":

```objective-c
.then(nil,  ^id(NSError* error){
    return @"OK";
}, nil)
```


#### Usually, a handler returns `nil` if the returned promise is not used anymore:
```objective-c
.then(nil, ^id(NSError* error){
    NSLog(@"Error: %@", error);
    return nil;
}); // last continuation
```

[Contents ^](#contents)

-----


### A Continuation Returns a Promise


What's not immediately obvious is the fact that the expression
```
then(...,...)
```
also returns a promise.

Suppose we have an asynchronous method:

```
- (RXPromise*) fetchUsers;
```

we can setup a continuation like

```
[self fetchUsers].then(..., ...)

```
and the above expression returns a promise which represents the _return value_ of the respective _handler_ that get called when the promise returned from `[self fetchUsers]` will be resolved (calls either the completion _or_ the error handler):
```
RXPromise* finalResultPromise = [self fetchUsers]
.then(^id(id result){
    ...
    return final_result;
}, ^id (NSError* error){
    ...
    return final_result;
});
```

**Caution:** Here, the promise returned from `[self fetchUsers]` is an "unnamed temporary". It's not `finalResultPromise`!

The promise created by an asynchronous task is also called "root promise". A root promise has no parent promise, that is, it was not created as the effect of adding a continuation.

On the other hand, the promise returned from the expression, for example:
```
[self fetchUsers].then(..., ...)
```
will be a "child promise", whose "parent" is the "root promise".


One great feature of promises is, that they are "composable". That means, it is possible to "chain" several asynchronous task: The first task asynchronously calculates a result, which will be used as the input of the next task, which itself asynchronously calculates a result which will be the input of the third task, and so force:
```Objective-C
[self taskA]
.then(^id(id resultA){
    return [self taskB:resultA]
}, nil)
.then(^id(id resultB){
    return [self taskC:resultB]
}, nil)
```

Chaining asynchronous tasks is described in detail in chapter [Chaining](#chaining).

[Contents ^](#contents)


----
### Chaining  

One substantial feature of promises is that they can be "chained": The first asynchronous task asynchronously calculates a result, which will be used as the input of the second task, which itself asynchronously calculates a result which will be the input of the third task, and so force.

Technically, "chaining" has been accomplished through making the expressions

 `then(<completion-handler>, <error-handler>)`  and
 `thenOn(<execution-context, <completion-handler>, <error-handler>)`

itself returning a promise:
```Objective-C
RXPromise* root = asyncA();
RXPromise* child1 = root.then(completion1, nil),
RXPromise* child2 = child1.then(completion2, nil),
```
Now, `root` is the _parent_ of `child1`, and `child1` is the _parent_ of `child2`, forming a "chain of promises".

Chaining in a more concise way:

```Objective-C
RXPromise* child2 = root()
.then(completion1, nil)
.then(completion2, nil);
```
In the concise form above, we only obtain the promise of the _final_ result of the whole chain. We do not explicitly obtain intermediate promises. These do exist, though, as anonymous temporaries.

We can even omit to keep a reference to the final promise `child2` if we don't want to precede with another continuation, or don't want to hold that promise in case we want cancel it from elsewhere:

```
root()
.then(completion1, nil)
.then(completion2, nil);
```
In this even more concise form above, we don't explicitly hold a "named" promise - we simply define continuations. Nonetheless, we can be assured, that the continuations will eventually be called - even if we don't have a promise object representing the final result.

Note also that function `root()` - or its underlying asynchronous task - will create and return a promise, representing the asynchronous task's result. The task is responsible to resolve it _eventually_.



The _root promise_ of any child promise can can be obtained via property `root`:

```Objective-C
RXPromise* root = child2.root;
```

The _parent promise_ of a promise can be obtained via property `parent`:

```Objective-C
RXPromise* child1 = child2.parent;
```

#### A Simple Example:

Suppose, we have an asynchronous network request which return a JSON (array of users):

```objective-c
- (RXPromise*) fetchUsers;
```

We can define the continuation as shown below:

```objective-c
[self fetchUsers]
.then(^id(id json){
    // parse the JSON
    NSError* error;
    id jsonArray = [NSJSONSerialization JSONObjectWithData:json
                                                   options:0
                                                     error:&error];
    if (jsonArray) {
        return jsonArray;  // handler succeeded
    }
    else {
        return error;      // handler failed
    }
}, nil)
.then(nil, ^id(NSError* error){
    NSLog(@"Error: %@", error);
    return nil;
});
```

Here, we have actually _two_ continuations, the latter being just there to handle an error. It's recommend practice to have a last continuation which handles potential errors.

It's not necessary to handle errors in _each_ continuation. Handling an error only makes sense IFF there is something which we want to do with an error at this particular continuation - for example, potentially resolve some kind of error and then proceed normally without an error. If we can't resolve this particular error, we then just return the original one.


#### A Non-Trivial Example:

This is a classic form of  chained continuations where the result of the previous task is passed as the input of the next task:

```objective-c
RXPromise* endResult = [self asyncA]
.then(^id(id resultA) {
    return [self asyncB:resultA];
}, nil)
.then(^id(id resultB) {
    return [self asyncC:resultB];
}, nil)
.then(^id(id resultC) {
    return [self asyncD:resultC];
}, nil)
.thenOn(dispatch_get_main_queue(),^id(id result) {
    NSLog(@"Result: %@", result);
    return result;
}, ^id(NSError* error) {
    NSLog(@"ERROR: %@", error);
    return error;
});
```
The code above chains four asynchronous tasks A, B, C and D and then a last one which returns an _immediate_ result. The result of a task will be used as the input of the task invoked in the completion handler in its continuation.


The first promise which has no parent promise, will be obtained through invoking the first asynchronous task via `[self asyncA]`. The return value - a promise, whose parent is the root promise - will be immediately used to define the handlers via the `then` property whose completion handler just invokes the next asynchronous task `asyncB`:

```objective-c
[self asyncA]
.then(^id(id resultA) {
    return [self asyncB:resultA];
}, nil)
```

Here, when task A finishes successful, the final result of task A will be passed as the parameter `resultA` to the completion handler, which in turn passes the result to task B in order to asynchronously compute another result.

When task B completes, its final result will be passed to the next completion handler and so force - up until there is no handler anymore.

The last `thenOn` eventually handles the result returned from task D - by simply logging the result to the console. Here, the execution context has been explicitly defined. That is, the handler executes on the specified queue - the main queue in the example.

At the end of the statement, promise _endResult_ will be the promise returned from the _last_ `thenOn`. When all tasks have been finished successfully, the _endResult_'s `value` will become the return value of the last completion handler - which is actually the result of the last task D.

If any of the tasks failed, _endResult_'s `value` will be the return value of the last error handler, which is also the error reason of the failing task. See more about [Error Propagation](#error-propagation)


Notice, that the statement will execute completely asynchronous! Yet, effectively, they will be invoked one after the other.



[Contents ^](#contents)

----
### Branching

A particular Promise can have _more_ than one continuation. This simply means, that one would want to start more than one handler at the same time when a certain promise gets resolved. This leads to a "branch" with a "base promise" and one or more "children promises".

For example, given an asynchronous task returning a root promise:
```Objective-C
RXPromise* rootPromise = [self doSomethingAsync];

RXPromise* childPromise1 = rootPromsise.then(completion_handler1, nil);
RXPromise* childPromise2 = rootPromsise.then(completion_handler2, nil);
RXPromise* childPromise3 = rootPromsise.then(completion_handler3, nil);
```

When `rootPromise` will be resolved, _all three_ continuations will be invoked simultaneously which in turn calls the handlers `completion_handler1`, `completion_handler2` and `completion_handler2`.

Since in this example the execution context where the handlers do execute on has not been explicitly specified, they actually execute on a private concurrent dispatch queue, that is, they execute in _parallel_.

One could control the "concurrency" between the handlers through specifying a concrete dispatch queue, or `NSOperationQueue` or a `NSThread`, though. See also [Execution Context](#execution-context).

The "child promises" `childPromise1`, `childPromise2` and `childPromise3` do have the same parent promise: `rootPromise`.

The "child promises" `childPromise1`, `childPromise2` and `childPromise3` are "siblings" to each other.




----
### The **_then_**, **_thenOn_** and **_thenOnMain_** Property

This chapter focusses more on the implementation details of the properties `then`, `thenOn` and `thenOnMain`.

The `then`, `thenOn` and `thenOnMain` are _properties_ of class `RXPromise` which return a Block. The properties are declared as follows:

```objective-c
@property (nonatomic, readonly) then_block_t then;
@property (nonatomic, readonly) then_on_block_t thenOn;
@property (nonatomic, readonly) then_on_main_block_t thenOnMain;
```

The Blocks have a signature as shown below:

```objective-c
RXPromise* (^then_block_t)(completionHandler_t, errorHandler_t)
RXPromise* (^then_on_block_t)(id, completionHandler_t, errorHandler_t)
RXPromise* (^then_on_main_block_t)(completionHandler_t, errorHandler_t)
```

These properties return a _block_ - which is quite unusual for a property. Since a block can be _called_ when applying the "invoke operator" (this is simply the function-call like syntax), we have a short-hand for invoking the block that will be returned from a property, for example:


```objective-c
promise.then(completionHandler, errorHandler);
```

The completion handler and the error handler are Blocks, too. Its signature is shown below:

```objective-c
id (^completionHandler_t)(id result)
id (^errorHandler_t)(NSError* error)
```
That is, a handler takes a parameter and returns an object of type `id` (or `nil`).

Now, when defining these handlers "inline" we finally can setup a continuation in this concise way:

```objective-c
promise.then(^id(id result){
    ...
    return ...;
}, ^id(NSError*error){
    ...
    return ...;
});
```



Note also, that the expression `[promise.then(completionHandler, errorHandler)]` returns a new promise!

In a more intuitive example:

```objective-c
RXPromise* newPromise = promise.then(completionHandler, errorHandler);
```

`newPromise` is a child promise of `promise`. Likewise, the "parent" promise of `newPromise` is `promise`.  The value of `newPromise` is the value returned from either handler. Handlers may return a promise, in which case the eventual value of `newPromise` will become the eventual value of the returned promise.



The client may now define what shall happen _when_ this asynchronous method succeeds or _when_ it fails through defining the corresponding handler blocks as shown above. The handler blocks may be `nil` indicating that no action is to be taken.


[Contents ^](#contents)




----
## Error Propagation

In a chain of continuations, if any of the asynchronous tasks rejects its promise or if any handler returns an error, the error will be *propagated downwards* up to a continuation which implements an error handler. That error handler "catches" the error and possibly handles it. The completion handlers will not be called.

An error handler may "rethrow" the error by simply returning it. Then, the error again gets propagated downwards the continuations up until the next error handler catches it.

Alternatively, an error handler may "handle" the error and return any other object in order to continue "normally".

Consequently, it's not necessary to define error handlers, unless there is a compelling reason to "handle" the error and take some appropriate actions.

For example:

```objective-c
[self asyncA]
.then(^id(id result) {
     return [self asyncB:result];
}, nil)
.then(^id(id result) {
    return [self asyncC:result];
}, nil)
.then(^id(id result) {
    // ... do something with result
    return nil;
}, nil),
.then(nil, ^id(NSError* error) {
    // handle error
    return nil;
});
```

In the above chain of continuations, only the last continuation handles the error. If an error occurs in either task A, B or C and the returned promise will be rejected, the error will be finally "caught" and handled in the last continuation.

See also [The Error Handler](#the-error-handler).

[Contents ^](#contents)

----
## The Execution Context

> The _execution context_ specifies where the handlers will execute on.

All methods of `RXPromise` are fully thread-safe. There are no restrictions *when* and *where* an instance or class method will be executed.

However, one needs to take care about concurrency when accessing shared resources in the handler blocks:

When using the `then` property in order to register the completion and error handler block, the execution context where the handler will be eventually executed is *private*. That means, the thread where the block gets executed is implementation defined. In fact, `RXPromise` will use a private _concurrent_ execution context.

From this it follows, that if the `then` property is used for registering handlers, handlers will execute _concurrently_ and concurrent access to shared resources from within handlers is not automatically guaranteed to be thread-safe.



**Making access to shared resources thread-safe**

Concurrent access to shared resources can be made easily thread-safe from within handlers when the execution context will be *explicitly* specified through the `thenOn` or then `thenOnMain` property, for example:

```
dispatch_queue_t sync_queue = dispatch_queue_create("sync.queue", NULL);
[self doSomethingAsync].thenOn(sync_queue, completion_block, error_block);
```

Here, we used a dedicated _serial dispatch queue_ as execution context to specify _where_ the handler shall execute on. It is immediately obvious, that a *serial* queue will serialize access to shared resources, and thus concurrent access is safe. For a concurrent queue, the things are more complex, and will be explained in detail below.


In `RXPromise` we can not only use dispatch queues for the execution context, but there are these:

**Types of Execution Contexts**

In `RXPromise`, handler can execute on the following types of execution contexts:

 - `dispatch_queue`,
 - `NSThread`,
 - `NSOperationQueue` and
 - `NSManagedObjectContext`.


A dispatch queue *can* be a *serial* or a *concurrent* queue.





----


#### Unspecified Execution Context

Using the `then` property to setup a Continuation, e.g.:

> `then(<completion-handler>, <error-handler>)`,

the execution context is not specified by the client.

In this case, the handler will execute on a _private concurrent dispatch queue_. More precisely, the handler will be dispatched via `dispatch_async()` on a _concurrent_ queue. Thus, handlers of different continuations executing on an unspecified execution context may execute in _parallel_.

> Handlers executing on the private concurrent queue should not access shared resources, since no synchronization guaranties can be made.


#### Explicit Execution Context

As already mentioned in brief earlier, when setting up a continuation, with the second form "`thenOn`" or the third form "`thenOnMain`" we explicitly specify an execution context:

With `thenOn` we can specify any valid execution context

> `thenOn(<execution-context>, <completion-handler>, <error-handler>)`,

and with

> `thenOnMain(<completion-handler>, <error-handler>)`,

we specify the main thread. The third form is functional equivalent to
`thenOn(dispatch_get_main_queue(), <completion-handler>, <error-handler>)`.

In the example below, we setup a continuation which executes the handler on the main queue:

#### Executing on the Main Thread:

Accessing shared resources from the main thread in order guarantee thread-safety can be accomplished as follows:

```Objective-C
id sharedResource = ...;

promise.thenOn(dispatch_get_main_queue(), ^(id result){
    // executing on the main thread
    [sharedResource foo];
    return nil;
}, ^id(NSError* error){
    // executing on the main thread
    [sharedResource foo];
    return nil;
});
```
The functional equivalent alternative form is to use `thenOnMain`:

```Objective-C
id sharedResource = ...;

promise.thenOnMain(^(id result){
    // executing on the main thread
    [sharedResource foo];
    return nil;
}, ^id(NSError* error){
    // executing on the main thread
    [sharedResource foo];
    return nil;
});
```
`thenOnMain` is the preferred form to execute handlers on the main thread.

----

#### Executing on a Serial Dispatch Queue

In order to synchronize concurrent access to a shared resource we can explicitly specify the execution context of the handlers for example by setting a dedicated *serial* dispatch queue:

```objective-c
dispatch_queue_t sync_queue = dispatch_queue_create("sync.queue", NULL);

id sharedResource = ...;
root.thenOn(sync_queue, ^id(id result) {
    ...
    [sharedResource foo];
    return nil;
}, nil);
root.thenOn(sync_queue, ^id(id result) {
    ...
    [sharedResource foo];
    return nil;
}, nil);

```

Here, we have two continuations setup on one root promise. Those continuation start more or less simultaneously when the root promise gets resolved. Since the handlers will execute serialized on the specified dispatch queue, it guarantees that no data race occurs. Other clients may use the _same_ dispatch queue, without introducing concurrency issues.

With using explicit execution contexts it is possible to define even complex usage scenarios with various synchronization requirements. Since access of shared resources can be made safe from within handlers, setting up complex composed tasks with access to shared resources becomes straight forward.


Remember, that it's also possible to "hook" into a promise with a handler from anywhere and anytime. Just establish a continuation with the `thenOn` or `thenOnMain` property and define handlers and the execution context. If the promise is already resolved, the handler will just execute immediately with the same concurrency guarantees.

----

#### Executing on a Concurrent Dispatch Queue
Using a *concurrent* dispatch queue requires more attention. Still, `RXPromise` guarantees thread-safety to a certain degree:

`RXPromise` makes the assumption that a *write* access will be performed within a handler to a hypothetical shared resource.

> `RXPromise` assumes *write* access to shared resources in its handlers.

For example:
```objective-c
dispatch_queue_t sync_queue = dispatch_queue_create("sync.queue", DISPATCH_QUEUE_CONCURRENT);

id sharedResource = ...;
root.thenOn(sync_queue, ^id(id result) {
    ...
    [sharedResource foo];
    return nil;
}, nil);
root.thenOn(sync_queue, ^id(id result) {
    ...
    [sharedResource foo];
    return nil;
}, nil);

```


Now, when the queue is *concurrent* this requires a *barrier* in order to guarantee thread-safety. Thus, `RXPromise` will invoke the handler using function `dispatch_barrier_async`.

`RXPromise` effectively executes the following:

```objective-c
if ([result isKindOfClass:[NSError class]) {
   dispatch_barrier_async(queue, error_handler(result));
}
else {
   dispatch_barrier_async(queue, completion_handler(result));
}
```

Due to this, handlers executing on a concurrent dispatch queue will properly take care of shared resources. However, other clients using the same concurrent dispatch queue may not.

> `dispatch_barrier_async` guarantees that write accesses to shared resources are thread-safe.

While `dispatch_barrier_async` guarantees thread-safety for a *concurrent* queue, it has a minor penalty when the handler would only perform *read* accesses to a shared resource.


----
#### Executing on the Private Concurrent Queue:

When setting up a continuation using `then` the handlers will execute on a private concurrent dispatch queue.

```objective-c
RXPromise* root = taskA();

root.then(^id(id result){
    ...
    return nil;
}, nil);

root.then(^id(id result){
    ...
    return nil;
}, nil);

```
In the code snippet above the "root promise" will be obtained first and a reference is kept. The root promise has setup two continuations, whose handler run on the private concurrent queue.

The effect of this is that once the root promise has been resolved, as the result of taskA is available, it _concurrently_ executes all continuations. It's not shown what the handlers do, but in particular, they SHALL not access shared resources.



[Contents ^](#contents)


#### Executing on a NSOperationQueue:

A `NSOperationQueue` can be operated in two modes: as a _serial_ queue, or as a _concurrent_ queue whose number of concurrently executed operations can be set.

Generally, when specifying a `NSOperationQueue` which operates _concurrently_, no synchronization guarantees can be made. Otherwise, if the operation queue is serial the same rules as for a serial dispatch queue apply.

For example, thread-safe access:
```objective-c
NSOperationQueue sync_queue = [[NSOperationQueue alloc] init];
[sync_queue setMaxConcurrentOperationCount:1];  // make it serial

id sharedResource = ...;
root.thenOn(sync_queue, ^id(id result) {
    ...
    [sharedResource foo];
    return nil;
}, nil);
root.thenOn(sync_queue, ^id(id result) {
    ...
    [sharedResource foo];
    return nil;
}, nil);

```



#### Executing on a `NSThread`

Specifying a `NSThread` object as execution context requires that this thread has a Run Loop.
TBD

#### Executing on the private queue of a `NSManagedObjectContext`

`RXPromise`'s continuations can execute on the private queue of a `NSManagedObjectContext`. A small example demonstrates this feature:

Here, we assume there is a "Core Data Stack", which has a "root context" associated with a persistent store and executing on a private queue, and a "main context" executing on the main thread and whose parent context is the "root context".

The code sample first creates a child managed object context based on the main context executing on a private queue. Then it creates a new managed object into this new context. When this succeeded, it fetches all managed objects into this context:
```Objective-C
    // Create a new managed object context executing on a private queue and whose
    // managed object context will be a child of the main context of the core
    // data stack:
    NSManagedObjectContext* context = [self.coreDataStack newManagedObjectContextWithConcurrencyType:NSPrivateQueueConcurrencyType];

    // Obtain parameters for initializing a User object:
    NSDictionary* userParams = ...;   // obtain parameters

    // Create and register a managed object of type User with that managed
    // object context:
    [User createWithParameters:user inManagedObjectContext:context];
    // Note: `createWithParameters:inManagedObjectContext` implementation ensures
    // that the managed object will be modified running on the execution context
    // associated to the managed object context!

    // Save the context chain and when finished, fetch all Users into the
    // same context:
    [[self.coreDataStack saveContextChainWithContext:context]
     .thenOn(context, ^id(id result) {
        NSFetchRequest* fetchRequest = [[NSFetchRequest alloc] initWithEntityName:@"User"];
        NSError* error;
        NSArray* users = [context executeFetchRequest:fetchRequest error:&error];
        if (users) {
            ...
            return @"OK";
        }
        else {
            return error;
        }
    },nil)
```

The code snippet above asynchronously executes core data methods on their associated execution context suitable for their concurrency policy.

Internally, `RXPromise` will use `performBlock:` in order to execute the handler block.


> **Caution:**

> The NSManagedObjectContext must be created with either `NSPrivateQueueConcurrencyType` or `NSMainQueueConcurrencyType`.

> "Thread confinement", (e.g. `NSConfinementConcurrencyType`) is not yet supported.


[Contents ^](#contents)



------
## Cancellation

Occasionally, a client of a certain promise wants to abandon its interest in the result, before the underlying task resolved it. For that purpose, two cancel methods exists:

```
- (void) cancel;
- (void) cancelWithReason:(id)reason;
```




For example, a View Controller starts a network request in its `viewWillAppear:` method, and assigns this promise an ivar:

```
- (void) viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.fetchUsersPromise = [self fetchUsersWithParams:params];
    self.fetchUsersPromise
    .thenOnMain(^id(id result){
        self.users = result;
        self.fetchUsersPromise = nil;
        [self.tableView reloadData];
        return nil;
    }, ^id(NSError*error){
        NSLog(@"Error: %@", error);
        self.fetchUsersPromise = nil;
        return nil;
    });
}
```

Now, the request is pending, but what shall we do when the user switches away from this view and the result is not strictly needed anymore? In this case, we could override the `viewDidDisappear:` method and implement as follows:

```
- (void) viewDidDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self.fetchUsersPromise cancel];
    self.fetchUsersPromise = nil;
}
```
When the underlying task implements [Forwarding Cancellation](#forwarding-cancellation) it also receives a cancellation message, and the network request stops.

In order to understand how cancellation is implemented in `RXPromise` one need to known the _relationships_ of promises.

As already mentioned in chapter [A Continuation Returns a Promise](#a-continuation-returns-a-promise), a promise may have a "parent" promise.

There's a property where we can obtain the _parent_ of a promise:

```
@property (nonatomic, readonly) RXPromise* parent;
```
`parent` may return `nil`, which means that the receiver is a "root promise".

A promise created by the underlying asynchronous task which is also responsible to _resolve_ this promise, will usually _not have_ a parent. This is called a "root promise".

> A "root promise" has no parent.

"Children promises" will usually be created when setting up _continuations_. Their parent will become the promise where the continuation has been registered:

```
RXPromise* childPromise = parent.then(..., ...);
assert(childPromise.parent == parent);
```
A chain of continuation will create the corresponding chain of parent, child and grand child promises:
```
RXPromise grandChildPromise = childPromise.then(..., ...);
assert(grandChild.parent == childPromise);
```

Since a particular promise may register for more than one continuation, it also has more than one children:

```
RXPromise* child1Promise = parent.then(..., ...);
RXPromise* child2Promise = parent.then(..., ...);
RXPromise* child3Promise = parent.then(..., ...);
```

`child1Promise`, `child2Promise` and `child3Promise` are _siblings_ who have the same parent promise `parent`.

Now, when we cancel a promise the following important rules apply:

>1. If a promise receives a `cancel` message it will send `cancel` to all its children, unless it is already cancelled.
1. Canceling a promise will not cancel its parent.

Since canceling a promise will cause it to send the cancel message to all its children, even if it is already resolved (that is fulfilled or rejected with a reason, but not cancelled), the cancellation will be forwarded to its children, and their children and so force.  But only promises which are not yet resolved get actually cancelled, that is their state  becomes rejected with a cancellation reason. Promises which are already fulfilled or rejected won't change their state.

Note though, the parent won't receive a cancel message.

The only means we really have to "navigate" the promise tree, is the property `parent`, and a convenience property `root`.
```
@property (nonatomic, readonly) RXPromise* parent;
@property (nonatomic, readonly) RXPromise* root;
```

Property `parent` will return `nil` if it is a root promise.

Property `root` walks up the parents until it finds the root promise and returns it. It returns `self`, if it doesn't have a parent, thus it is itself the root.

There is no property which returns the children of a promise, it's strictly not required.


With this knowledge, we can selectively cancel a certain "branch" of a promise tree, while we can leave the parent untouched, perhaps since there is another child which is a sibling to our promise that we cancel, and we want that sibling still receive the result.





[Contents ^](#contents)
