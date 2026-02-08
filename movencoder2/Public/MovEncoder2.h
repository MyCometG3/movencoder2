//
//  MovEncoder2.h
//  movencoder2
//
//  Public API umbrella header for movencoder2 framework
//
//  Copyright (C) 2018-2026 MyCometG3
//  SPDX-License-Identifier: GPL-2.0-or-later
//

#ifndef MovEncoder2_h
#define MovEncoder2_h

/**
 * @header MovEncoder2.h
 * @abstract Public API for movencoder2 transcoding library
 * @discussion
 * This umbrella header provides access to the public API of movencoder2,
 * a QuickTime movie transcoding library for macOS.
 *
 * ## Key Components
 *
 * - **METranscoder**: Main transcoding controller for video/audio transcoding operations
 * - **MEVideoEncoderConfig**: Type-safe configuration for video encoding parameters
 * - **METypes**: Public type definitions and enumerations
 *
 * ## Usage
 *
 * @code
 * #import <MovEncoder2/MovEncoder2.h>
 *
 * // Create transcoder
 * METranscoder *transcoder = [[METranscoder alloc] initWithInput:inputURL output:outputURL];
 *
 * // Configure parameters
 * transcoder.param = @{
 *     kVideoEncodeKey: @YES,
 *     kVideoCodecKey: @"avc1",
 *     kVideoKbpsKey: @5000
 * };
 *
 * // Set progress callback
 * transcoder.progressCallback = ^(NSDictionary *info) {
 *     NSNumber *percent = info[kProgressPercentKey];
 *     NSLog(@"Progress: %.1f%%", percent.floatValue);
 * };
 *
 * // Start transcoding
 * [transcoder startAsync];
 * @endcode
 *
 * @copyright Copyright (C) 2018-2026 MyCometG3
 */

// MARK: - Public API Headers

/**
 * Core Types and Enumerations
 */
#import "METypes.h"

/**
 * Type-safe Configuration
 */
#import "MEVideoEncoderConfig.h"

/**
 * Main Transcoding Controller
 */
#import "METranscoder.h"

// MARK: - Public Constants

/**
 * @constant kProgressMediaTypeKey
 * @abstract Media type key for progress callback dictionary
 * @discussion Value is an NSString (e.g., "vide", "soun")
 */
extern NSString* const kProgressMediaTypeKey;

/**
 * @constant kProgressTagKey
 * @abstract Tag key for progress callback dictionary
 * @discussion Value is an NSString identifying the track/channel
 */
extern NSString* const kProgressTagKey;

/**
 * @constant kProgressTrackIDKey
 * @abstract Track ID key for progress callback dictionary
 * @discussion Value is an NSNumber of int (CMPersistentTrackID)
 */
extern NSString* const kProgressTrackIDKey;

/**
 * @constant kProgressPTSKey
 * @abstract Presentation timestamp key for progress callback dictionary
 * @discussion Value is an NSNumber of float (seconds)
 */
extern NSString* const kProgressPTSKey;

/**
 * @constant kProgressDTSKey
 * @abstract Decode timestamp key for progress callback dictionary
 * @discussion Value is an NSNumber of float (seconds)
 */
extern NSString* const kProgressDTSKey;

/**
 * @constant kProgressPercentKey
 * @abstract Progress percentage key for progress callback dictionary
 * @discussion Value is an NSNumber of float (0.0 to 100.0)
 */
extern NSString* const kProgressPercentKey;

/**
 * @constant kProgressCountKey
 * @abstract Sample count key for progress callback dictionary
 * @discussion Value is an NSNumber of int (number of samples processed)
 */
extern NSString* const kProgressCountKey;

#endif /* MovEncoder2_h */
