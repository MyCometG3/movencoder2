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
- **File**: `movencoder2/METranscoder.m`
- **Method**: `cleanupTemporaryFilesForOutput:(NSURL*)outputURL`
- **Trigger**: Called after successful export completion in `exportCustomOnError:`

#### Detection Logic
1. **Pattern Matching**: Files must:
   - Start with the output filename as a prefix
   - Contain `.sb-` in the filename (AVAssetWriter pattern)

2. **Time-based Safety**: Only removes files modified within the last 1 minute to avoid:
   - Removing unrelated files with similar names
   - Interfering with concurrent operations

3. **Timestamp Ordering**: All files are sorted by modification date (most recent first) before validation for more efficient processing

4. **Modern API Usage**: Uses `contentsOfDirectoryAtURL:includingPropertiesForKeys:options:error:` for efficient file attribute retrieval

3. **Example Matches**:
   ```
   sample.mov.sb-94f28a92-xDAs6Q  ✓ (will be removed)
   sample.mov.sb-abc123-XyZ789    ✓ (will be removed)
   sample.mov.bak                 ✗ (no .sb- pattern)
   other.mov.sb-123456-AbCdEf     ✗ (different prefix)
   ```

#### Safety Features
- **Non-destructive**: Only affects files matching the exact pattern
- **Time-bounded**: Only removes recently modified files (within 1 minute)
- **Ordered processing**: All files sorted by modification date before validation for optimal performance
- **Efficient**: Uses modern URL-based APIs for better performance
- **Error handling**: Graceful failure handling with comprehensive logging
- **Logging**: Reports cleanup actions and failures via SecureLog

#### Integration
The cleanup is triggered only in the success path:
```objective-c
if (self.finalSuccess) {
    SecureLog(@"[METranscoder] Export session completed.");
    // Clean up any temporary files created by AVAssetWriter
    [self cleanupTemporaryFilesForOutput:self.outputURL];
}
```

## Testing
A test demonstration is provided in `test_temp_cleanup.m` that shows:
- Creation of mock temporary files
- Execution of cleanup logic
- Verification of correct files being removed/preserved

## Impact
- **Minimal**: Only 2 files modified with surgical changes
- **Safe**: No impact on export logic or error handling
- **Focused**: Only affects successful export completion
- **Backwards compatible**: No changes to public API

## Files Modified
1. `movencoder2/METranscoder+Internal.h` - Added method declaration
2. `movencoder2/METranscoder.m` - Added implementation and integration