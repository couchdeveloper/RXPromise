//
//  RXPromise.h
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

#import <Foundation/Foundation.h>


/**

 Concurrency:

 Concurrent access to shared resources is only guaranteed to be safe for accesses
 from within handlers whose promises belong to the same "promise tree". *)
 
 A "promise tree" is a set of promises which share the same root promise.
 

 *) Currently, it is guraranteed that concurrent access from within any handler
    from any promise to a shared resource is guaranteed to be safe.
 
 
 
 Usage:
 
 
 
 Chaining
 
 foo.result = nil;
 id input = ...;
 
 [foo doSomethingAsyncWith:input].then(^id(id result){
    return [foo doFooAsyncWith:result];
 }, nil)
 .then(^id(id result){
    return [foo doBarAsyncWith:result];
 }, nil)
 .then(^id(id result){
    return [foo doFoobarAsyncWith:result];
 }, nil)
 .then(^id(id result){
    [foo setResult:result]; 
    return nil;
 }, ^id(NSError* error){
    [foo setError:error]; 
    return nil;
 });
 
 
 RXPromise* if_auth = [self.user authenticate];
 if_auth
    .then(^id(id){ return [self.user loadProfile]; }, nil)
    .then(^id(id result){
        NSError* error;
        self.user.profile = [NSJSONSerialization JSONObjectWithData:result options:0 error:&error];
        if (self.user.profile == nil) {
            [foo handleJSONParseError:error];
        }
        return nil;
 }, ^id(NSError* error){
        // load profile failed
        return nil;
    } )
 }, nil #*auth failed*#);
 
 if_auth.then(^id(id){
     [self.user loadMessages]
     .then(^id(id result){
        NSError* error;
        self.user.messages = [NSJSONSerialization JSONObjectWithData:result options:0 error:&error];
        if (self.user.messages == nil) {
            [foo handleJSONParseError:error];
        }
        return nil;
     },nil)
 }, nil);
 */


@class RXPromise;

typedef id (^completionHandler_t)(id result);
typedef id (^errorHandler_t)(NSError* error);
typedef void (^progressHandler_t)(id progress);

typedef RXPromise* (^then_t)(completionHandler_t, errorHandler_t);


@interface RXPromise : NSObject

@property (nonatomic, readonly) BOOL isPending;
@property (nonatomic, readonly) BOOL isFulfilled;
@property (nonatomic, readonly) BOOL isRejected;
@property (nonatomic, readonly) BOOL isCancelled;

@property (nonatomic, readonly) then_t then;

- (RXPromise*) then:(id(^)(id result))completionHandler
       errorHandler:(id(^)(NSError* error))errorHandler
    progressHandler:(void(^)(id progress))progressHandler;

- (RXPromise*) then:(id(^)(id result))completionHandler
       errorHandler:(id(^)(NSError* error))errorHandler;

- (RXPromise*) then:(id(^)(id result))completionHandler;

- (void) cancel;

- (id) get;

- (void) wait;


@end


// Deferred Interface
@interface RXPromise(Deferred)

- (id)init;

- (void) fulfillWithValue:(id)result;
- (void) rejectWithReason:(id)error;
- (void) setProgress:(id)progress;
- (void) cancelWithReason:(id)reason;
@end


