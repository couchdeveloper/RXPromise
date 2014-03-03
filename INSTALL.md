## Installation
Installation of the RXPromise library into your Xcode project is basically quite easy. The `RXPromise` library is actually just _one_ class and consists of just a few files.

There are three options to incorporate class `RXPromise` into you project:

 1. Utilize CocoaPods
 2. Include the sources directly into your project
 3. Link your project against the static library (iOS) or the Framework (Mac OS X)

**Note:**
> `RXPromise` version number system adheres to the rules of [Semantic Versioning](http://semver.org).


####Using CocoaPods

The easiest way to install `RXPromise` library into you Xcode project is to utilize [CocoaPods](http://cocoapods.org). How you prepare your Xcode project for using PODs is explained here in detail: [Using CocoaPods](http://guides.cocoapods.org/using/using-cocoapods.html).


Usually, it's good practice to specify a particular _major_ and a minimum _minor_ release number which defines the minimum set of APIs which is required for your application, and furthermore let CocoaPods automatically choose the most recent version which contains all the APIs and the most recent bug fixes. You can achieve this with adding the following to your Podfile:

`pod 'RXPromise', '~> 1.1'`

This will automatically select the most recent version whose major version number equals **1** and which contains the set of APIs defined in version **1.1** and also has the most recent patch level, e.g.:  **1.3.1**.    

Older code which had worked with versions **1.0.0** should still be running.

If you are more picky about the probability that newer versions, say **1.3.x** will possibly not expose the _same_ behavior as **1.2.x**, you might want to use

`pod 'RXPromise', '~> 1.2.0'`

This imports `RXPromise` library whose major version number equals **1** and the minor version number equals **2** and with the most recent patch level which contains only bug fixes. Say, for version **1.2.x** the most recent patch level equals **6**, the above statement `'~> 1.2.0'` will import version **1.2.6**.  

However, if there are newer versions which add more features in a backwards compatible way, say **1.3.1** and possibly also contain bug fixes not fixed in versions **1.2.x**, those will not be considered. 
    

####Adding RXPromise Xcode project to your project

There are two public header files: 

 - `RXPromise.h`,  the principle APIs.
 - `RXPromise+RXExtension.h`, the extension APIs which is a Category of class RXPromise.
 
Additionally, there is a private header file `RXPromise+Private.h` and two implementation files, `RXPromise.mm` and `RXPromise+RXExtension.mm`.

Furthermore, there's a logging utility `DLog.h` which is just a header file. It's located in sub folder `utility`.



Just an important note beforehand:  

> RXPromise depends on the C++ standard library. When including the sources directly or when linking against the static library this requires one extra step which is explained in detail below. If you link against the Framework, there is no extra step.  

> Note that RXPromise is a *pure* Objective-C API. Even though it depends itself on the standard C++ library it does not affect (or "infect") *your* Objective-C sources in any way with C++.



### Include sources directly into your project

   1. Download the zip archive or clone the git repository in order to obtain the source files. 
   
   1. In Finder, locate the folder `Source` which is located in "`Promise Libraries`". 

   1. Drag the `Source` folder into the Navigation area of your Xcode project below or beneath your other sources. Optionally make a copy. This will create a new group in the Navigation area, which you can rename to, say "RXPromise".
   
**Caution:**
> RXPromise must be compiled with ARC enabled. The deployment target should be Mac OS X 10.7 and newer, respectively iOS 5.x and newer.

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
> In your sources, use the `#import <RXPromise/RXPromise.h>` in order to include the header.

> If you use the extension methods, you need to import the extension header, too: `#import <RXPromise/RXPromise+RXExtension.h>`


**Caution:**
> Linking an executable binary against a _static library_ requires that all dependencies are finally linked in the executable binary. That means, when you use the static lib (`libRXPromise.a`) you need to ensure to link your executable binary also against the C++ Standard library. How you can accomplish this is explained below:


### Link against the C++ Standard library

 **Note:** 
> When linking against the RXPromise *Framework*, its dependencies are already established. This means, that the executable does not need to link itself against those dependencies of the RXPromise framework, e.g. linking against the standard C++ library.  


Linking against the Standard C++ Library can be accomplished for example:

  - Rename your `main.m`file to `main.mm`. This causes the build tools to automatically link against the correct standard C++ library. You are finished.

  - Alternatively, locate the build setting "**Other Linker Flags**" in your target build settings of the executable binary and *add* the setting: `-lc++`.



> Written with [StackEdit](https://stackedit.io/).