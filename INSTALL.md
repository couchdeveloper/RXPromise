## Installation

The `RXPromise` library is actually just _one_ class. There are a few options how to incorporate it into you projects. 

Just an important note beforehand:  RXPromise depends on the C++ standard library. When including the sources directly or when linking against the static library this requires one extra step which is explained in detail below. If you link against the Framework, there is no extra step.  Note that RXPromise is a pure Objective-C API - and does not affect (or "infect") your Objective-C soures in any way with C++.


 - Include sources directly into your project

    This is probably the quickiest way. There are only three source files to include:

    Dowload the zip archive or clone the git repository in order to obtain the sources. Locate the folder `Sources` in Finder, which is located in "`Promise Libraries`", into the Navigation area of your Xcode project below or beneath your other sources. Optionally make a copy. This will create a new group in the Navigation area, which you can rename to, say "RXPromise".

    RXPromise must be compiled with ARC enabled. The deployment target should be Mac OS X 10.7 and newer, respectively iOS 5.x and newer.

    If you include source files directly, you need to ensure that your _executable_ binary links against the C++ standard library. How you can accomplish this is explained below.

    In your sources, use the `#import "RXPromise.h"` in order to include the header.
 

 - Use the static library (iOS) or the Framework (Mac OS X)

    Download the zip archive or clone the git repository in order to obtain the sources. Ensure you have a Workspace for your project and open in Xcode. Also ensure you don't have the RXPromise project open in Xcode. Otherwise, close the RXPromise project. Locate the Xcode project file "`RXPromise Libraries.xcodeproj`" in Finder and drag it into the Navigation area of your project, preferable beneath your other projects. Do not make a copy. This will create a new Project reference in the Navigation area.

    Then you need to link your binary against either the static library for your iOS project or against the Framework in your Mac OS X project: In the Navigation area, select your project. In the target editor area select the target that produces your executable binary and select "Build Phases" tab. In the "Link Binary With Libraries" section, click the "+" button. This opens a selection dialog, with a "Workspace" folder, where you can find "RXPromise.framework", "libRXPromise.a" (for Mac OS) and "libRXPromise.a" (for iOS). Ensure you select the correct library and click the "Add" button.

    In your sources, use the `#import <RXPromise/RXPromise.h>` in order to include the header.


    Note: Linking an executable binary against a _static library_ requires that all dependencies are finally linked in the executable binary. That means, when you use the static lib ("libRXPromise.a") you need to ensure to link your executable binary also against the C++ Standard library. How you can accomplish this is explained below:


#### Link against the C++ Standard library

One can accpomplish this, for example:

  - Rename your `main.m`file to `main.mm`. This causes the build tools to automatically do the right things. You are finished.

  - Alternatively, add a build setting in "Other Linker Flags" in your target build settings: select the project in the Navigation area, select your target which produces the executable. In the target editor, select "Build Settings" tab, locate the "Other Linker Flags" build setting and add `-lc++` (without back ticks).
 
    
  Note: when using a Framework, the dependencies are already established.  

 

