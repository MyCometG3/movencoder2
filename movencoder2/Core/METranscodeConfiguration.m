//
//  METranscodeConfiguration.m
//  movencoder2
//
//  Created by OpenCode.
//  Copyright © 2026 MyCometG3. All rights reserved.
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

#import "METranscodeConfiguration.h"

NS_ASSUME_NONNULL_BEGIN

@implementation METranscodeConfiguration

- (instancetype)init
{
    if (self = [super init]) {
        _encodingParams = [NSMutableDictionary dictionary];
        _timeRange = kCMTimeRangeInvalid;
        _verbose = NO;
        _logLevel = MELogLevelInfo;
        _callbackQueue = nil;
        _startCallback = nil;
        _progressCallback = nil;
        _completionCallback = nil;
        return self;
    }
    return nil;
}

@end

NS_ASSUME_NONNULL_END
