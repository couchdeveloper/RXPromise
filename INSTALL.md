# Installation


> The minimum deployment version for iOS is 7.0 and for Mac OS X it is 10.9.


## Adding RXPromise library project to your Xcode project

There are two ways to incorporate `RXPromise` library into you project:

 1. Utilize CocoaPods
 1. Link your project against the respective Framework for iOS or MacOS.

**Note:**
> `RXPromise` version number system adheres to the rules of [Semantic Versioning](http://semver.org).

**Note:**
> At the time of writing, RXPromise is still in beta. Thus, the major version is **zero**. The current version is **0.14.0**.


### Using CocoaPods

The easiest way to install `RXPromise` library for use in a client Xcode project is to utilize [CocoaPods](http://cocoapods.org). How to create a Podfile, where to place it and how to specify POD dependencies is explained here in detail: [Using CocoaPods](http://guides.cocoapods.org/using/using-cocoapods.html).

Usually, it's good practice to specify a particular _major_ and a minimum _minor_ release number of the POD's version. Basically, this defines the minimum set of APIs which is required for your application. Furthermore let CocoaPods automatically choose the most recent version of this POD which contains all the APIs and the most recent bug fixes. Assuming, your project requires the RXPromise APIs which have been defined in version **1.1.0**, you can achieve this using the following syntax:

`pod 'RXPromise', '~> 1.1'`

This will automatically select the most recent version which is API backwards compatible to version **1.1.0**, that is, whose major version number equals **1**. This version contains the set of APIs defined in version **1.1.0**  and possibly new ones, and also has the most recent patch level. Client code which has been developed using the **1.1.0** API should still compile and run without issues.

> You can read more about the syntax of the versioning scheme and dependency declaration in [The Podfile](http://guides.cocoapods.org/using/the-podfile.html). It might be helpful as well to read [Declaring dependencies](http://guides.rubygems.org/patterns/#declaring_dependencies) in the Ruby Gems documentation.




### Using the Framework (iOS or MacOS)

1. Download the zip archive or clone the git repository in order to obtain the sources.

2. Ensure you have a Workspace for your project and open in Xcode. Also ensure you don't have the RXPromise project open in Xcode. Otherwise, close the RXPromise project.

3. In Finder, locate the Xcode project file "`RXPromise.xcodeproj`"

4. Drag the Xcode project file into the Navigation area of your project, preferable beneath your other projects. Do not make a copy. This will create a new Project reference in the Navigation area.

5. Link your binary against the Framework for your iOS project or against the Framework in your Mac OS X project:

- In the Navigation area, select your project.
- In the target editor area select the target that produces your executable binary and select "Build Phases" tab.
- In the "Link Binary With Libraries" section, click the "+" button. This opens a selection dialog, with a "Workspace" folder, where you can find `RXPromise.framework` - for either iOS or MacOS.
- Ensure you select the correct library or framework and click the "Add" button.


**Including Headers:**
> In your sources, use the `#import <RXPromise/RXPromise.h>` in order to include all public headers.
