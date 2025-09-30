//
//  MESecureLogging.h
//  movencoder2
//
//  Created by Security Enhancement
//

#ifndef MESecureLogging_h
#define MESecureLogging_h

#import <Foundation/Foundation.h>

// Secure logging functions (prevent format-string attacks)
void SecureLog(NSString* message);
void SecureErrorLog(NSString* message);
void SecureDebugLog(NSString* message);

// Formatted logging (internally sanitized)
void SecureLogf(NSString* format, ...) NS_FORMAT_FUNCTION(1,2);
void SecureErrorLogf(NSString* format, ...) NS_FORMAT_FUNCTION(1,2);
void SecureDebugLogf(NSString* format, ...) NS_FORMAT_FUNCTION(1,2);

// String sanitization
NSString* sanitizeLogString(NSString* input);

// Setup FFmpeg log redirection to our secure logging (call once during initialization)
void SetupFFmpegLogging(void);

// Multiline helpers: output header, each content line, then footer (any may be nil)
void SecureInfoMultiline(NSString *header, NSString *footer, NSString *content);
void SecureDebugMultiline(NSString *header, NSString *footer, NSString *content);

#endif /* MESecureLogging_h */
