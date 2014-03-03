# RXPromise

A thread safe implementation of the Promises/A+ specification in Objective-C with extensions.



### Credits

RXPromise has been inspired by the  [Promises/A+](https://github.com/promises-aplus/promises-spec) specification which defines an open standard for robust and interoperable implementations of promises in JavaScript.

Thus, much of the credits go to their work and to those smart people they based their work on!

### How to Install
For install instructions, please refer to: [INSTALL](INSTALL.md)


## Contents

 1. [Overview](#overview)
 1. [The Principal API of the Promise](#the-principal-api-of-the-promise)
 1. [Asynchronous Service Provider's Responsibility](#asynchronous-service-providers-responsibility)
 1. [The _thenOn_ and _then_ Property](#the-thenon-and-then-property)
 1. [Chaining](#chaining)
 1. [Error Propagation](#error-propagation)
 1. [Controlling the Handler's Paths](#controlling-the-handlers-paths)
 1. [Starting Parallel Tasks](#starting-parallel-tasks)
 1. [Cancellation](#cancellation)
 1. [Synchronization Guarantees For Shared Resources](#synchronization-guarantees-for-shared-resources)



-----
## Overview

A _promise_ is a lightweight object which helps to solve asynchronous programming problems. A promise represents the _eventual result_ of an asynchronous operation. Equal and similar concepts are also called _future_, _deferred_ or _delay_. A more detailed introduction can be found in the wiki article: [Futures and promises](http://en.wikipedia.org/wiki/Futures_and_promises).

`RXPromise` strives to meet the requirements specified in the [Promises/A+ specification](https://github.com/promises-aplus/promises-spec) as close as possible. The specification was originally written for the JavaScript language but the architecture and the design can be implemented in virtually any language.

`RXPromise` implementation follows a "non-blocking" style. `RXPromise`'s principal methods are all *asynchronous and thread-safe*. That means, a particular implementation utilizing `RXPromise` will resemble a purely *asynchronous* and also *thread-safe* system, where no thread is ever blocked. (There are a few exceptions where certain miscellaneous methods *do* block).

In addition to the requirements stated in the Promise/A++ specification the `RXPromise` library contains a number of useful extensions. For example, it's possible to specify the execution context of the success and failure handler which helps to synchronize access to shared resources.

Additionally, `RXPromise` supports *cancellation*, which is invaluable in virtual every real application. And furthermore, there are a couple of helper methods which makes it especially easy to manage a list or a group of asynchronous operations. 


#### Why do we need promises?

Promises will be invaluable when dealing with *asynchronous* architectures which make the code effectively look like it were *synchronous*. 

When a synchronous function returns a *value*, an asynchronous function will return a *promise* whose value represents the eventual result of the asynchronous function (possibly an error, too):

**Synchronous style:**

    -(NSArray*) synchronousFetchUsersWithParams:(NSDictionary*)parameters error:(NSError**)error;


**Asynchronous style:**

    -(RXPromise*) fetchUsersWithParams:(NSDictionary*)parameters;

Assuming there is an underlying asynchronous task which actually performs and evaluates the result of the method, the synchronous method will *block* the current thread and put it into a suspended state until the result is available. Then the thread resumes and returns the result. 

In contrast, the asynchronous method will not block the current thread, instead it will return *immediately* - yet the *actual* result is not yet available. The _eventual result_ will be represented by the promise.

The result can be obtained by "registering" success respectively failure handlers:

**Obtaining the eventual result:**

Registering the handlers will be achieved with the `then` respectively the `thenOn` property:

`promise.then(<success_handler>, <error_handler>);`

The *success handler* has a parameter `result` of type `id` which will be passed through and which is the actual result value of the asynchronous task.

Naturally, the *error handler* has a parameter `error` of type `NSError*` which contains the error returned by the asynchronous task when it failed.

For example:

    promise.then(^(id result){
        ...
        return nil;
    }, ^id(NSError* error){
        ...
        return nil;
    });

The signature of both handlers is described below in [The Principal API of the Promise](the_principal_api_of_the_promise).

The returned promise will be created by the underlying _asynchronous task_ - an "asynchronous result provider" within the asynchronous method `fetchUsersWithParams:error:` and then immediately returned to the client. The "asynchronous result provider" is an object whose lifetime extends up to the point at which it has finished its task and has the result available. When the result is available, or when the task failed to compute, the "asynchronous result provider" _resolves_ its promise with the result of the task or the reason of the failure.

A promise is initially in the state _pending_ - that is, it is not *resolved* yet. Then, at some indeterminable time it will be resolved with either the result value or with a reason for the failure. After it has been resolved, its state will then be either _fulfilled_ or _rejected_.

A promise can be resolved only *once*. Once a promise has been resolved its state cannot change anymore. Further attempts to *fulfill* or *reject* a resolved promise will have no effect.

The "consumer" (the client) of the asynchronous task can setup *handlers* (blocks) which will be invoked when the promise has been resolved. There are two kinds of handlers: the _completion handler_ which will be invoked when the promise has been fulfilled and the _error handler_ which will be invoked when the promise has been rejected.


#### Example

Suppose we want to implement an utility method `fetchUsers` which should download users using a network request method, get a representation as an `NSArray` of `Users`, and finally update a table view. Loading data from a network request typically may take indeterminable time to finish. Thus, virtually all reasonable approaches employ an asynchronous style. But lets assume we would have a synchronous convenient method `synchronousFetchUsersWithParams::error:`.  

Our utility method `fetchUser` has to be asynchronous, since it will be invoked from the main thread, and the main thread should never block. Thus, a viable implementation utilizing a synchronous convenient method `synchronousFetchUsersWithParams:error:`may look as follows:

```objective-c
- (void) fetchUsers {
    dispatch_async(queue, ^{
        NSError* error;
        NSArray* users = [self synchronousFetchUsersWithParams:params error:&error];
        if (users) {
            self.usersModel = users;
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.tableView reloadData];
            });
        }
        else {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self handleError:error];
            });
        }        
    });
}
```
    

Notice: even though the helper method `fetchUser` is indeed asynchronous, the implementation forces a thread to block until after the result is available. This thread has nothing to do than to wait until after the network request finished. Threads are usually expensive, and this solution is somewhat costly. The better solution follows:


Now, we utilize an asynchronous helper method `fetchWithParams:` which returns a promise. The implementation of the asynchronous helper method `fetchUsers` utilizing an asynchronous network request method will look as follows:

```objective-c
- (void) fetchUsers {
    self.usersPromise = [self fetchWithParams:params];
    self.usersPromise.thenOn(dispatch_get_main_queue() , ^id(id users){
        self.usersModel = users;
        [self.tableView reloadData];
    }, ^id(NSError* error){
        [self handleError:error];
    });
}
```

From an outer view, the behavior of both implementations of `fetchUsers` seem to be identical. However, the implementation of the second one utilizing Promises is more efficient in terms of system resources. Additionally, it looks also more concise. These differences will become more drastic, if problems become more complex.

[Contents ^](#contents)


-----
## The Principal API of the Promise

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

 The value of the property `thenOn` is a _block_ having three parameters. The first parameter specifies the execution context where the handlers are executed. The second is the _completion handler_ and the third is the _error handler_. The handlers are itself blocks. 

 The value of the property `then` is the same as above, except that it omits the explicit execution context for handlers. Here, the _implicit_ execution context is a _concurrent queue_.
 
The signatures are defined below:


```objective-c
typedef id (^completionHandler_t)(id result);
typedef id (^errorHandler_t)(NSError* error);

typedef RXPromise* (^then_on_t)(dispatch_queue_t, completionHandler_t, errorHandler_t);
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

-----
## Asynchronous Service Provider's Responsibility

A promise - more precisely, the _root promise_ - will be usually created by the asynchronous service provider. Initially, a promise is in the _pending_ state.

When the asynchronous function eventually succeeds or fails the asynchronous service provider must _resolve_ its associated promise. "Resolving" is either fulfilling or rejecting the promise with it's corresponding values, either the final result or an error.

That means, in order to resolve the promise when the task succeeded the asynchronous service provider must send the promise a _fulfillWithValue:_ message whose parameter represents the result value of the asynchronous function. Otherwise, if the asynchronous function fails, the asynchronous service provider must send the promise a _rejectWithReason:_ message whose parameter represents the reason for the failure, possibly an `NSError` object.


An example how an asynchronous method could be implement which uses a subclass of a `NSOperation` as the underlying asynchronous service provider is illustrated below:

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
    
    return promise;
}
```

The relevant API for the asynchronous service provider are just these methods:

```objective-c
- (void) fulfillWithValue:(id)result;
- (void) rejectWithReason:(id)reason;
```


> **Note:**

> When the promise will be resolved, the state of the promise changes from _pending_ to either _fulfilled_ or _rejected_. No further state changes are possible there after: once a promise has been resolved, subsequent fulfill or reject messages have no effect, and the promise's _value_ - which represents either the reason for a failure or the result of the asynchronous function - will not change either.


[Contents ^](#contents)

-----
## The _thenOn_ and _then_ Property

 A "consumer" (or client) of the result of an asynchronous function may or may not keep a reference to the promise which the function returns. In any case, the client can specify callback handlers (blocks) which will be invoked when either the promise has been fulfilled or rejected. This will be accomplished with the property `thenOn` and `then`.

As shown already, property `thenOn` and `then` returns a _block_ - which is quite unusual for a property. Since a block can be _called_ when applying the "invoke operator" (this is simply the function-call like syntax), we have a short hand for invoking the block that will be returned from a property. Remember the declaration of the `thenOn` property:

```objective-c
    @property then_on_t thenOn;
```

And the signature of the returned block was:

`typedef RXPromise* (^then_on_t)(dispatch_queue_t queue, completionHandler_t onSuccess, errorHandler_t onError);`


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

----
## Chaining  

(also *Continuation*)

The awesome feature of this `thenOn` and `then` property is that it is a block which itself returns a promise. That way, it becomes possible to _chain_ several asynchronous tasks together, like in words, it performs this:

"Start task A. If finished successful, start task B. If finished successful start task C. If finished successful start task D. If finished successful return result, else return error.",

where all tasks are supposed to be asynchronous, of course.


Again, an example will describe the concept of "chaining" promises in a more comprehensible way:


```objective-c
    RXPromise* endResult = [self async_A].then(
        ^id(id result) {
           return [self async_B:result];
        }, nil)
    .then(
        ^id(id result) {
           return [self async_C:result];
        }, nil)
    .then(
        ^id(id result) {
           return [self async_D:result];
        }, nil)
    .thenOn(dispatch_get_main_queue(),
        ^id(id result) {
           NSLog(@"Result: %@", result);
           return result;
        }, ^id(NSError* error) {
            NSLog(@"ERROR: %@", error);
           return error;
        });
```

The code above chains four asynchronous tasks and a last one which returns an _immediate_ result: the result of the last task or the error of the first task that failed. The asynchronous methods `async_B`, `async_C` and `async_D` are invoked on a _implicit_ execution context. That execution context is actually a _concurrent dispatch queue_.

The last handler on the other hand executes on the main thread - as specified through using the `thenOn` property.


The _root promise_, that is the first promise which has no parent promise, will be obtained through invoking the first asynchronous task via `[self async_A]`. The return value - a promise, whose parent is the root promise - will be immediately used to define the handlers via the `then` property whose completion handler just invokes the next asynchronous task `async_B`:

```objective-c
[self async_A].then(
        ^id(id result) {
           return [self async_B:result];
        }, nil)
        ...
```

Here, when task A finishes successful, the final result of task A will be passed as the parameter `result` to the completion handler, which in turn passes the result to task B in order to asynchronously compute another result. 

When task B completes, its final result will be passed to the next completion handler and so force - up until there is no handler anymore.


Note that the return values of the tasks are promises which will be returned from the handler. Since `then` and `thenOn` returns a promise, the next `then` or `thenOn` can be chained upon its previous `then` respectively `thenOn` the same way. And so force.

The last `thenOn` eventually handles the result returned from task_D - by simply logging the result to the console. Here, the execution context has been explicitly defined. That is, the handler executes on the specified queue - the main queue in the example.

At the end of the statement, promise _endResult_ will be the promise returned from the _last_ `thenOn`. When all tasks have been finished successfully, the _endResult_'s `value` will become the return value of the last completion handler - which is actually the result of the last task D.

If any of the tasks failed, _endResult_'s `value` will be the return value of the last error handler, which is in this example the error returned from the previous task. And that error, will possibly come from a previous task if that failed and so force. This is called "error propagation". So, when any of the tasks fails, promise _endResult_ will contain the error.


Notice, that the statement will execute completely asynchronously! Yet, effectively, they will be invoked one after the other.

[Contents ^](#contents)

----
## Error Propagation

In a *Continuation*, if any of the asynchronous tasks fails, the error will be automatically *propagated forward* to the promise _endResult_ - even when there are no error handlers defined. Subsequent tasks will not be started since the completion handler hasn't been invoked. So, it's not necessary to define error handlers, unless you want explicitly _catch_ them and handle them where they occurred.

For example:

```objective-c
    [self async_A]
    .then(^id(id result) {
         return [self async_B:result];
    }, nil)
    .then(^id(id result) {
        return [self async_C:result];
    }, nil)
    .then(^id(id result) {
        // ... do something with result
        return nil;
    }, ^id(NSError* error) {
        // handle error
        return nil;
    });
```

In the above continuation, none of the error handlers is defined, except for the last promise (note: `then`returns a promise). If either `async_A`, `async_B` *or* `async_D` the error will be propagated forward and handled by the next child promise which implements the error handler.

[Contents ^](#contents)

----
## Controlling the Handler's Paths

You may want to catch errors when you want to and are able to recover from an error and proceed normally. In this case, return something different than an error object - possibly a promise from any other asynchronous task - and the flow continues with the "success path".

Example:

```objective-c
    [self async_A]
    .then(^id(id result) {
         return [self async_B:result];
    }, ^(NSError* error){
        // ignore that error
        return @"Continue";
    })
    .then(^id(id result) {
        return [self async_C:result];
    }, nil)
    .then(^id(id result) {
        // ... do something with result
        return nil;
    }, ^id(NSError* error) {
        // handle error
        return nil;
    });
```

In the sample above, if `async_A`fails, it will be *caught* in the next error handler which ignores the error and returns a string constant: `@"Continue"`. Since this is not an `NSError` object, the Continuation proceeds with invoking `async_C` which gets passed a result parameter `@Continue"`.

Likewise, if you feel the result from a completion handler is bogus you can interrupt the "success path" through simply returning an `NSError` object and the flow subsequently takes the "error path".

[Contents ^](#contents)

----
## Starting Parallel Tasks

One feature that might become already obvious for the attentive reader is that it might be possible to invoke *several* `then` blocks for a particular promise.

In fact, this is perfectly valid:


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


Furthermore, it's also possible to "hook" into a promise with a handler from anywhere and anytime. Just invoke the `thenOn` or `then` block and define what shall happen anywhere in a program. If the promise is already resolved, the handler will just execute immediately, with the same concurrency guarantees.

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
            [op cancel];
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

When using the `then` property in order to register the success and error handler block, the execution context where the handler will be eventually executed is *private*. That means, the thread where the block gets executed is implementation defined. In fact,
`RXPromise` will use a private _concurrent_ execution context. 

From this it follows, that if the the `then` property is used for registering handlers, handlers will execute _concurrently_ and concurrent access to shared resources from within handlers is not automatically guaranteed to be thread-safe.


#### Making access to shared resources thread-safe

Concurrent access to shared resources can be made easily thread-safe from within handlers when the execution context (a dispatch queue) will be *explicitly* specified through the `thenOn` property:

    [self doSomethingAsync].thenOn(dispatch_queue, success_block, error_block);

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
   dispatch_barrier_async(queue, success_handler(result));
}
```

**Note:** 

> `dispatch_barrier_async` guarantees that write accesses to shared resources are thread-safe.


While `dispatch_barrier_async` guarantees thread-safety for a *concurrent* queue, it has a minor penalty when the handler would only perform *read* accesses to a shared resource. If the specified queue is a serial queue, `dispatch_barrier_async` is effectively the same as `dispatch_async`.

  

[Contents ^](#contents)
