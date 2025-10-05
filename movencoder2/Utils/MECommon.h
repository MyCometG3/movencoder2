//
//  MECommon.h
//  movencoder2
//
//  Created by Refactoring on 2024/09/06.
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

/**
 * @header MECommon.h
 * @abstract Internal API - Common definitions and utilities
 * @discussion
 * This header is part of the internal implementation of movencoder2.
 * Constants defined here (like progress callback keys) are re-exported in the public API.
 *
 * @internal This is an internal API. Do not import directly - use MovEncoder2.h instead.
 */

#ifndef MECommon_h
#define MECommon_h

@import Foundation;
@import AVFoundation;
#import "MESecureLogging.h"

/* =================================================================================== */
// MARK: - Common Macros
/* =================================================================================== */

#ifndef ALog
#define ALog(fmt, ...) SecureDebugLogf((@"%s [Line %d] " fmt), __PRETTY_FUNCTION__, __LINE__, ##__VA_ARGS__)
#endif

/* =================================================================================== */
// MARK: - Audio Channel Layout Constants
/* =================================================================================== */

// Standard MPEG source channel layouts (8 channels max)
extern const AudioChannelLayoutTag kMEMPEGSourceLayouts[8];

// Standard AAC destination channel layouts (8 channels max)
extern const AudioChannelLayoutTag kMEAACDestinationLayouts[8];

/* =================================================================================== */
// MARK: - Progress Callback Keys
/* =================================================================================== */

extern NSString* const kProgressMediaTypeKey;   // NSString
extern NSString* const kProgressTagKey;         // NSString
extern NSString* const kProgressTrackIDKey;     // NSNumber of int
extern NSString* const kProgressPTSKey;         // NSNumber of float
extern NSString* const kProgressDTSKey;         // NSNumber of float
extern NSString* const kProgressPercentKey;     // NSNumber of float
extern NSString* const kProgressCountKey;       // NSNumber of int

#endif /* MECommon_h */
