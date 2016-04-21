
def git_has_uncommitted_changes
    return system("git diff-index --quiet --cached HEAD") == false
end

def git_has_dirty_workspace
    return system("git diff-files --quiet") == false
end

def git_has_untracked_files
    return `git ls-files --exclude-standard --others`.strip.length > 0
end


def git_is_status_clean
    return `git status --porcelain`.strip.empty?
end

def git_version
    return `git describe --long`.strip
end


$workspace = "RXPromise.xcworkspace"
$allSchemes = ['RXPromise-MacOS', 'RXPromise-iOS', 'RXPromise-tvOS', 'RXPromise-WatchOS']
$testSchemes = ['RXPromise-MacOS', 'RXPromise-iOS', 'RXPromise-tvOS']


desc "Build all targets defined within the given schemes #{$allSchemes}"
task :build do
    $allSchemes.each { |scheme|
        sh "xctool -workspace #{$workspace} -scheme #{scheme} build"
    }
end

desc "Clean all targets defined within the given schemes #{$allSchemes}"
task :clean do
    $allSchemes.each { |scheme|
        sh "xctool -workspace #{$workspace} -scheme #{scheme} clean"
    }
end



desc "Run all tests defined within the given schemes"
task :test  => [:build] do
    sh "xcrun xcodebuild test -workspace RXPromise.xcworkspace -scheme RXPromise-MacOS -destination 'arch=x86_64'| xcpretty"
    sh "xcrun xcodebuild test -workspace RXPromise.xcworkspace -scheme RXPromise-iOS -destination 'platform=iOS Simulator,name=iPhone 6' test | xcpretty"
    sh "xcrun xcodebuild test -workspace RXPromise.xcworkspace -scheme RXPromise-tvOS -destination 'platform=tvOS Simulator,name=Apple TV 1080p' test | xcpretty"
end




namespace :version do

    desc "Print a description of the current version"
    task :describe do
        puts "git HEAD: #{`git describe --dirty`}"
        puts "Marketing version: #{`agvtool what-marketing-version -terse1`}"
        puts "Build number: #{`agvtool what-version  -terse`}"
    end

    desc "Udates BUNDLE_SHORT_VERSION with the specified version, then commits and pushes to origin"
    task :release do
        currentBranch = `git symbolic-ref --short HEAD`.strip
        if currentBranch != 'master'
            abort "Error: You must be on the master branch in order to define a new release!"
        end
        if !git_is_status_clean
            abort "Error: There are uncommitted changes. Please run tests and commit changes before creating a new release!"
        end

        puts "Current git description: #{`git describe --dirty`}"
        puts "Current Marketing version: #{`agvtool what-marketing-version -terse1`}"
    end
end
