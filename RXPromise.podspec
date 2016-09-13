Pod::Spec.new do |s|
  s.name             = "RXPromise"
  s.version          = "1.0.3"
  s.summary          = "A thread safe implementation of the Promises/A+ specification in Objective-C with extensions."
  s.license          = { :type => 'Apache License, Version 2.0', :file => 'LICENSE.md'}
  s.authors          = { "Andreas Grosam" => "agrosam@onlinehome.de" }
  s.homepage         = "https://github.com/couchdeveloper"
  s.source           = { :git => "https://github.com/couchdeveloper/RXPromise.git", :tag => s.version.to_s }

  s.ios.deployment_target = '8.0'
  s.osx.deployment_target = '10.9'
  s.tvos.deployment_target = '9.0'
  s.requires_arc = true

  s.source_files = "Source/**/*.{h,m,mm}"
  s.public_header_files = "Source/RXPromise.h", "Source/RXPromiseHeader.h", "Source/RXPromise+RXExtension.h", "Source/RXSettledResult.h"
  s.header_mappings_dir = "Source"
  s.libraries = 'c++'

  s.weak_framework = 'CoreData'

  s.compiler_flags = '-O3', '-std=c++11', '-stdlib=libc++', '-DNDEBUG', '-DDEBUG_LOG=1', '-DNS_BLOCK_ASSERTIONS', '-D__ASSERT_MACROS_DEFINE_VERSIONS_WITHOUT_UNDERSCORES=0'

  s.xcconfig = { 'OTHER_LDFLAGS' => '-ObjC' }

end
