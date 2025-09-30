//
//  MESecureLogging.m
//  movencoder2
//
//  Created by Security Enhancement
//

#define _GNU_SOURCE
#import "MESecureLogging.h"
#import <stdarg.h>

#import <libavutil/log.h>

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

// Note: We intentionally do NOT escape newlines here for FFmpeg logging compatibility.
// Preserving newlines in log output is required for correct integration with FFmpeg's log handling.
static NSString* sanitizeForOutput(NSString* s) {
    return sanitizeStringWithOptions(s, SanitizeOptionsEscapeTab | SanitizeOptionsEscapeCarriageReturn);
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

static void ffmpeg_log_callback(void *ptr, int level, const char *fmt, va_list vl) {
    // Respect global FFmpeg log level
    if (level > av_log_get_level()) return;
    // Compose message
    va_list vl_copy;
    va_copy(vl_copy, vl);
    int needed = vsnprintf(NULL, 0, fmt, vl_copy);
    va_end(vl_copy);
    if (needed < 0) {
        // Formatting error, fallback to empty string
        NSString *line = @"";
        if (level <= AV_LOG_ERROR) {
            SecureErrorLog(line);
        } else if (level <= AV_LOG_WARNING) {
            SecureLog(line);
        } else if (level <= AV_LOG_INFO) {
            SecureLog(line);
        } else {
            SecureDebugLog(line);
        }
        return;
    }
    size_t bufsize = (size_t)needed + 1;
    char *buf = (char *)malloc(bufsize);
    if (!buf) {
        // Allocation failed, fallback to empty string
        NSString *line = @"";
        if (level <= AV_LOG_ERROR) {
            SecureErrorLog(line);
        } else if (level <= AV_LOG_WARNING) {
            SecureLog(line);
        } else if (level <= AV_LOG_INFO) {
            SecureLog(line);
        } else {
            SecureDebugLog(line);
        }
        return;
    }
    vsnprintf(buf, bufsize, fmt, vl);
    NSString *line = [NSString stringWithUTF8String:buf ?: ""]; // may contain '\n'
    free(buf);
    // FFmpeg often ends lines with '\n'; NSLog will add its own newline, so trim trailing newlines to avoid blank lines
    while ([line hasSuffix:@"\n"]) {
        line = [line substringToIndex:line.length - 1];
    }
    // Map level to our logger
    if (level <= AV_LOG_ERROR) {
        SecureErrorLog(line);
    } else if (level <= AV_LOG_WARNING) {
        SecureLog(line);
    } else if (level <= AV_LOG_INFO) {
        SecureLog(line);
    } else {
        SecureDebugLog(line);
    }
}

void SetupFFmpegLogging(void) {
    av_log_set_callback(ffmpeg_log_callback);
}

static void multiline_emit(BOOL debug, NSString *header, NSString *footer, NSString *content) {
    if (header && header.length) {
        if (debug) {
            SecureDebugLog(header);
        } else {
            SecureLog(header);
        }
    }
    if (content) {
        [content enumerateLinesUsingBlock:^(NSString *line, BOOL *stop) {
            if (debug) {
                SecureDebugLogf(@"%@", line);
            } else {
                SecureLogf(@"%@", line);
            }
        }];
    }
    if (footer && footer.length) {
        if (debug) {
            SecureDebugLog(footer);
        } else {
            SecureLog(footer);
        }
    }
}

void SecureInfoMultiline(NSString *header, NSString *footer, NSString *content) {
    multiline_emit(NO, header, footer, content);
}

void SecureDebugMultiline(NSString *header, NSString *footer, NSString *content) {
    multiline_emit(YES, header, footer, content);
}
