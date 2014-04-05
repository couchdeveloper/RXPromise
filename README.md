# RXPromise

A thread safe implementation of the Promises/A+ specification in Objective-C with extensions.


## **Important Note:**
 > There are breaking changes since version 0.11.0 beta.
 > Minimum deployment version on Mac OS X is now 10.8
 > Please read the [CHANGELOG](CHANGELOG.md) document.


### A Brief Feature List:


 - Employs the asynchronous "non-blocking" style.
 
 - Supports continuation.
 
 - Supports cancellation.
 
 - Simplifies error handling through error propagation.

 - `RXPromise` objects are thread safe.

 - Handlers can execute on diverse execution contexts, namely `dispatch_queue`, `NSThread`, `NSOperationQueue` and `NSManagedObjectContext`.

 - RXPromise objects are lightweight.
 


### Credits

`RXPromise` has been inspired by the  [Promises/A+](https://github.com/promises-aplus/promises-spec) specification which defines an open standard for robust and interoperable implementations of promises in JavaScript.

Thus, much of the credits go to their work and to those smart people they based their work on!

### How to Install
For install instructions, please refer to: [INSTALL](INSTALL.md)


## Contents

 1. [Introduction](#introduction)
  2. [What is a Promise](#what-is-a-promise)
  2. [Why Do We Need Promises](#why-do-we-need-promises)
 3. [Understanding Promises](#understanding-promises)
  1. [The Resolver Aspect](#the-resolver-aspect)
  2. [The Promise Aspect](#the-promise-aspect)
 1. [Using a Promise at the Resolver Site](#using-a-promise-at-the-resolver-site)
  1.  [The Asynchronous Task's Responsibility](#the-asynchronous-tasks-responsibility)
 2. [Using a Promise at the Call Site](#using-a-promise-at-the-call-site)
 1. [Chaining](#chaining)
 2. [The Execution Context](#the-execution-context)
 1. [Error Propagation](#error-propagation)
 1. [Controlling the Handler's Paths](#controlling-the-handlers-paths)
 1. [Starting Parallel Tasks](#starting-parallel-tasks)
 1. [Cancellation](#cancellation)
 1. [Synchronization Guarantees For Shared Resources](#synchronization-guarantees-for-shared-resources)



-----
## Introduction

### What is RXPromise

In general, a promise represents the _eventual result_  of an asynchronous task,  respectively the _error reason_ when the task fails. Equal and similar concepts are also called _future_, _deferred_ or _delay_ (see also wiki article: [Futures and promises](http://en.wikipedia.org/wiki/Futures_and_promises)). 

The `RXPromise` implementation strives to meet the requirements specified in the [Promises/A+ specification](https://github.com/promises-aplus/promises-spec) as close as possible. The specification was originally written for the JavaScript language but the architecture and the design can be implemented in virtually any language.

A `RXPromise` employs the asynchronous non-blocking style. That is, a call site can invoke an _asynchronous_ task which _immediately_ returns a `RXPromise` object. For example, an asynchronous network request:

```Objective-C
    RXPromise* usersPromise = [self fetchUsers];
```
    
The asynchronous method `fetchUsers` returns immediately, and its _eventual_ result is represented by the _promise_.

The call site can setup a _Continuation_ - which defines how to proceed when the result or the error is eventually available:

    
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

A _Continuation_ for a promise will be established via the `then` property and defining two handlers: the _completion handler_ and the _error handler_.
    
**A Continuation:**

 >   `then(<completion-handler>, <error-handler>)`
   
The _completion handler_ has a parameter _result_ of type `id`. This value is the _eventual result_  of the promise, which has been evaluated by the asynchronous task associated to this promise.

The _error handler_  has a parameter _error_ of type `NSError*`. An error handler "catches" the error reason from this promise or any other error "thrown" from a "previous" continuation which has not been "caught" by a "previous" error handler.

A Continuation can also be registered with the `thenOn`  and `thenOnMain` property.

> A more thorough explanation of the "Continuation" and its handles is given in chapter [Understanding Promises](#understanding-promises).

`RXPromise`'s principal methods are all *asynchronous and thread-safe*. That means, a particular implementation utilizing `RXPromise` will resemble a purely *asynchronous* and also *thread-safe* system, where no thread is ever blocked. (There are a few exceptions where certain miscellaneous methods *do* block).

In addition to the requirements stated in the Promise/A++ specification the `RXPromise` library contains a number of useful extensions. For example, it's possible to specify the *execution context* of the completion and error handler which helps to synchronize access to shared resources. This execution context can be a `dispatch_queue`, a `NSThread`, a `NSOperationQueue` or a `NSManagedObjectContext`.

Additionally, `RXPromise` supports *cancellation*, which is invaluable in virtual every real application. 

The library also provides a couple of useful helper methods which makes it especially easy to manage a list or a group of asynchronous operations. 


[Contents ^](#contents)

### Why Do We Need Promises?

Unquestionable, our coding style will become increasingly asynchronous. The Cocoa API already has a notable amount of asynchronous methods which provide completion handlers and also has numerous frameworks which support the asynchronous programming style through the delegate approach.

However, getting _asynchronous_ problems right is hard, especially when the problems get more complex. 

With Promises it becomes far more easy to solve asynchronous problems. It makes it straightforward to utilize frameworks and APIs that already employ the asynchronous style. A given implementation will look like it were _synchronous_, yet the solution remains completely _asynchronous_. The code also becomes concise and - thanks to Blocks - it greatly improves the locality of the whole asynchronous problem and thus the code becomes comprehensible and easy to follow for others as well.


### A Non-trivial Example

Suppose, our objective is to implement the task described in the six steps below:

1. Asynchronously perform a login for a web service.
2. Then, if that succeeded, asynchronously fetch a list of objects as `JSON`.
3. Then, if that succeeded, parse the `JSON` response.
4. Then, if that succeeded, create managed objects from the JSON and save them asynchronously to the persistent store, using a helper method `saveWithChildContext:` (see below).
5. Then, if this succeeded, update the UI on the main thread. 
6. Catch any error from above steps.

** The implementation looks as follows:**

Suppose, we have implemented the following _asynchronous_ methods utilizing `RXPromise`:

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
  

Suppose, for managing a persistent store, we utilize Core Data. Suppose we have a class `CoreDataStack`, which has a "main context" executing on the main thread, whose parent is the "root context" running on a private queue with a backing store. For this example, we only require one method
as described below:

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

Then, the following _single statement_ asynchronously performs these six steps:
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
.thenOn(dispatch_get_main_queue(), ^id(id result){
    // Update our UI
    self.objects = [Object allInManagedObjectContext:self.coreDataStack.mainContext];
    [self.tableView reloadData];
    return @"OK";
}, nil)
.then(nil, ^id(NSError* error){
    // If something went wrong in any of the above four steps, the error 
    // will be propagated down and "caught" in this error handler:
    NSLog(@"Error: %@", error);
    return nil;
});

```

The above code is a single yet complex statement which is itself asynchronous and which is composed of several asynchronous tasks forming a _chain of continuations_. 

The control and data flow should be easily recognizable: the steps are performed from top to bottom. We start with an asynchronous method and setup a continuation, that is, register a completion and an error handler, with using `then(<completion-handler, error-handler>)`.

We can also see, that a handler can be `nil`. Frequently, only the completion handler is set, while the error handler is `nil`. Only at the very bottom there is a continuation with a singly error handler.

A handler can execute any statements, but it must return a result. This result can be an "immediate" value like an  `NSArray` or `@"OK"`, or `nil.` Or it may signal an error through returning an `NSError` object. Or, the handler may execute an _asynchronous_ task and returning the task's _promise_. 

A continuation - whether it was for an asynchronous task returning a promise or whether it was an immediate value - will be setup with a subsequent `then`,  `thenOn` or `thenOnMain` and defining a completion and error handler. A handler is optional, but it makes sense to define at least one for a continuation.

The return value of a handler will "appear" as the parameter of the  handler of the continuation (either as the _result_ in the completion handler or the error reason in the error handler).

When the handler returns a promise, the subsequent continuation (either the completion or error handler) will be called only after the promise has been resolved. The completion handler will be passed the _result value_ of the handlers task, the error handler will be passed the _error reason_ (an `NSError` object).

The _final_ result of the whole chain of tasks is represented through the promise `fetchAndSaveObjects`.

If any of the asynchronous tasks fails or if any handler returns an `NSError` object, that error will be _propagated_ "downwards" and caught by the next registered error handler. Since only the completion handler OR the error handler of a continuation will be called, this also implies that when an error is "thrown", the subsequent completion handlers will NOT be invoked. This behavior is similar to `try/catch`.

The final promise can also be used to _cancel_ the whole chain of tasks at any point and at any time. For more information on canceling a promise see [Cancellation](#cancellation)

In the next chapters we take a more thorough look at promises.


[Contents ^](#contents)

----------
## Understanding Promises

As already mentioned, a promise _represents_ the _eventual_ result of an asynchronous task. There is the _caller_  (or call-site) of the asynchronous task which is interested in the eventual result, and there is the _asynchronous task_ which evaluates this value. Both communicate through the promise object.

So, a promise has _two_ distinct aspects where we can look at it. The one side is the "Promise API" used by the _call-site_, the other side is the "Resolver API" used by the underlying task. 

For each aspect there are corresponding APIs defined in class `RXPromise`.

### The Resolver Aspect

The promise will usually be created by the underlying task. Initially, the promise is in the state "pending". That means, the result is not yet available. This promise will be immediately returned to the call-site.

> The promise will be created by the underlying asynchronous task. The initial state of this promise is _pending_. 

The underlying task can create and return its promise whose state is "pending" easily:

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

```objective-c
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

The resolver API it's usage is defined in more detail in [Using a Promise at the Resolver Site](#using-a-promise-at-the-resolver-site)

[Contents ^](#contents)

### The Promise Aspect

On the other hand, the call-site wants to handle the eventual result and continue the program once the result is available. 

> The call-site registers handlers in order to obtain the eventual result or error of the underlying task and continue with the program.

In order to achieve this, it uses the `then` and the `thenOn` properties which will be explained in short, but to better understand promises which will be used by the call-site, we first take a look at a corresponding _asynchronous_ method:

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

At the first glance we cannot see how we would obtain the result and continue with the program when the asynchronous method finished, and how we would handle a possible error. But, no worry, this is all possible with the returned promise: The "continuation" will be defined by means of the promise, namely through the `then` and `thenOn` properties and _registering handlers_.

> The call-site obtains the _eventual_ result or the _error reason_ from the underlying asynchronous task through _registering_ a completion handler respectively an error handler.

[Contents ^](#contents)

#### Defining a Continuation with Completion and Error Handler

The [Promises/A+ specification](https://github.com/promises-aplus/promises-spec) proposes to use the `then` method in order to specify the _continuation_ . The Continuation has two "handlers", the _completion handler_ and the _error handler_.

In the `RXPromise` library we have three variants to establish a Continuation, `then`, `thenOn` and `thenOnMain`. These are actually _properties_ of class `RXPromise`. How these are defined is explained in more detail later. For now, we only need to know how to _use_ them, which is illustrated below:

The first form: 

> `then(<completion-handler>, <error-handler>)`

```objective-c
promise.then(^(id result){
    ...
    return completion_result;
}, ^id(NSError* error){
    ...
    return error_result;
});
```

The second form

> `thenOn(<execution-context>, <completion-handler>, <error-handler>)`
 
allows us to _explicitly_ specify an _execution context_ where the handler - either the completion handler or the error handler will be executed on:

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

The third form: 

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


The role of an execution context is explained later in more detail in chapter [The Execution Context](#the-execution-context).

> In `RXPromise` the _Continuation_  of an asynchronous task will be defined with:
>
* `then(<completion-handler>, <error-handler>)`  or
* `thenOn(<execution-context>, <completion-handler>, <error-handler>)`
* `thenOnMain(<completion-handler>, <error-handler>)`

Both, completion handler and error handler are _Blocks_. Handlers can be `nil`. In fact, both can be `nil` - but that wouldn't make much sense.



As we can see, each handler takes a parameter and returns a value.

The completion handler takes a parameter `result` of type `id `. This _result_ is identical the eventual result of the underlying task of the _same_ promise where the handler has been registered.

> The completion handler has a parameter which is the eventual result of the task associated to the promise.

The underlying task SHOULD specify and document what exactly the type of its result is. Furthermore, it should also specify what potentially can go wrong.

Then moreover, the error handler takes an `NSError` parameter. An error handler basically catches _any_  uncaught error "thrown" from a _previous_ task or handler which has been executed in the same "chain" (a previous continuation or the root method). Errors will be handled like it takes place in a `try/catch` clause.

> The error handler takes an `NSError` as parameter. An error handler catches any uncaught error "thrown" from any _previous_ task or handler which has been executed within the _chain of continuations_.

In `RXPromise`, errors occuring in handlers will be signaled to the call-site through simply returning an `NSError` object. An asynchronous tasks signals an error through _rejecting_ their promise with an error reason. 

**Caution:**
> As usual in Objective-C, throwing exceptions using the keyword `throw` or `@throw` or using the method `raise:` are not appropriate to signal errors to a call site. In fact, throwing an exception from within a handler will lead to a crash. 

See also chapter [Error Propagation](error-propagation).

Note that either the completion _or_ the error handler (if not `nil`) will be _eventually_ called, since the underlying task MUST eventually _resolve_ its promise: that is, if the task succeeded, the completion handler will be called (if defined) and if the task failed, the error handler (if defined) will be called.

> Either the completion handler _or_ the error handler (if defined) will eventually be called. 

Both handlers shall return a value. This returned value is the result of the _handler_. The handler may even invoke another asynchronous method, which itself returns a promise and return that promise. This idiom is actually quite common, and the standard way to define a "chain of asynchronous tasks". 

In certain circumstances, a handler may run into an erroneous situation and want to signal this to the call-site, instead to continue. In this case, the handler simply returns an `NSError` object, describing the details of the failure.

If the handler doesn't produce a meaningful or useful result, it should return `nil` - or perhaps something like @"OK" or @"Finished". Returning `nil` will not be considered a failure.

> Handlers SHALL always return a _value_. The value can be any object, e.g. `@"OK"`, a `RXPromise` or an `NSError` or `nil`. The only means to signal a failure during execution of the handler is through returning an `NSError` object.

The signature of both handlers is described in detail in [The Principal API of the Promise](the_principal_api_of_the_promise).


Now, invoking the underlying task and registering handlers can be written in a more concise way:

```objective-c
[self fetchUsersWithParams:params]
.then(^(id result){
    ...
    return nil;
}, ^id(NSError* error){
    ...
    return nil;
});
```

Method `fetchUsersWithParams:` is supposed to return a new promise. This "returned promise" will usually be _created_ by the underlying _asynchronous task_ - an "asynchronous result provider" and then immediately returned to the client. 

#### Chaining a series of asynchronous tasks

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


#### Creating a Promise

A promise - more precisely, the _root promise_ - will usually be created by the "asynchronous task" or an helper method wrapping this task object. And usually, *initially* a promise is in the _pending_ state. There are however situations where it makes sense to create an already resolved promise. `RXPromise` provides suitable APIs for these usage scenarios.

The method `init` will create a "pending" promise. So, mostly an asynchronous tasks would create a promise like this:

```Objective-C
     RXPromise* promise = [[RXPromise alloc] init];
```

An _resolved_ promise can be created using class convenience method `promiseWithResult:`. Whether the promise becomes _fulfilled_ or _rejected_ depends on the kind of parameter: if the parameter is a kinf of `NSError`, it will be rejected, otherwise it will be fulfilled:

```Objective-C
    RXPromise* fulfilledPromise = [RXPromise promiseWithResult:@"OK"];
    
    RXPromise* rejectedPromise = [RXPromise promiseWithResult:error];
```

#### Resolveing a Promise

When the "asynchronous result provider" eventually succeeds or fails it MUST _resolve_ its associated promise. "Resolving" is either _fulfilling_ or _rejecting_ the promise with it's corresponding values, either the final result or an error.

That means, in order to resolve the promise when the task succeeded the asynchronous task must send the promise a `fulfillWithValue:` message whose parameter will be the result of the asynchronous function. 

```Objective-C
    [promise fulfillWithValuet:@"OK"];
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

The error reason "should" be an descriptive `NSError` object. However, we can use a short form as well:

```Objective-C
if ([users count] == 0) {
    [promise rejectWithReason:@"there are no users"];
}
```    
Here, `rejectWithReason:` will inernally create an `NSError` object with domain `@"RXPromise"` and error code -1000, with a `userInfo` dictionary setup as follows:

 `userInfo = @{NSLocalizedFailureReasonErrorKey: reason ? reason : @""};`


#### Forwarding Cancelation

A returned promise can be cancelled from elsewhere at any time. 

Now, IFF the underlying asynchronous task is _cancelable_ we SHOULD also prepare for a _cancelation_ of the _returned promise_ and then _forward_ the cancel message to the underlying asynchronous task, for example sending it a `cancel` message.

This can be easily accomplished through setting up a continuation with an error handler for the returned promise which performs the cancelation of the asynchronous task.

An example how an asynchronous method could be implemented which uses a subclass of a `NSOperation` as the underlying "asynchronous result provider" is illustrated below:

```objective-c
- (RXPromise*) doSomethingAsync
{
    RXPromise* promise = [[RXPromise alloc] init];
    MyOperation* op = [MyOperation alloc] initWithCompletionHandler: ^(id result){
        [promise fulfillWithValue:result];
    } 
    errorHandler:^(NSError* error){
        [promise rejectWithReason:error];
    }];

    [self.queue addOperation:op];
    
    // Foward Cancelation: Cancel the operation if the returned promise 
    // has been cancelled:
    promise.then(nil, ^id(NSError*error){
        [op cancel];
        return nil;
    });
    
    return promise;
}
```
 **Note:**

Since the underlying task is a subclass of `NSOperation` which is _cancelable_, the method `doSomethingAsync` sets up a continuation with an error handler. This error handler will be called when the call-site cancels the promise, or when the asycnhronous task fails. As an effect, the operation will receive a `cancel` message as well. Should the operation fail and the operation's completion handler reject its promise, this "cancel" handler will also be called - but it will have no effect on the operation since it is already finished. We can be more restrictive in taking actions through inspecting the error properties and the promise' state.





[Contents ^](#contents)

-------
## Using a Promise at the Call Site

As already described in [Understanding Promises](#understanding-promises) a call site can obtain the result of the asynchronous task and continue the execution when the task is finished through setting up a _continuation_:

`then(<completion-handler>, <error-handler>)` and
`thenOn(<execution-context>, <completion-handler>, <error-handler>)`

Suppose, we have an asynchronous network request which return a JSON (array of users):

```objective-c
- (RXPromise*) fetchUsers;
```

We can define the continuation as shown below:

```objective-c
[self fetchUsers].then(^id(id json){
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

### The Return Value of a Handler


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



#### A particular Promise can have more than one Continuation:

A promise can register _more_ than one handler pairs. All the respective handlers will eventually be called when the promise has been resolved (fulfilled _or_ rejected).

For example:
```Objective-C
RXPromise* promise = [self doSomethingAsync];

promsise.then(completion_handler1, nil);
promsise.then(completion_handler2, nil);
promsise.then(completion_handler3, nil);
```
Here, we have three Continuations, each defining a completion handler. When the promise will be _fulfilled_ all three completion handlers will be started in _parallel_. The _execution context_ where the handlers will execute will define their concurrency with respect to each other. In the example above, the execution context is a private concurrent queue, that is the handlers will actually run in parallel. See also [Execution Context](#execution-context).

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



### The _thenOn_ and _then_ Property

 A "consumer" (or client) of the result of an asynchronous function may or may not keep a reference to the promise which the function returns. In any case, the client can specify callback handlers (blocks) which will be invoked when either the promise has been fulfilled or rejected. This will be accomplished with the property `thenOn` and `then`.

As shown already, property `thenOn` and `then` returns a _block_ - which is quite unusual for a property. Since a block can be _called_ when applying the "invoke operator" (this is simply the function-call like syntax), we have a short hand for invoking the block that will be returned from a property. Remember the declaration of the `thenOn` property:

```objective-c
    @property then_on_t thenOn;
```

And the signature of the returned block was:

`typedef RXPromise* (^then_on_t)(id executionContext, completionHandler_t onSuccess, errorHandler_t onError);`


Given an object of type `RXPromise` _promise_, we could now _call_ the block whatever the promise's property `thenOn` returns:

```objective-c
    promise.thenOn( ... );
```

We know, that this block requires three parameters (while `then` requires two parameters). The first parameter _queue_ of the returned block from property `thenOn` is the _execution context_ of the handlers. This is a _dispatch queue_ which shall be defined by the call site to define _where_ the handlers shall be executed.

The _onSuccess_ and _onError_ parameters are blocks, and their signature has already been given above.

The `then_on_t` respectively the `then_t` block's return value is a promise, a _new_ promise - and often referred to the "returned promise" in the documentation.

```objective-c
    id completionHandler = ^id(id result) { ...; return something; }
    id errorHandler = ^id(NSError* error) { ...; return error; }

    RXPromise* nextPromise = promise.then(completionHandler, errorHandler);
```

And shorter in a hopefully comprehensible way:

```objective-c
    RXPromise* nextPromise = promise
    .thenOn(dispatch_get_main_queue(), ^id(id result) {
        ...;
        return something;
    },
    ^id(NSError* error{
        ...;
        return error;
    });
```

That means, when sending a given promise the `thenOn` or `then` message the execution of the returned block will create and return a new promise.

In a more intuitively example:

    RXPromise* newPromise = promise.thenOn(queue, onSuccess, onError);


The very first promise, the "root promise", should be obtained from an asynchronous service provider, for example:

```objective-c
    RXPromise* rootPromise = [self doSomethingAsync];
```

The method `doSomethingAsync` will start an asynchronous task and then immediately return a promise.



The client may now define what shall happen _when_ this asynchronous method succeeds or _when_ it fails through defining the corresponding handler blocks as shown above. The handler blocks may be `NULL` indicating that no action is to be taken.


[Contents ^](#contents)


-----
## The Principal API of the RXPromise Class

The API has two parts: one for the "asynchronous service provider" and one for the consumer of the task's result, the "client".


```objective-c
/**
 Promise Client API
*/

@interface RXPromise : NSObject
@property (nonatomic, readonly) then_on_t   thenOn;
@property (nonatomic, readonly) then_t      then;
@end
```

 The value of the property `thenOn` is a _block_ having three parameters. The first parameter specifies the _execution context_ where the handlers are executed. The second is the _completion handler_ and the third is the _error handler_. The handlers are itself blocks. 
 
 **Note**
 >The _execution context_ specifies where the handler gets executed. It can be a `dispatch_queue`, a `NSThread`, a `NSOperationQueue` or a `NSManagedObjectContext`.
 
 > If no execution context is specified or if it is `nil` the handler will execute on a private concurrent dispatch queue.

 The value type of the property `then` is the same as above, except that it omits the explicit execution context for handlers. Here, the _implicit_ execution context is a _concurrent queue_.
 
The signatures are defined below:


```objective-c
typedef id (^completionHandler_t)(id result);
typedef id (^errorHandler_t)(NSError* error);

typedef RXPromise* (^then_on_t)(id, completionHandler_t, errorHandler_t);
typedef RXPromise* (^then_t)(completionHandler_t, errorHandler_t);
```

 One very important fact is that the return value of the block, which is the value of the property `thenOn` respectively `then` is again a promise. This enables to _chain_ promises. Chaining asynchronous tasks will be explained in more detail below in section "Chaining".
 


The part interfacing to the service provider is also often called "Deferred":

```objective-c
/**
 Promise Deferred API
*/

@interface RXPromise(Deferred)
- (id)init;
- (void) fulfillWithValue:(id)result;
- (void) rejectWithReason:(id)error;
@end
```

[Contents ^](#contents)


----
## Chaining  

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
Note that in the concise form above, we only obtain the promise of the _final_ result of the whole chain. We do not explicitly obtain intermediate promises. These do exist, though, as anonymous temporaries.

The _root promise_ of any child promise can can be obtained via property `root`:

```Objective-C
RXPromise* root = child2.root;
```

The _parent promise_ of a promise can be obtained via property `parent`:

```Objective-C
RXPromise* child1 = child2.parent;
```

#### A non-trivial example:


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

[Contents ^](#contents)

----
## The Execution Context

Where the handlers will finally execute on is specified through the _execution context_. 

#### Types of Execution Contexts

In `RXPromise`, handler can execute on the following types of execution contexts:

 - `dispatch_queue`, 
 - `NSThread`, 
 - `NSOperationQueue` and 
 - `NSManagedObjectContext`.

#### Unspecified Execution Context

Using the `then` property to setup a Continuation, e.g.:

> `then(<completion-handler>, <error-handler>)`, 

the execution context is not specified. In this case, the handler will execute on a _private concurrent dispatch queue_. More precisely, the handler will be dispatched via `dispatch_async()` on a _concurrent_ queue. Thus, handlers of different continuations executing on an unspecified execution context may execute in _parallel_ and no synchronization guarantees can be made.


#### Explicit Execution Context

As already mentioned in brief earlier, when setting up a continuation, with the second form "`thenOn`" or the third form "`thenOnMain`" we explicitly specify an execution context:

With `thenOn` we can specify any valid execution context

> `thenOn(<execution-context>, <completion-handler>, <error-handler>)`, 

and with 

> `thenOnMain(<completion-handler>, <error-handler>)`, 

we specify the main thread. The third form is funcional equivalent to 
`thenOn(dispatch_get_main_queue(), <completion-handler>, <error-handler>)`.

In the example below, we setup a continuation which executes the handler on the main queue:

```Objective-C
promise.thenOn(dispatch_get_main_queue(), ^(id result){
    // executing on the main thread
    ...
    return nil;
}, ^id(NSError* error){
    // executing on the main thread
    ...
    return nil;
});
```






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
        root.then(^id(id result){
            ...
            return nil;
        }, nil);
        root.then(^id(id result){
            ...
            return nil;
        }, nil);
```

In the code snippet above the "root promise" will be obtained first and a reference is kept.
The root promise will invoke several `then` blocks  - each returning a promise, which are not used in this sample, though.

The effect of this is that once the root promise has been resolved, as the result of taskA is available, it _concurrently_ executes all four handlers. These handlers may start an asynchronous task or return an immediate value. 

If those handlers access shared resources we MUST be worried about concurrent access! In order to synchronize concurrent access to a shared resource we can explicitly specify the execution context of the handlers for example by setting a dedicated serial queue:

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



With this design it is possible to define even _complex trees_ of tasks in a concise way. Since access of shared resources can be made safe from within handlers, setting up complex composed tasks with access to shared resources becomes quite easy.


Furthermore, it's also possible to "hook" into a promise with a handler from anywhere and anytime. Just establish a Continuation with the `thenOn`, `thenOnMain` or `then` property and define handlers. If the promise is already resolved, the handler will just execute immediately, with the same concurrency guarantees.

[Contents ^](#contents)

------
## Cancellation

Occasionally, it is required to _cancel_ a _certain_ task, a _certain chain_ of tasks, or a _certain branch_ of a tree of tasks, or everything that belongs to the root promise. No matter, whether that task is already started or not yet started, or even when it is already finished - in which case it shall have no effect.

RXPromise provides a cancellation mechanism which will perform exactly what one would intuitively think it should do:

A promise will respond to a `cancel` message. If it is in state pending, it will resolve itself with a cancel signal and also forward the cancel message to all subsequent tasks. These tasks will be in the pending state as well and they just forward the cancel message as its parent promise did.

If the promise is already resolved, it will forward the cancel message to its children promises, which may or may not already resolved.

A promise never _backwards_ a cancel message. That is, if you cancel the last task in a chain, only the last task will be cancelled and all others in the chain will proceed and run up to this task.


That way, it's possibly to _selectively_ cancel a chain, part of a chain in direction to the leave, or branches, etc.


A asynchronous service provider should - if it supports cancellation at all - add an error handler to the promise which it creates and possibly check for cancellation and then take appropriate actions, for example cancel itself:

```objective-c
- (RXPromise*) doSomethingAsync
{
    RXPromise* promise = [[RXPromise alloc] init];

    MyOperation* op = [MyOperation alloc] initWithCompletionHandler: ^(id result){
        [promise fulfillWithValue:result];
    } 
    errorHandler:^(NSError* error){
        [promise rejectWithReason:error];
    }];
    

    promise.then(^id(NSError* error){
        if (promise.isCancelled) {
            [op cancelWithReason:error];
        }
        return error;
    });

    [self.queue addOperation:op];
    
    return promise;
}
```



[Contents ^](#contents)

----
## Synchronization Guarantees For Shared Resources

All methods of `RXPromise` are fully thread-safe. There are no restrictions *when* and *where* an instance or class method will be executed.

However, one needs to take care about when accessing shared resources in the handler blocks:

When using the `then` property in order to register the completion and error handler block, the execution context where the handler will be eventually executed is *private*. That means, the thread where the block gets executed is implementation defined. In fact,
`RXPromise` will use a private _concurrent_ execution context. 

From this it follows, that if the the `then` property is used for registering handlers, handlers will execute _concurrently_ and concurrent access to shared resources from within handlers is not automatically guaranteed to be thread-safe.


#### Making access to shared resources thread-safe

Concurrent access to shared resources can be made easily thread-safe from within handlers when the execution context (a dispatch queue) will be *explicitly* specified through the `thenOn` or then `thenOnMain` property:

    [self doSomethingAsync].thenOn(dispatch_queue, completion_block, error_block);

The dispatch queue `dispatch_queue` specifies where the handler block will be executed. The queue *can* be a *serial* or a *concurrent* dispatch queue. When it is a serial queue, the handler block will automatically ensure thread-safety when *all* accesses to this shared resource will be executed using that queue. This *MUST* also include all accesses which are not performed from within promise handlers.


**Note:** 

> `RXPromise` assumes *write* access to shared resources in its handlers.

Using a *concurrent* dispatch queue requires more attention. `RXPromise` makes the assumption that a *write* access will be performed within a handler to a hypothetical shared resource. Now, when the queue is *concurrent* this requires a *barrier* in order to guarantee thread-safety. Thus, `RXPromise` will invoke the handler using function `dispatch_barrier_async`. 

When a handler is about to be invoked which has been registered with the `thenOn` property which explicitly specifies a dispatch queue, `RXPromise` effectively executes the following:

```objective-c
if ([result isKindOfClass:[NSError class]) {
   dispatch_barrier_async(queue, error_handler(result));
}
else {
   dispatch_barrier_async(queue, completion_handler(result));
}
```

**Note:** 

> `dispatch_barrier_async` guarantees that write accesses to shared resources are thread-safe.


While `dispatch_barrier_async` guarantees thread-safety for a *concurrent* queue, it has a minor penalty when the handler would only perform *read* accesses to a shared resource. If the specified queue is a serial queue, `dispatch_barrier_async` is effectively the same as `dispatch_async`.

  

[Contents ^](#contents)
