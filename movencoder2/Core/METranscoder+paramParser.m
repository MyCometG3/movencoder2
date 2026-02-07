//
//  METranscoder.m
//  movencoder2
//
//  Created by Takashi Mochizuki on 2018/11/03.
//  Copyright © 2018-2026 MyCometG3. All rights reserved.
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

#import "METranscoder+Internal.h"

/* =================================================================================== */
// MARK: -
/* =================================================================================== */

NS_ASSUME_NONNULL_BEGIN

@implementation METranscoder (paramParser)

- (BOOL) copyOtherMedia
{
    NSNumber* numCopyOtherMedia = self.param[kCopyOtherMediaKey];
    BOOL copyOtherMedia = (numCopyOtherMedia != nil) ? numCopyOtherMedia.boolValue : FALSE;
    return copyOtherMedia;
}

- (BOOL) audioEncode
{
    NSNumber* numAudioEncode = self.param[kAudioEncodeKey];
    BOOL audioEncode = (numAudioEncode != nil) ? numAudioEncode.boolValue : FALSE;
    return audioEncode;
}

- (NSString*) audioFourcc
{
    NSString* fourcc = self.param[kAudioCodecKey];
    return fourcc;
}

- (int) audioBitRate
{
    NSNumber* numAudioKbps = self.param[kAudioKbpsKey];
    float targetKbps = (numAudioKbps != nil) ? numAudioKbps.floatValue : 128;
    int targetBitrate = (int)(targetKbps * 1000);
    return targetBitrate;
}

- (int) lpcmDepth
{
    NSNumber* numPCMDepth = self.param[kLPCMDepthKey];
    int lpcmDepth = (numPCMDepth != nil) ? numPCMDepth.intValue : 16;
    return lpcmDepth;
}

- (uint32_t) audioChannelLayoutTag {
    NSNumber* numTag = self.param[kAudioChannelLayoutTagKey];
    return (numTag != nil) ? numTag.unsignedIntValue : 0;
}

- (BOOL) videoEncode
{
    NSNumber* numVideoEncode = self.param[kVideoEncodeKey];
    BOOL videoEncode = (numVideoEncode != nil) ? numVideoEncode.boolValue : FALSE;
    return videoEncode;
}

- (NSString*) videoFourcc
{
    NSString* fourcc = self.param[kVideoCodecKey];
    return fourcc;
}

- (int) videoBitRate
{
    NSNumber* numVideoKbps = self.param[kVideoKbpsKey];
    float targetKbps = (numVideoKbps != nil) ? numVideoKbps.floatValue : 2500;
    int targetBitRate = (int)(targetKbps * 1000);
    return targetBitRate;
}

- (BOOL) copyField
{
    NSNumber* numCopyField = self.param[kCopyFieldKey];
    BOOL copyField = (numCopyField != nil) ? numCopyField.boolValue : FALSE;
    return copyField;
}

- (BOOL) copyNCLC
{
    NSNumber* numCopyNCLC = self.param[kCopyNCLCKey];
    BOOL copyNCLC = (numCopyNCLC != nil) ? numCopyNCLC.boolValue : FALSE;
    return copyNCLC;
}

@end

NS_ASSUME_NONNULL_END
