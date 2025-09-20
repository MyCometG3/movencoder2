//
//  MESecureLogging.m
//  movencoder2
//
//  Created by Security Enhancement
//

#import "MESecureLogging.h"
#import <stdarg.h>

typedef NS_OPTIONS(NSUInteger, SanitizeOptions) {
    SanitizeOptionsNone = 0,
    SanitizeOptionsEscapePercent = 1 << 0,
    SanitizeOptionsEscapeNewline = 1 << 1,
    SanitizeOptionsEscapeTab = 1 << 2,
    SanitizeOptionsEscapeCarriageReturn = 1 << 3
};

static NSString* sanitizeStringWithOptions(NSString* input, SanitizeOptions options) {
    if (!input) return @"(null)";
    
    NSString* result = input;
    
    if (options & SanitizeOptionsEscapePercent) {
        result = [result stringByReplacingOccurrencesOfString:@"%" withString:@"%%"];
    }
    if (options & SanitizeOptionsEscapeNewline) {
        result = [result stringByReplacingOccurrencesOfString:@"\n" withString:@"\\n"];
    }
    if (options & SanitizeOptionsEscapeTab) {
        result = [result stringByReplacingOccurrencesOfString:@"\t" withString:@"\\t"];
    }
    if (options & SanitizeOptionsEscapeCarriageReturn) {
        result = [result stringByReplacingOccurrencesOfString:@"\r" withString:@"\\r"];
    }
    
    return result;
}

static NSString* sanitizeForOutput(NSString* s) {
    return sanitizeStringWithOptions(s, SanitizeOptionsEscapeNewline | SanitizeOptionsEscapeTab | SanitizeOptionsEscapeCarriageReturn);
}

NSString* sanitizeLogString(NSString* input) {
    return sanitizeStringWithOptions(input, SanitizeOptionsEscapePercent | SanitizeOptionsEscapeNewline | SanitizeOptionsEscapeTab);
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
