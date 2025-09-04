//
//  parseUtil.m
//  movencoder2
//
//  Created by Takashi Mochizuki on 2019/06/16.
//  Copyright © 2019-2023 MyCometG3. All rights reserved.
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

#import "parseUtil.h"

#ifndef ALog
#define ALog(fmt, ...) NSLog((@"%s [Line %d] " fmt), __PRETTY_FUNCTION__, __LINE__, ##__VA_ARGS__)
#endif

NSString* const separator = @";";
NSString* const equal = @"=";
NSString* const optSeparator = @":";

NS_ASSUME_NONNULL_BEGIN

NSNumber* parseInteger(NSString* val) {
    NSScanner *ns = [NSScanner scannerWithString:val];
    NSInteger theValue = 0;
    if ([ns scanInteger:&theValue]) {
        // parse metric prefix - i.e. 1G, 1M, 1k
        if (!ns.atEnd) {
            NSString* result = nil;
            NSCharacterSet* cSet = [NSCharacterSet letterCharacterSet];
            if ([ns scanCharactersFromSet:cSet intoString:&result] && ns.atEnd) {
                if ([result hasPrefix:@"T"])
                    theValue = theValue * 1000*1000*1000*1000;
                else if ([result hasPrefix:@"G"])
                    theValue = theValue * 1000*1000*1000;
                else if ([result hasPrefix:@"M"])
                    theValue = theValue * 1000*1000;
                else if ([result hasPrefix:@"K"])
                    theValue = theValue * 1000;
                else if ([result hasPrefix:@"k"])
                    theValue = theValue * 1000;
                else
                    goto error;
            }
        }
        return [NSNumber numberWithInteger:theValue];
    }
    
error:
    NSLog(@"ERROR: %@ : not Integer", val);
    return nil;
}

NSNumber* parseDouble(NSString* val) {
    NSScanner *ns = [NSScanner scannerWithString:val];
    double theValue = 0.0;
    if ([ns scanDouble:&theValue]) {
        // parse metric prefix - i.e. 1G, 1M, 1k
        if (!ns.atEnd) {
            NSString* result = nil;
            NSCharacterSet* cSet = [NSCharacterSet letterCharacterSet];
            if ([ns scanCharactersFromSet:cSet intoString:&result] && ns.atEnd) {
                if ([result hasPrefix:@"T"])
                    theValue = theValue * 1000*1000*1000*1000;
                else if ([result hasPrefix:@"G"])
                    theValue = theValue * 1000*1000*1000;
                else if ([result hasPrefix:@"M"])
                    theValue = theValue * 1000*1000;
                else if ([result hasPrefix:@"K"])
                    theValue = theValue * 1000;
                else if ([result hasPrefix:@"k"])
                    theValue = theValue * 1000;
                else
                    goto error;
            }
        }
        return [NSNumber numberWithDouble:theValue];
    }
    
error:
    NSLog(@"ERROR: %@ : not Double", val);
    return nil;
}

NSValue* parseSize(NSString* val) {
    NSValue* _Nullable (^toSize)(NSString*, NSString*) = ^(NSString* val, NSString* delimiter) {
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
    NSValue* _Nullable (^toRect)(NSString*, NSString*) = ^(NSString* val, NSString* delimiter) {
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
    NSValue* _Nullable (^toTime)(NSString*, NSString*) = ^(NSString* val, NSString* delimiter) {
        CMTime time = kCMTimeInvalid;
        NSValue* outVal = nil;
        NSArray* array = [val componentsSeparatedByString:delimiter];
        if (array.count == 2) {
            NSNumber* numerator = parseInteger(array[0]);
            NSNumber* denominator = parseInteger(array[1]);
            if (numerator && denominator) {
                time = CMTimeMake([numerator intValue], [denominator intValue]);
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
    
    NSNumber* numValue = parseDouble(val);
    if (numValue != nil) {
        double doubleValue = [numValue doubleValue];
        if (doubleValue != 0) {
            int64_t numerator = 90000 / doubleValue;
            int32_t denominator = 90000;
            CMTime timeValue = CMTimeMake(numerator, denominator);
            outValue = [NSValue valueWithCMTime:timeValue];
        }
        if (outValue) return outValue;
    }
    
error:
    NSLog(@"ERROR: %@ : not Time", val);
    return nil;
}

NSNumber* parseBool(NSString* val) {
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
    NSLog(@"ERROR: %@ : not Boolean", val);
    return nil;
}

NSDictionary* parseCodecOptions(NSString* val) {
    NSMutableArray* skipped = [NSMutableArray new];
    NSMutableDictionary *options = [NSMutableDictionary new];
    NSArray *optArray = [val componentsSeparatedByString:optSeparator];
    for (NSString* opt in optArray) {
        NSArray *optParse = [opt componentsSeparatedByString:equal];
        if (optParse.count == 2) {
            NSString* optKey = optParse[0];
            NSString* optVal = optParse[1];
            options[optKey] = optVal;
        } else {
            [skipped addObject:opt];
        }
    }
    if (skipped.count) {
        NSLog(@"ERROR: Skipped = %@", skipped);
    }
    if (options.allKeys.count) {
        return [options copy];
    }
    
error:
    NSLog(@"ERROR: %@ : not codec options", val);
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
