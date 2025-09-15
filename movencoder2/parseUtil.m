//
//  parseUtil.m
//  movencoder2
//
//  Created by Takashi Mochizuki on 2019/06/16.
//  Copyright © 2019-2025 MyCometG3. All rights reserved.
//

/*
 * This file is part of movencoder2.
 *
 * movencoder2 is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * movencoder2 is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with movencoder2; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301  USA
 */

#import "MECommon.h"
#import "parseUtil.h"
#include <ctype.h>

NSString* const separator = @";";
NSString* const equal = @"=";
NSString* const optSeparator = @":";

NS_ASSUME_NONNULL_BEGIN

NSNumber* parseInteger(NSString* val) {
    // Trim whitespace and newlines from input
    val = [val stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    
    NSScanner *ns = [NSScanner scannerWithString:val];
    long long theValue = 0;
    if ([ns scanLongLong:&theValue]) {
        // parse metric prefix - accept only a single-letter suffix (K/M/G/T)
        if (!ns.atEnd) {
            NSString* suffix = nil;
            NSCharacterSet* cSet = [NSCharacterSet letterCharacterSet];
            if ([ns scanCharactersFromSet:cSet intoString:&suffix] && ns.atEnd) {
                if (suffix.length != 1) goto error; // reject multi-letter suffix like "MB"
                unichar ch = [suffix characterAtIndex:0];
                long long multiplier = 1;
                switch (toupper((int)ch)) {
                    case 'T': multiplier = 1000LL * 1000LL * 1000LL * 1000LL; break;
                    case 'G': multiplier = 1000LL * 1000LL * 1000LL; break;
                    case 'M': multiplier = 1000LL * 1000LL; break;
                    case 'K': multiplier = 1000LL; break;
                    default: goto error;
                }
                // overflow check before multiplication
                if (theValue > 0 && (unsigned long long)theValue > ULLONG_MAX / (unsigned long long)multiplier) goto error;
                if (theValue < 0) {
                    // Handle INT64_MIN edge case: -INT64_MIN causes undefined behavior due to overflow
                    if (theValue == INT64_MIN) goto error;
                    if ((unsigned long long)(-theValue) > ULLONG_MAX / (unsigned long long)multiplier) goto error;
                }
                long long result = theValue * multiplier;
                return [NSNumber numberWithLongLong:result];
            }
        }
        return [NSNumber numberWithLongLong:theValue];
    }

error:
    NSLog(@"ERROR: '%@' is not a valid integer value (optionally with K/M/G/T suffix, 1000-base)", val);
    return nil;
}

NSNumber* parseDouble(NSString* val) {
    // Trim whitespace and newlines from input
    val = [val stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    
    NSScanner *ns = [NSScanner scannerWithString:val];
    double theValue = 0.0;
    if ([ns scanDouble:&theValue]) {
        // parse metric prefix - accept only a single-letter suffix (K/M/G/T)
        if (!ns.atEnd) {
            NSString* suffix = nil;
            NSCharacterSet* cSet = [NSCharacterSet letterCharacterSet];
            if ([ns scanCharactersFromSet:cSet intoString:&suffix] && ns.atEnd) {
                if (suffix.length != 1) goto error; // reject multi-letter suffix
                unichar ch = [suffix characterAtIndex:0];
                double multiplier = 1.0;
                switch (toupper((int)ch)) {
                    case 'T': multiplier = 1e12; break;
                    case 'G': multiplier = 1e9; break;
                    case 'M': multiplier = 1e6; break;
                    case 'K': multiplier = 1e3; break;
                    default: goto error;
                }
                double result = theValue * multiplier;
                if (!isfinite(result)) goto error;
                return [NSNumber numberWithDouble:result];
            }
        }
        return [NSNumber numberWithDouble:theValue];
    }

error:
    NSLog(@"ERROR: '%@' is not a valid double value (optionally with K/M/G/T suffix, 1000-base)", val);
    return nil;
}

NSValue* parseSize(NSString* val) {
    NSValue* _Nullable (^toSize)(NSString*, NSString*) = ^NSValue* (NSString* val, NSString* delimiter) {
        NSValue* outVal = nil;
        NSArray* array = [val componentsSeparatedByString:delimiter];
        if (array.count == 2) {
            NSNumber* num1 = parseDouble(array[0]);
            NSNumber* num2 = parseDouble(array[1]);
            if (num1 && num2) {
                NSSize size = NSMakeSize(num1.doubleValue, num2.doubleValue);
                outVal = [NSValue valueWithSize:size];
            }
        }
        return outVal;
    };
    
    NSValue* outValue = nil;
    for (NSString* delimiter in @[@":",@"/",@"x",@","]) {
        outValue = toSize(val, delimiter);
        if (outValue) return outValue;
    }
    
error:
    NSLog(@"ERROR: %@ : not Size", val);
    return nil;
}

NSValue* parseRect(NSString* val) {
    NSValue* _Nullable (^toRect)(NSString*, NSString*) = ^NSValue* (NSString* val, NSString* delimiter) {
        NSValue* outVal = nil;
        NSArray* array = [val componentsSeparatedByString:delimiter];
        if (array.count == 4) {
            NSNumber* num1 = parseDouble(array[0]);
            NSNumber* num2 = parseDouble(array[1]);
            NSNumber* num3 = parseDouble(array[2]);
            NSNumber* num4 = parseDouble(array[3]);
            if (num1 && num2 && num3 && num4) {
                NSRect rect = NSMakeRect(num1.doubleValue, num2.doubleValue,
                                         num3.doubleValue, num4.doubleValue);
                outVal = [NSValue valueWithRect:rect];
            }
        }
        return outVal;
    };
    
    NSValue* outValue = nil;
    for (NSString* delimiter in @[@":",@"/",@"x",@","]) {
        outValue = toRect(val, delimiter);
        if (outValue) return outValue;
    }
    
error:
    NSLog(@"ERROR: %@ : not Rect", val);
    return nil;
}

NSValue* parseTime(NSString* val) {
    // Try to interpret as a rational number first
    //   "30000:1001" -> CMTimeMake(30000, 1001) (frames per second)
    NSValue* _Nullable (^toTime)(NSString*, NSString*) = ^NSValue* (NSString* val, NSString* delimiter) {
         NSValue* outVal = nil;
         NSArray* array = [val componentsSeparatedByString:delimiter];
         if (array.count == 2) {
             NSNumber* numerator = parseInteger(array[0]);
             NSNumber* denominator = parseInteger(array[1]);
             if (numerator && denominator) {
                 long long numeratorLL = [numerator longLongValue];
                 long long denominatorLL = [denominator longLongValue];
                 if (denominatorLL <= 0 || numeratorLL <= 0) return nil;
                 if (denominatorLL > INT32_MAX) return nil;
                 CMTime time = CMTimeMake((int64_t)numeratorLL, (int32_t)denominatorLL);
                 outVal = [NSValue valueWithCMTime:time];
             }
         }
         return outVal;
     };
    
    NSValue* outValue = nil;
    for (NSString* delimiter in @[@":",@"/",@"x",@","]) {
        outValue = toTime(val, delimiter);
        if (outValue) return outValue;
    }
    
    // Interpret as a plain floating point value (assumed as frame rate)
    //   "29.97" -> CMTimeMake(90000, 3003) (frames per second)
    // NOTE: Timebase 90000 is used as project-wide timescale
    NSNumber* numValue = parseDouble(val);
    if (numValue != nil) {
        double fps = [numValue doubleValue];
        if (!(fps > 0.0 && isfinite(fps))) {
            goto error;
        }
        int64_t numerator = 90000;  // Use timebase 90000 as project-wide timescale
        int32_t denominator = (int32_t)floor((double)numerator / fps);
        CMTime timeValue = CMTimeMake(numerator, denominator);
        outValue = [NSValue valueWithCMTime:timeValue];
        if (outValue) return outValue;
    }
    
error:
    NSLog(@"ERROR: %@ : not Time", val);
    return nil;
}

NSNumber* parseBool(NSString* val) {
    // Trim whitespace and newlines from input
    val = [val stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    
    BOOL (^oneOf)(NSArray*, NSString*) = ^(NSArray* array, NSString* value) {
        for (NSString* item in array)
            if ([item caseInsensitiveCompare:value] == NSOrderedSame)
                return YES;
        return NO;
    };
    BOOL isYes = oneOf(@[@"YES", @"Y", @"TRUE", @"ON", @"1"], val);
    BOOL isNo = oneOf(@[@"NO", @"N", @"FALSE", @"OFF", @"0"], val);
    if (isYes) return @YES;
    if (isNo) return @NO;
    
error:
    NSLog(@"ERROR: '%@' is not a valid boolean value (expected: YES/NO, TRUE/FALSE, ON/OFF, 1/0)", val);
    return nil;
}

NSDictionary* parseCodecOptions(NSString* val) {
    // Trim whitespace and newlines from input
    val = [val stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    
    NSMutableArray* skipped = [NSMutableArray new];
    NSMutableDictionary *options = [NSMutableDictionary new];
    NSArray *optArray = [val componentsSeparatedByString:optSeparator];
    for (NSString* optOriginal in optArray) {
        // Trim each option as well
        NSString* opt = [optOriginal stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (opt.length == 0) continue; // Skip empty options
        
        NSArray *optParse = [opt componentsSeparatedByString:equal];
        if (optParse.count == 2) {
            NSString* optKey = [optParse[0] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            NSString* optVal = [optParse[1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if (optKey.length > 0) {
                options[optKey] = optVal;
            } else {
                [skipped addObject:opt];
            }
        } else {
            [skipped addObject:opt];
        }
    }
    
    if (skipped.count) {
        NSLog(@"ERROR: Invalid codec options format in '%@', skipped options: %@", val, skipped);
    }
    
    if (options.allKeys.count) {
        return [options copy];
    }
    
    NSLog(@"ERROR: '%@' contains no valid codec options (expected format: key1=value1:key2=value2)", val);
    return nil;
}

NSNumber* parseLayoutTag(NSString* val) {
    // First, try to interpret as an integer value
    NSNumber* num = parseInteger(val);
    if (num != nil) return num;
    // Constant name to value table (AAC layouts only)
    static NSDictionary<NSString*, NSNumber*>* table = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        table = @{
            @"Mono": @(kAudioChannelLayoutTag_Mono),
            @"Stereo": @(kAudioChannelLayoutTag_Stereo),
            @"AAC_3_0": @(kAudioChannelLayoutTag_AAC_3_0),
            @"AAC_4_0": @(kAudioChannelLayoutTag_AAC_4_0),
            @"AAC_5_0": @(kAudioChannelLayoutTag_AAC_5_0),
            @"AAC_5_1": @(kAudioChannelLayoutTag_AAC_5_1),
            @"AAC_6_1": @(kAudioChannelLayoutTag_AAC_6_1),
            @"AAC_7_1": @(kAudioChannelLayoutTag_AAC_7_1),
            @"AAC_7_1_C": @(kAudioChannelLayoutTag_AAC_7_1_C),
            @"AAC_Quadraphonic": @(kAudioChannelLayoutTag_AAC_Quadraphonic),
            @"AAC_6_0": @(kAudioChannelLayoutTag_AAC_6_0),
            @"AAC_7_0": @(kAudioChannelLayoutTag_AAC_7_0),
            @"AAC_Octagonal": @(kAudioChannelLayoutTag_AAC_Octagonal),
        };
    });
    NSNumber* tag = table[val];
    if (tag != nil) return tag;
    NSLog(@"ERROR: %@ : not valid AAC layout name or integer", val);
    return nil;
}

NS_ASSUME_NONNULL_END
