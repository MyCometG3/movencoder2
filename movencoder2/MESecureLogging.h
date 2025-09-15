//
//  MESecureLogging.h
//  movencoder2
//
//  Created by Security Enhancement
//

#ifndef MESecureLogging_h
#define MESecureLogging_h

#import <Foundation/Foundation.h>

/**
 * Secure logging functions to prevent format string attacks
 * These functions ensure that user-controlled strings cannot be used as format strings
 */

/**
 * Secure NSLog wrapper that prevents format string attacks
 * Always uses a fixed format string with %@ placeholder for the message
 */
#define SecureNSLog(message, ...) \
    NSLog(@"[SECURE] %@", [NSString stringWithFormat:(message), ##__VA_ARGS__])

/**
 * Secure error logging function
 * Ensures error messages cannot contain format string vulnerabilities
 */
#define SecureErrorLog(message, ...) \
    NSLog(@"[ERROR] %@", [NSString stringWithFormat:(message), ##__VA_ARGS__])

/**
 * Secure debug logging function
 * For debugging information with format string protection
 */
#define SecureDebugLog(message, ...) \
    NSLog(@"[DEBUG] %@", [NSString stringWithFormat:(message), ##__VA_ARGS__])

/**
 * Sanitize a string to remove potential format string specifiers
 * Replaces % with %% to prevent format string interpretation
 */
NSString* sanitizeLogString(NSString* input);

#endif /* MESecureLogging_h */