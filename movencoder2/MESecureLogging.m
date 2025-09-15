//
//  MESecureLogging.m
//  movencoder2
//
//  Created by Security Enhancement
//

#import "MESecureLogging.h"

NSString* sanitizeLogString(NSString* input) {
    if (!input) {
        return @"(null)";
    }
    
    // Replace % with %% to prevent format string interpretation
    // This ensures that user-controlled strings cannot contain format specifiers
    NSString* sanitized = [input stringByReplacingOccurrencesOfString:@"%" withString:@"%%"];
    
    // Also sanitize common format specifiers that might be used in attacks
    // Note: This is defensive - the main protection is using fixed format strings
    sanitized = [sanitized stringByReplacingOccurrencesOfString:@"\\n" withString:@"\\\\n"];
    sanitized = [sanitized stringByReplacingOccurrencesOfString:@"\\t" withString:@"\\\\t"];
    
    return sanitized;
}
