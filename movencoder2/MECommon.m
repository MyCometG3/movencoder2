//
//  MECommon.m
//  movencoder2
//
//  Created by Refactoring on 2024/09/06.
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

#import "MECommon.h"

/* =================================================================================== */
// MARK: - Audio Channel Layout Constants
/* =================================================================================== */

// Standard MPEG source channel layouts (8 channels max)
const AudioChannelLayoutTag kMEMPEGSourceLayouts[8] = {
    kAudioChannelLayoutTag_Mono,        // C
    kAudioChannelLayoutTag_Stereo,      // L R
    kAudioChannelLayoutTag_MPEG_3_0_A,  // L R C
    kAudioChannelLayoutTag_MPEG_4_0_A,  // L R C Cs
    kAudioChannelLayoutTag_MPEG_5_0_A,  // L R C Ls Rs
    kAudioChannelLayoutTag_MPEG_5_1_A,  // L R C LFE Ls Rs
    kAudioChannelLayoutTag_MPEG_6_1_A,  // L R C LFE Ls Rs Cs
    kAudioChannelLayoutTag_MPEG_7_1_C,  // L R C LFE Ls Rs Rls Rrs
};

// Standard AAC destination channel layouts (8 channels max)
const AudioChannelLayoutTag kMEAACDestinationLayouts[8] = {
    kAudioChannelLayoutTag_Mono,        // C
    kAudioChannelLayoutTag_Stereo,      // L R
    kAudioChannelLayoutTag_AAC_3_0,     // C L R
    kAudioChannelLayoutTag_AAC_4_0,     // C L R Cs
    kAudioChannelLayoutTag_AAC_5_0,     // C L R Ls Rs
    kAudioChannelLayoutTag_AAC_5_1,     // C L R Ls Rs Lfe
    kAudioChannelLayoutTag_AAC_6_1,     // C L R Ls Rs Cs Lfe
    kAudioChannelLayoutTag_AAC_7_1_B    // C L R Ls Rs Rls Rrs LFE
};

/* =================================================================================== */
// MARK: - Progress Callback Keys
/* =================================================================================== */

NSString* const kProgressMediaTypeKey = @"mediaType";       // NSString
NSString* const kProgressTagKey = @"tag";                   // NSString
NSString* const kProgressTrackIDKey = @"trackID";           // NSNumber of int
NSString* const kProgressPTSKey = @"pts";                   // NSNumber of float
NSString* const kProgressDTSKey = @"dts";                   // NSNumber of float
NSString* const kProgressPercentKey = @"percent";           // NSNumber of float
NSString* const kProgressCountKey = @"count";               // NSNumber of float
