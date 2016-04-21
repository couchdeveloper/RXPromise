## Installation


Important note beforehand:  

RXPromise is a *pure* Objective-C API. Even though it depends itself on the standard C++ library it does not affect (or "infect") *your* Objective-C sources in any way with C++.


The minimum deployment version for iOS is 8.0 and for Mac OS X it is 10.9. Since version 1.0.0 the project does not contain any static library targets anymore - but this can be added when desired.

There are two recommended ways to incorporate the library into your project:

 1. Using CocoaPods
 2. Using Carthage

**Note:**
> `RXPromise` version number system adheres to the rules of [Semantic Versioning](http://semver.org).


#### Using CocoaPods


For reference, see [CocoaPods](https://guides.cocoapods.org/using/using-cocoapods.html).

As a minimum, add the following line to your [Podfile](http://guides.cocoapods.org/using/the-podfile.html) in your project folder:

```ruby
pod 'RXPromise'
```

The above declaration loads the _most recent_ published version from Cocoapods.

You may specify a certain version or a certain _range_ of available versions. For example:
```ruby
pod 'RXPromise', '~> 1.0'  
```

This automatically selects the most recent version in the repository in the range from 1.0.0 and up to 2.0, not including 2.0 and higher.

See more help here: [Specifying pod versions](http://guides.cocoapods.org/using/the-podfile.html#specifying-pod-versions).


Example Podfile:

```ruby
# MyProject.Podfile

use_frameworks!

target 'MyTarget' do
  pod 'RXPromise', '~> 1.0' # Version 1.0 and the versions up to 2.0, not including 2.0 and higher
end
```

After you edited the Podfile, open Terminal, cd to the directory where the Podfile is located and type the following command in the console:

```console
$ pod install
```

### Carthage


> **Note:** Carthage only supports dynamic frameworks which are supported in Mac OS X and iOS 8 and later.
For further reference see [Carthage](https://github.com/Carthage/Carthage).


1. Follow the instructions [Installing Carthage](https://github.com/Carthage/Carthage) to install Carthage on your system.
2. Follow the instructions [Adding frameworks to an application](https://github.com/Carthage/Carthage). Then add    
    `github "couchdeveloper/RXPromise"`    
 to your Cartfile.		
