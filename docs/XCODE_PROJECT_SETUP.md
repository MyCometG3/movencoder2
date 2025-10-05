# Xcode Project Setup for Public API

## Overview

This document provides instructions for configuring the Xcode project to properly expose public headers for framework distribution.

---

## ⚠️ Important: Current Project Status

**The movencoder2 project currently has a command-line tool target, not a framework target.**

- **Current Target Type:** `com.apple.product-type.tool` (command-line tool)
- **Current Product:** Executable binary (`mh_execute`)
- **Framework Target:** Does not exist yet

You can verify this with:
```bash
xcodebuild -showBuildSettings -project movencoder2.xcodeproj -target movencoder2 | grep -E "(PRODUCT_TYPE|MACH_O_TYPE)"
```

**This document describes future framework configuration steps** that will apply once a framework target is added to the project. The Public API structure and headers have been prepared in advance to facilitate this future transition.

### When to Use This Document

Use these instructions when you are ready to:
1. Create a framework target in addition to (or instead of) the command-line tool
2. Distribute movencoder2 as a reusable framework
3. Support framework-based integration (e.g., via CocoaPods, Carthage, or manual framework linking)

The current command-line tool target can continue to use all headers directly via `#import` statements without the framework-specific configuration described below.

---

## Creating a Framework Target (Prerequisite)

Before following the configuration steps below, you'll need to add a framework target to the Xcode project:

### Option 1: Create New Framework Target

1. Open `movencoder2.xcodeproj` in Xcode
2. Select the project in the navigator
3. Click the "+" button at the bottom of the targets list
4. Choose **"Framework"** (under macOS → Framework & Library)
5. Name it `MovEncoder2`
6. Set Language to **Objective-C**
7. Click **Finish**

### Option 2: Convert Existing Target

Alternatively, you can create a separate framework target while keeping the command-line tool:

1. Follow Option 1 to create a new framework target
2. Add all source files (`.m` files) to both targets
3. Configure headers as described below (public headers only for framework target)
4. Keep the command-line tool target for CLI usage
5. Build and distribute both the CLI tool and framework as needed

---

## Steps to Configure Public Headers (For Framework Target)

### 1. Add Public Directory to Framework Target

1. Open `movencoder2.xcodeproj` in Xcode
2. In the Project Navigator, right-click on the `movencoder2` group (or create a new group for the framework)
3. Select "Add Files to movencoder2..."
4. Navigate to and select the `movencoder2/Public` folder
5. Ensure "Create groups" is selected (not "Create folder references")
6. **Important:** In the "Add to targets" section, check **only the framework target** (MovEncoder2), not the command-line tool target
7. Click "Add"

### 2. Mark Headers as Public (Framework Target Only)

For each header in the `Public/` directory:

1. Select the header file in the Project Navigator
2. Open the File Inspector (⌥⌘1)
3. In the "Target Membership" section, locate the **framework target** (e.g., "MovEncoder2")
4. Check the box for the framework target if not already checked
5. Change the header visibility from "Project" to **"Public"**

Public headers to mark:
- `MovEncoder2.h` (umbrella header)
- `METranscoder.h`
- `MEVideoEncoderConfig.h`
- `METypes.h`

**Note:** Internal headers (in Config/, Core/, Pipeline/, IO/, Utils/) should remain marked as "Project" or "Private" for the framework target.

### 3. Set Framework Umbrella Header

1. Select the **framework target** (MovEncoder2) in the project editor
2. Go to "Build Settings" tab
3. Search for "umbrella"
4. Set **"Public Headers Folder Path"** to: `include/MovEncoder2`
5. Set **"Module Name"** to: `MovEncoder2`

### 4. Configure Header Search Paths (Framework Target)

1. Select the **framework target** in the project editor
2. In Build Settings, search for "Header Search Paths"
3. Add the following paths (if not already present):
   - `$(SRCROOT)/movencoder2/Public` (recursive)
   - `$(SRCROOT)/movencoder2` (non-recursive, for internal framework builds only)

### 5. Verify Framework Structure

After building the framework, verify the structure:

```
MovEncoder2.framework/
├── Versions/
│   └── A/
│       ├── Headers/          # Public headers should be here
│       │   ├── MovEncoder2.h
│       │   ├── METranscoder.h
│       │   ├── MEVideoEncoderConfig.h
│       │   └── METypes.h
│       ├── MovEncoder2       # Framework binary
│       └── Resources/
├── Headers -> Versions/Current/Headers
└── MovEncoder2 -> Versions/Current/MovEncoder2
```

### 6. Test Public API Import

Create a test file to verify the public API is accessible:

```objective-c
#import <MovEncoder2/MovEncoder2.h>

int main(int argc, char *argv[]) {
    @autoreleasepool {
        // This should compile without errors
        NSURL *input = [NSURL fileURLWithPath:@"/tmp/input.mov"];
        NSURL *output = [NSURL fileURLWithPath:@"/tmp/output.mov"];
        
        METranscoder *transcoder = [[METranscoder alloc] initWithInput:input 
                                                                output:output];
        
        NSLog(@"Transcoder created: %@", transcoder);
    }
    return 0;
}
```

Compile with:
```bash
clang -framework MovEncoder2 -framework Foundation test.m -o test
```

---

## Module Map (Optional for Swift/Modules)

For module support, create `movencoder2/Public/module.modulemap`:

```
framework module MovEncoder2 {
    umbrella header "MovEncoder2.h"
    
    export *
    module * { export * }
    
    explicit module Public {
        header "METranscoder.h"
        header "MEVideoEncoderConfig.h"
        header "METypes.h"
        export *
    }
}
```

Then in Build Settings:
- Set **"Defines Module"** to **YES**
- Set **"Module Map File"** to `$(SRCROOT)/movencoder2/Public/module.modulemap`

---

## Troubleshooting

### Headers Not Found During Build

**Problem:** Compiler can't find public headers

**Solution:**
- Check that headers are marked as "Public" in Target Membership
- Verify Header Search Paths include the Public directory
- Clean build folder (⇧⌘K) and rebuild

### Internal Headers Visible to Framework Users

**Problem:** Internal headers are accessible from framework

**Solution:**
- Ensure only headers in `Public/` are marked as "Public"
- All other headers should be marked as "Project" or "Private"
- Verify the built framework's Headers directory

### Module Not Found in Swift

**Problem:** `import MovEncoder2` fails in Swift

**Solution:**
- Ensure "Defines Module" is set to YES
- Check that umbrella header includes all public headers
- Verify Module Name matches the import statement

---

## Build Configurations

### Debug Configuration

For development builds:
- Keep internal headers accessible for debugging
- Enable verbose logging
- Include symbols

### Release Configuration  

For distribution:
- Only public headers should be in the framework
- Strip debugging symbols
- Enable optimizations
- Set deployment target appropriately

---

## Validation Checklist

**Prerequisites:**
- [ ] Framework target created in Xcode project

**Framework Configuration:**
- [ ] Public directory added to Xcode project (framework target only)
- [ ] All public headers marked as "Public" in framework target membership
- [ ] Umbrella header configured in framework build settings
- [ ] Framework builds without errors
- [ ] Public headers accessible via `#import <MovEncoder2/...>`
- [ ] Internal headers not visible in framework bundle
- [ ] Test app successfully links against framework
- [ ] No private symbols exposed in public headers
- [ ] Documentation builds correctly (if using HeaderDoc/Jazzy)

**Current Status:**
- [x] Public API headers prepared in `movencoder2/Public/` directory
- [x] Internal headers marked with `@internal` documentation
- [x] Documentation structure ready for framework distribution
- [ ] Framework target configuration (pending - requires framework target creation)

---

## Future Considerations

### Swift Package Manager

When creating a Package.swift:

```swift
// swift-tools-version:5.5
import PackageDescription

let package = Package(
    name: "MovEncoder2",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .library(
            name: "MovEncoder2",
            targets: ["MovEncoder2"]
        )
    ],
    targets: [
        .target(
            name: "MovEncoder2",
            path: "movencoder2",
            publicHeadersPath: "Public",
            cSettings: [
                .headerSearchPath("Config"),
                .headerSearchPath("Core"),
                .headerSearchPath("Pipeline"),
                .headerSearchPath("IO"),
                .headerSearchPath("Utils")
            ]
        )
    ]
)
```

### CocoaPods

When creating a .podspec:

```ruby
Pod::Spec.new do |s|
  s.name         = "MovEncoder2"
  s.version      = "1.0.0"
  s.summary      = "QuickTime movie transcoding library"
  s.homepage     = "https://github.com/MyCometG3/movencoder2"
  s.license      = { :type => "GPL-2.0", :file => "COPYING.txt" }
  s.author       = "MyCometG3"
  
  s.platform     = :osx, "12.0"
  s.source       = { :git => "https://github.com/MyCometG3/movencoder2.git", :tag => "#{s.version}" }
  
  s.source_files = "movencoder2/**/*.{h,m}"
  s.public_header_files = "movencoder2/Public/*.h"
  
  s.frameworks   = "Foundation", "AVFoundation", "CoreMedia", "CoreVideo", "VideoToolbox", "CoreAudio"
  
  # External dependencies (FFmpeg, x264, x265)
  # These would need to be specified based on installation method
end
```

---

## Resources

- [Apple's Framework Programming Guide](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPFrameworks/)
- [Creating Custom Frameworks](https://developer.apple.com/documentation/xcode/creating-a-custom-framework)
- [Header Visibility](https://developer.apple.com/library/archive/documentation/DeveloperTools/Conceptual/CppRuntimeEnv/Articles/SymbolVisibility.html)

---

## Summary: Command-Line Tool vs Framework

### Current State (Command-Line Tool)

The movencoder2 project currently builds as a **command-line tool**:
- Target: `movencoder2` (type: `com.apple.product-type.tool`)
- Output: Executable binary at `build/Debug/movencoder2` or similar
- Headers: All headers accessible during build via direct `#import` statements
- Usage: Run as CLI tool from terminal

**The command-line tool does not need framework configuration** and can continue to use all headers directly. The Public API structure prepared in this PR serves as documentation of the intended public interface.

### Future State (Framework)

When a framework target is added:
- Target: `MovEncoder2` (type: `com.apple.product-type.framework`)
- Output: `MovEncoder2.framework` bundle
- Headers: Only public headers exposed in framework bundle
- Usage: Link framework into other applications

### Hybrid Approach (Recommended)

The project can support both:
1. **Command-line tool target** - For CLI usage, building the `movencoder2` executable
2. **Framework target** - For library usage, building `MovEncoder2.framework`

Both targets can share the same source files (`.m` files), but the framework target should expose only the public headers while the CLI tool can access all headers.

---

## Notes

This document was created as part of the public/internal API separation initiative. The actual Xcode project modifications should be done using Xcode on macOS for reliability.

**Important:** This document describes **future framework configuration**. The current project is a command-line tool and does not require these configuration steps unless you want to add framework distribution capability.
