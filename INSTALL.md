## Installation

Installation of the RXPromise library into a Xcode project is basically quite easy. The `RXPromise` library consists of just _one_ class and just a few files.

Important note beforehand:  

> RXPromise depends on the C++ standard library. When including the sources directly or when linking against the static library this requires one extra step in your target build settings which is explained in detail below. If your project links against the RXPromise Framework or when you use CocoaPods, there is no extra step.

> The minimum deployment version for iOS is 7.0 and for Mac OS X it is 10.9.

> Note that RXPromise is a *pure* Objective-C API. Even though it depends itself on the standard C++ library it does not affect (or "infect") *your* Objective-C sources in any way with C++.

### Adding RXPromise library project to your Xcode project

There are three ways to incorporate `RXPromise` library into you project:

 1. Utilize CocoaPods
 2. Include the sources directly into your project
 3. Link your project against the static library (iOS) or the Framework (Mac OS X)

**Note:**
> `RXPromise` version number system adheres to the rules of [Semantic Versioning](http://semver.org).

**Note:**
> At the time of writing, RXPromise is still in beta. Thus, the major version is **zero**. The current version is **0.14.0**.


#### Using CocoaPods

The easiest way to install `RXPromise` library for use in a client Xcode project is to utilize [CocoaPods](http://cocoapods.org). How to create a Podfile, where to place it and how to specify POD depenencies is explained here in detail: [Using CocoaPods](http://guides.cocoapods.org/using/using-cocoapods.html).

Usually, it's good practice to specify a particular _major_ and a minimum _minor_ release number of the POD's verion. Basically, this defines the minimum set of APIs which is required for your application. Furthermore let CocoaPods automatically choose the most recent version of this POD which contains all the APIs and the most recent bug fixes. Assuming, your project requires the RXPromise APIs which have been defined in version **1.1.0**, you can achieve this using the following syntax:

`pod 'RXPromise', '~> 1.1'`

This will automatically select the most recent version which is API backwards compatible to version **1.1.0**, that is, whose major version number equals **1**. This version contains the set of APIs defined in version **1.1.0**  and possibly new ones, and also has the most recent patch level. Client code which has been developed using the **1.1.0** API should still compile and run without issues.

> You can read more about the syntax of the versioning scheme and dependency declaration in [The Podfile](http://guides.cocoapods.org/using/the-podfile.html). It might be helpful as well to read [Declaring dependencies](http://guides.rubygems.org/patterns/#declaring_dependencies) in the Ruby Gems documentation.


#### Include sources directly into your project

   1. Download the zip archive or clone the git repository in order to obtain the source files. 

      
   1. In Finder, locate the folder `Source` which is located in "`Promise Libraries`". 

   1. Drag the `Source` folder into the Navigation area of your Xcode project below or beneath your other sources. Optionally make a copy. This will create a new group in the Navigation area, which you can rename to, say "RXPromise".

There are two public header files: 

 - `RXPromise.h`,  the principle APIs.
 - `RXPromise+RXExtension.h`, the extension APIs which is a Category of class `RXPromise`.
 
Additionally, there is a private header file `RXPromise+Private.h` and two implementation files, `RXPromise.mm` and `RXPromise+RXExtension.mm`.

Furthermore, there's a logging utility `DLog.h` which is just a header file. It's located in sub folder `utility`.

   
**Caution:**
> `RXPromise` module files must be compiled with ARC enabled. The deployment target should be Mac OS X 10.7 and newer, respectively iOS 5.1 and newer.

> If you include source files directly, you need to ensure that your _executable_ binary links against the C++ standard library. How you can accomplish this is explained below.

**Including Headers:**

> In your sources, use  `#import "RXPromise.h"` in order to include the header. 

> If you use the extension methods, you need to import the extension header, too: `#import <RXPromise+RXExtension.h>`

 

### Using the static library (iOS) or the Framework (Mac OS X)

1. Download the zip archive or clone the git repository in order to obtain the sources. 

2. Ensure you have a Workspace for your project and open in Xcode. Also ensure you don't have the RXPromise project open in Xcode. Otherwise, close the RXPromise project. 

3. In Finder, locate the Xcode project file "`RXPromise Libraries.xcodeproj`" 

4. Drag the Xcode project file into the Navigation area of your project, preferable beneath your other projects. Do not make a copy. This will create a new Project reference in the Navigation area.

5. Link your binary against either the static library for your iOS project or against the Framework in your Mac OS X project:

- In the Navigation area, select your project. 
- In the target editor area select the target that produces your executable binary and select "Build Phases" tab. 
- In the "Link Binary With Libraries" section, click the "+" button. This opens a selection dialog, with a "Workspace" folder, where you can find `RXPromise.framework`, `libRXPromise.a` (for Mac OS) and `libRXPromise.a` (for iOS). 
- Ensure you select the correct library or framework and click the "Add" button.

6. When linking against the static library, ensure you set option `-ObjC` in the build setting **Other Linker Flags" of the target of the executable binary.

**Including Headers:**
> In your sources, use the `#import <RXPromise/RXPromise.h>` in order to include all public headers.



**Caution:**
> Linking an executable binary against a _static library_ requires that all dependencies are finally linked in the executable binary. That means, when you use the static lib (`libRXPromise.a`) you need to ensure to link your executable binary also against the C++ Standard library. How you can accomplish this is explained below:


### Linking against the C++ Standard library

 **Note:** 
> When linking against the RXPromise *Framework*, its dependencies are already established. This means, that the executable does not need to link itself against those dependencies of the RXPromise framework, e.g. linking against the standard C++ library.  

> If you use CocoaPods, the target settings already take care of this and link against the standard C++ Library.



Linking against the Standard C++ Library can be accomplished for example:

  - Rename your `main.m`file to `main.mm`. This causes the build tools to automatically link against the correct standard C++ library. You are finished.

  - Alternatively, locate the build setting "**Other Linker Flags**" in your target build settings of the executable binary and *add* the setting: `-lc++`.



> Written with [StackEdit](https://stackedit.io/).