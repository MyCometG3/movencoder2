# AVAssetWriter Temporary File Cleanup

## Overview
This document describes the implementation of automatic temporary file cleanup for AVAssetWriter in movencoder2.

## Problem
AVAssetWriter creates temporary files during QuickTime export operations. These temporary files follow a naming pattern like:
```
outputfile.mov.sb-94f28a92-xDAs6Q
```

These files can remain in the output directory even after successful export completion, resulting in:
- Unnecessary disk usage
- Confusion for users seeing multiple similar files
- Potential cleanup burden on user workflows

## Solution
The solution implements automatic detection and removal of AVAssetWriter temporary files after successful export completion.

### Implementation Details

#### Location
- **File**: `movencoder2/Core/METranscoder.m`
- **Method**: `cleanupTemporaryFilesForOutput:(NSURL*)outputURL`
- **Trigger**: Called after all export attempts (success, failure, or cancellation) in `exportCustomOnError:`

#### Detection Logic
1. **Sorting**: All files in the output directory are sorted by modification date (most recent first) before validation
2. **Timestamp Validation**: Files are first checked for modification time within the last 1 minute
3. **Pattern Matching**: Files that pass timestamp validation are then checked for:
   - Start with the output filename as a prefix, AND
   - Contain `.sb-` in the filename (AVAssetWriter pattern)
4. **Modern API Usage**: Uses `contentsOfDirectoryAtURL:includingPropertiesForKeys:options:error:` for efficient file attribute retrieval

#### Processing Order (Optimized)
The method processes files in this optimized order:
1. Retrieve all files with pre-fetched modification date and name attributes
2. Sort all files by modification timestamp (most recent first)
3. For each file in sorted order:
   - First: Check timestamp validity (fast operation)
   - Then: Check filename pattern (only if timestamp is valid)
   - Add to cleanup candidates if both checks pass
4. Remove all candidate files

5. **Example Matches**:
   ```
   sample.mov.sb-94f28a92-xDAs6Q  ✓ (will be removed)
   sample.mov.sb-abc123-XyZ789    ✓ (will be removed)
   sample.mov.bak                 ✗ (no .sb- pattern)
   other.mov.sb-123456-AbCdEf     ✗ (different prefix)
   ```

#### Safety Features
- **Non-destructive**: Only affects files matching the exact AVAssetWriter temporary pattern
- **Time-bounded**: Only removes files modified within the last 1 minute (conservative approach)
- **Optimized processing**: Timestamp validation before filename validation (avoids unnecessary string operations)
- **Pre-sorted**: Files processed in timestamp order for predictable behavior
- **Efficient**: Uses modern URL-based APIs with pre-fetched file attributes
- **Error handling**: Graceful failure handling with comprehensive logging
- **Logging**: Reports all cleanup actions and failures via SecureLog

#### Integration
The cleanup is triggered after all export attempts, ensuring temporary files are cleaned up regardless of export outcome:
```objective-c
// Clean up any temporary files created by AVAssetWriter (on all paths)
[self cleanupTemporaryFilesForOutput:self.outputURL];
```

## Testing
A test demonstration is provided in `test_temp_cleanup.m` that shows:
- Creation of mock temporary files
- Execution of cleanup logic
- Verification of correct files being removed/preserved

## Implementation History & Optimizations

### Initial Implementation (commit 9a6022c)
- Basic cleanup method with path-based file enumeration
- 10-minute time window for safety
- Simple filtering approach

### First Optimization (commit 0515c20)
- Switched to URL-based API (`contentsOfDirectoryAtURL:includingPropertiesForKeys:options:error:`)
- Reduced time window from 10 minutes to 1 minute
- Added file sorting by modification timestamp

### Performance Optimization (commit 52f625b)
- Moved sorting to occur before validation (not after filtering)
- Eliminated redundant sorting step
- Improved performance for large directories

### Final Refinements (commit ebffe9d)
- Optimized validation order: timestamp first, then filename pattern
- Concatenated filename comparison into single conditional
- Maximized efficiency by avoiding string operations on old files

## Impact
- **Minimal**: Only 2 files modified with surgical changes
- **Safe**: No impact on export logic or error handling
- **Focused**: Only affects successful export completion
- **Backwards compatible**: No changes to public API

## Files Modified
1. `movencoder2/Core/METranscoder+Internal.h` - Added method declaration (path updated)
2. `movencoder2/Core/METranscoder.m` - Added implementation and integration (path updated)