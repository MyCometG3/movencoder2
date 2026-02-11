# Xcode Project Setup for Public API

**Last Updated:** February 2026

## Overview

This document provides instructions for configuring the Xcode project to properly expose public headers for framework distribution.

---

## ✅ Current Project Status

**The movencoder2 project now includes both a command-line tool and a framework target.**

- **movencoder2**: Command-line tool target (`com.apple.product-type.tool`)
- **MovEncoder2Framework**: Framework target (`com.apple.product-type.framework`)
- **movencoder2Tests**: Unit test bundle

You can verify the targets with:
```bash
xcodebuild -list -project movencoder2.xcodeproj
```

**This document provides reference information** about the framework target configuration. The framework has been successfully implemented with proper public header exposure and module support.

### About This Document

This document describes:
1. The framework target configuration that has been implemented
2. How public headers are exposed for framework distribution
3. Technical details of the Xcode project setup for reference and maintenance

For a complete guide on using the framework, see `FRAMEWORK_TARGET_SETUP.md`.

---

## Framework Target Implementation

The MovEncoder2Framework target has been successfully created and configured with the following setup:

### Target Configuration

**Target Name:** MovEncoder2Framework  
**Product Name:** MovEncoder2.framework  
**Type:** macOS Framework  
**Architecture:** arm64  
**Deployment Target:** macOS 12.0

### Implementation Details

The framework target was created alongside the existing command-line tool target:
- All source files (`.m` files except `main.m`) are included in the framework
- Public headers from `movencoder2/Public/` are properly exposed
- CLI tool and framework coexist, sharing the same codebase
- Both targets can be built and distributed independently

---

## Public Headers Configuration

### Headers in Framework Target

The following public headers are configured and exposed in the framework:

- **`MovEncoder2.h`** - Umbrella header that imports all public APIs
- **`METranscoder.h`** - Main transcoding controller API
- **`MEVideoEncoderConfig.h`** - Type-safe encoder configuration
- **`METypes.h`** - Public type definitions and enums

All headers are marked as "Public" in the MovEncoder2Framework target's Target Membership settings.

**Note:** Internal headers (in Config/, Core/, Pipeline/, IO/, Utils/) remain marked as "Project" or "Private" and are not exposed in the framework bundle.

### Build Settings

The framework target is configured with the following key settings:

**Header Configuration:**
- **Public Headers Folder Path**: `$(CONTENTS_FOLDER_PATH)/Headers`
- **Module Name**: `MovEncoder2`
- **Defines Module**: YES (enables module support)

**Search Paths:**
- **Header Search Paths**: Includes `$(SRCROOT)/movencoder2/Public` and other source directories

---

## Framework Structure

The built framework follows Apple's standard framework layout:

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

### Test Public API Import

The framework's public API can be tested with the following code:

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
- [x] Framework target configuration (completed - MovEncoder2Framework target)

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
  s.license      = { :type => "GPL-2.0-or-later", :file => "COPYING.txt" }
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

This document describes the Xcode project configuration for the public/internal API separation and framework target implementation. The MovEncoder2Framework target has been successfully implemented and configured.

**Status:** ✅ Framework target fully implemented and operational. Both CLI tool and framework targets coexist and build successfully.
