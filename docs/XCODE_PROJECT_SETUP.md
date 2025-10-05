# Xcode Project Setup for Public API

## Overview

This document provides instructions for configuring the Xcode project to properly expose public headers for framework distribution.

---

## Steps to Configure Public Headers

### 1. Add Public Directory to Xcode Project

1. Open `movencoder2.xcodeproj` in Xcode
2. In the Project Navigator, right-click on the `movencoder2` group
3. Select "Add Files to movencoder2..."
4. Navigate to and select the `movencoder2/Public` folder
5. Ensure "Create groups" is selected (not "Create folder references")
6. Click "Add"

### 2. Mark Headers as Public

For each header in the `Public/` directory:

1. Select the header file in the Project Navigator
2. Open the File Inspector (⌥⌘1)
3. In the "Target Membership" section, locate the framework target
4. Change the header visibility from "Project" to **"Public"**

Public headers to mark:
- `MovEncoder2.h` (umbrella header)
- `METranscoder.h`
- `MEVideoEncoderConfig.h`
- `METypes.h`

### 3. Set Framework Umbrella Header

1. Select the movencoder2 target in the project editor
2. Go to "Build Settings" tab
3. Search for "umbrella"
4. Set **"Public Headers Folder Path"** to: `include/MovEncoder2`
5. Set **"Module Name"** to: `MovEncoder2`

### 4. Configure Header Search Paths

1. In Build Settings, search for "Header Search Paths"
2. Add the following paths (if not already present):
   - `$(SRCROOT)/movencoder2/Public` (recursive)
   - `$(SRCROOT)/movencoder2` (non-recursive, for internal builds only)

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

- [ ] Public directory added to Xcode project
- [ ] All public headers marked as "Public" in target membership
- [ ] Umbrella header configured in build settings
- [ ] Framework builds without errors
- [ ] Public headers accessible via `#import <MovEncoder2/...>`
- [ ] Internal headers not visible in framework bundle
- [ ] Test app successfully links against framework
- [ ] No private symbols exposed in public headers
- [ ] Documentation builds correctly (if using HeaderDoc/Jazzy)

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

## Notes

This document was created as part of the public/internal API separation initiative. The actual Xcode project modifications should be done using Xcode on macOS for reliability.
