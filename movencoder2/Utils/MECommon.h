//
//  MECommon.h
//  movencoder2
//
//  Created by Refactoring on 2024/09/06.
//
//  Copyright (C) 2019-2026 MyCometG3
//  SPDX-License-Identifier: GPL-2.0-or-later
//

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
