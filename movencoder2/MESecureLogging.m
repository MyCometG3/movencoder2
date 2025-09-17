//
//  MESecureLogging.m
//  movencoder2
//
//  Created by Security Enhancement
//

#import "MESecureLogging.h"
#import <stdarg.h>

static NSString* sanitizeForOutput(NSString* s) {
    if (!s) return @"(null)";
    // Replace actual control characters with escaped representations to avoid multiline/log injection
    NSString* out = [s stringByReplacingOccurrencesOfString:@"\n" withString:@"\\n"];
    out = [out stringByReplacingOccurrencesOfString:@"\r" withString:@"\\r"];
    out = [out stringByReplacingOccurrencesOfString:@"\t" withString:@"\\t"];
    return out;
}

NSString* sanitizeLogString(NSString* input) {
    if (!input) return @"(null)";
    // Legacy behavior: escape '%' so that if this string was (incorrectly) used as a format it won't be interpreted.
    // Also escape backslash-newline/tab sequences.
    NSString* s = [input stringByReplacingOccurrencesOfString:@"%" withString:@"%%"];
    s = [s stringByReplacingOccurrencesOfString:@"\n" withString:@"\\n"];
    s = [s stringByReplacingOccurrencesOfString:@"\t" withString:@"\\t"];
    return s;
}

void SecureLog(NSString* message) {
    NSString* out = sanitizeForOutput(message);
    NSLog(@"[INFO] %@", out);
}

void SecureErrorLog(NSString* message) {
    NSString* out = sanitizeForOutput(message);
    NSLog(@"[ERROR] %@", out);
}

void SecureDebugLog(NSString* message) {
    NSString* out = sanitizeForOutput(message);
    NSLog(@"[DEBUG] %@", out);
}

void SecureLogf(NSString* format, ...) {
    va_list args;
    va_start(args, format);
    NSString* formatted = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    NSString* out = sanitizeForOutput(formatted);
    NSLog(@"[INFO] %@", out);
}

void SecureErrorLogf(NSString* format, ...) {
    va_list args;
    va_start(args, format);
    NSString* formatted = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    NSString* out = sanitizeForOutput(formatted);
    NSLog(@"[ERROR] %@", out);
}

void SecureDebugLogf(NSString* format, ...) {
    va_list args;
    va_start(args, format);
    NSString* formatted = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    NSString* out = sanitizeForOutput(formatted);
    NSLog(@"[DEBUG] %@", out);
}
