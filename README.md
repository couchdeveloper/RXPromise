"Promises are a awesome!"



# RXPromise

An Objective-C Class which implements the Promises/A+ specification.


## General

The Promises/A+ specification defines the API and behavior of a _promise_. The specification was originally written for the Javascript language but the architecture and the design can be implemented in virtually any language.

This is an example of an implementation in Objective-C.


## Overview


A promise is lightweight primitive to manage asynchronous patterns. Promises will be invaluable when dealing with asynchronous architectures which make the code effectively look like it were synchronous.


Basically, a _promise_ represents the _eventual result_ of an asynchronous function or method. The "generic" form of such a method just requires to return a promise:

```objective-c
-(RXPromise*) doSomethingAsync;
```



A promise is initially in the state _pending_. Its state will then become either _fulfilled_ or _rejected_ as the effect of _resolving_ the promise.

The promise will be created by the "asynchronous service provider" associated to the asynchronous task. It is also responsible for _resolving_ the promise. "Resolving" is either _fulfilling_ or _rejecting_ the promise along with corresponding arguments, either the final _result_ of the tasks or an _error_.

Once a promise has been resolved its state cannot change anymore. Further attempts to fulfill or reject a resolved promise will have no effect.


The "consumer" (the client) of the asynchronous task can setup handlers (blocks) which will be invoked when the promise has been resolved. There are two kinds of handlers: the _completion handler_ which will be invoked when the promise will be fulfilled and the _error handler_ which will be invoked when the promise will be rejected.



## Credits 

This implementation strives to be as close as possible to the Promises/A+ specification which has brought to us from the Javascript community.
Thus, much of the credits go to their work and to those smart people they based their work on!
<https://github.com/promises-aplus/promises-spec>






## The Principal API of the Promise

The API has two parts: one for the "asynchronous service provider" and one for the consumer of the task's result, the "client".


```objective-c
/**
 Promise Client API
*/
@interface RXPromise : NSObject
@property (nonatomic, readonly) then_t then;
@end
```

 The value of the property `then` is a _block_ having two parameters. The first is the _completion handler_, the second is the _error handler_. The handlers are blocks again. The signatures are defined below:

```objective-c
typedef id (^completionHandler_t)(id result);
typedef id (^errorHandler_t)(NSError* error);
typedef RXPromise* (^then_t)(completionHandler_t, errorHandler_t);
```

 One very important fact is that the return value of the block_ which is the value of the property `then` is again a promise. This enables to _chain_ promises which will be explained in more detail below in section "Chaining".
 




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



## Asynchronous Service Provider's Responsibility

A promise shall always be created by the asynchronous service provider. Initially, a promise is in the _pending_ state.

When the asynchronous function eventually succeeds or fails the asynchronous service provider must _resolve_ its associated promise. "Resolving" is either fulfilling or rejecting the promise with its corresponding values, either the final result or an error. 

That means, in order to resolve the promise when the task succeeded the asynchronous service provider must send the promise a _fulfillWithResult:_ message whose parameter represents the result value of the asynchronous function. Otherwise, if the asynchronous function fails, the asynchronous service provider must send the promise a _rejectWithReason:_ message whose parameter represents the reason for the failure, possibly an `NSError` object.


An example how an asynchronous method could be implement which uses a subclass of a `NSOperation` as the underlaying asynchronous service provider is illustrated below:

```objective-c
- (RXPromise*) doSomethingAsync
{
    RXPromise* promise = [[RXPromise alloc] init];
    
    MyOperation* op = [MyOperation alloc] initWithCompletionHandler: ^(id result){
        [promise fulfillWithResult:result];
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
- (void) fulfillWithResult:(id)result;
- (void) rejectWithReason:(id)reason;
```


Note:

When the promise will be resolved, the state of the promise changes from _pending_ to either _fulfilled_ or _rejected_. No further state changes are possible there after: once a promise has been resolved, subsequent fulfill or reject messages have no effect, and the promise's _value_ - which represents either the reason for a failure or the result of the asynchronous function - will not change either.





## The _then_ Property

 A "consumer" (or client) of the result of an asynchronous function may or may not keep a reference to the promise which the function returns. In any case, the client can specify callback handlers (blocks) which will be invoked when either the promise has been fulfilled or rejected. This will be accomplished with the property `then`.

As shown already, property `then` returns a _block_ - which is quite unusual for a property. Since a block can be _called_ when applying the "invoke operator" (this is simply the function-call like syntax), we have a short hand for invoking the block that will be returned from a property. Remember the declaration of the `then` property:

```objective-c
    @property then_t then;
```


Given an object of type `RXPromise` _promise_, we could now _call_ the block whatever the promise's property `then` returns:

```objective-c
    promise.then( ... );
```

We know, that this block requires two parameters. These are blocks, too, and their signature has given above. The block also returns another promise:

```objective-c
    id completionHandler = ^id(id result) { ...; return something; }
    id errorHandler = ^id(NSError* error) { ...; return error; }

    RXPromise nextPromise = promise.then(completionHandler, errorHandler);
```

And shorter in a hopefully comprehensible way:

```objective-c
    RXPromise nextPromise = promise
    .then(^id(id result) {
        ...;
        return something;
    },
    ^id(NSError* error{
        ...;
        return error;
    });
```

That means, a given promise will create and return new promises when a client accesses the property `then`.

The very first promise, the "root promise", must be obtained from an asynchronous service provider, though:

```objective-c
    RXPromise* rootPromise = [self doSomethingAsync];
```

The method `doSomethingAsync` will start an asynchronous task and then immediately return a promise.



The client may now define what shall happen _when_ this asynchronous method succeeds or _when_ it fails through defining the corresponding handler blocks as shown above. The handler blocks may be `NULL` indicating that no action is to be taken.


## Chaining


The awesome feature of this `then` property is that it is a block which itself returns a promise. That way, it becomes possible to _chain_ several asynchronous tasks together, like in words, it performs this:

"Start task A. If finished successful, start task B. If finished successful start task D. If finished successful return result, else return error.",

where all tasks are supposed to be asynchronous, of course.


Again, an example will describe the concept of "chaining" promises in a more comprehensible way:


```objective-c
    Promise* endResult = [self async_A].then(
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
    .then(
        ^id(id result) {
           NSLog(@"Result: %@", result);
           return result;
        }, ^id(NSError* error) {
            NSLog(@"ERROR: %@", error);
           return error";
        });
```

The code above chains four asynchronous tasks and a last one which just synchronously returns the result respectively an error.



The first promise will be obtained through invoking the first asynchronous task via `[self async_A]`. The return value - a promise - will be immediately used to define the handlers via the `then` property whose completion handler just invokes the next asynchronous task `async_B`:

```objective-c
[self async_A].then(
        ^id(id result) {
           return [self async_B:result];
        }, nil)
        ...
```

Here, when task A finishes successful, the final result of task A will be passed as the parameter `result` to the completion handler, which in turn passes the result to task B in order to asynchronously compute another result. 

When task B completes, its final result will be passed to the next completion handler and so force - up until there is no handler anymore.


Note that the return values of the tasks are promises which will be returned from the handler. Since `then` returns a promise, the next `then` can be chained upon its previous `then` the same way. And so force.

The last `then` eventually handles the end result - by simply logging the result of the four chained asynchronous tasks to the console.

At the end of the statement, promise _endResult_ will be the promise returned from the _last_ `then`. When all tasks have been finished successfully, the _endResult_'s `value` will become the return value of the last completion handler - which is actually the result of the last task D.

If any of the tasks failed, _endResult_'s `value` will be the return value of the last error handler, which is in this example the error returned from the previous task. And that error, will possibly come from a previous task if that failed and so force. This is called "error propagation". So, when any of the tasks fails, promise _endResult_ will contain the error.


Notice, that the statement will execute completely asynchronously! Yet, effectively, they will be invoked one after the other.



## Error Propagation

If any of the asynchronous tasks fails, the error will be automatically propagated forward to the promise _endResult_ - even when there are no error handlers defined. Subsequent tasks will not be started since the completion handler hasn't been invoked. So, it's not necessary to define error handlers, unless you want explicitly _catch_ them and handle them where they occurred.


## Controlling the Handler's Paths

You may want to catch errors when you want to and are able to recover from an error and proceed normally. In this case, return something different than an error object - possibly a promise from any other asynchronous task - and the flow continues with the "success path".

Likewise, if you feel the result from a completion handler is bogus you can interrupt the "success path" through simply returning an `NSError` object and the flow subsequently takes the "error path".



## Starting Parallel Tasks

One feature that might become already obvious for the attentive reader is that it might possible to invoke *several* `then` blocks for a particular promise.
In fact, this is perfectly valid:


```objective-c
        RXPromise root = taskA();

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

The effect of this is that once the root promise has been resolved, as the result of taskA is available, it serially executes all four handlers _in order_ they have been defined and possibly starts several new tasks "quasi" at once (since starting a asynchronous task returns quickly).

The newly started tasks now may return at indeterminable times and may cause to invoke their handlers, too. Though, don't worry about possibly race conditions when these handlers try to access a shared resource: all handlers are guaranteed to be synchronized - if they originate from the same root promise!



With this design it is possible to define even _complex trees_ of tasks in a concise way. Since access of shared resources is safe from within handlers, setting up complex composed tasks becomes quite easy.


Furthermore, it's also possible to "hook" into a promise with a handler from anywhere and anytime. Just invoke the `then` block and define what shall happen anywhere in a program. If the promise is already resolved, the handler will just execute immediately, with the same concurrency guarantees.


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
        [promise fulfillWithResult:result];
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








## Synchronization Guarantees

Concurrent access to shared resources is guaranteed to be safe for accesses from within handlers whose promises belong to the same "promise tree".



