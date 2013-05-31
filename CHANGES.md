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

