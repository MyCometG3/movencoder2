//
//  MEVideoProcessor.h
//  movencoder2
//
//  Created by Takashi Mochizuki on 2018/11/03.
//  Copyright © 2018-2023 MyCometG3. All rights reserved.
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

#ifndef MEVideoProcessor_h
#define MEVideoProcessor_h

@import Foundation;
@import AVFoundation;
@import VideoToolbox;

@class SBChannel;

/* =================================================================================== */
// MARK: -
/* =================================================================================== */

NS_ASSUME_NONNULL_BEGIN

@interface MEVideoProcessor : NSObject

/**
 Parameters dictionary for configuration
 */
@property (strong, nonatomic) NSMutableDictionary* param;

/**
 Initialize with parameters dictionary
 
 @param param Configuration parameters
 @return Initialized MEVideoProcessor instance
 */
- (instancetype)initWithParameters:(NSMutableDictionary*)param;

/**
 Initialize with full dependencies for integration with METranscoder
 
 @param param Configuration parameters
 @param managers MEManager instances dictionary
 @param sbChannels SBChannel array for managing channels
 @param prepareCopyChannelBlock Block for handling copy channel preparation
 @return Initialized MEVideoProcessor instance
 */
- (instancetype)initWithParameters:(NSMutableDictionary*)param 
                          managers:(NSMutableDictionary*)managers 
                        sbChannels:(NSMutableArray<SBChannel*>*)sbChannels
               prepareCopyChannelBlock:(void (^)(AVMovie*, AVAssetReader*, AVAssetWriter*, AVMediaType))prepareCopyChannelBlock;

/**
 Check if track supports field mode
 
 @param track AVMovieTrack to check
 @return YES if field mode is supported
 */
- (BOOL)hasFieldModeSupportOf:(AVMovieTrack*)track;

/**
 Add decompression properties to asset reader output settings
 
 @param track Source track
 @param arOutputSetting Asset reader output settings to modify
 */
- (void)addDecompressionPropertiesOf:(AVMovieTrack*)track setting:(NSMutableDictionary*)arOutputSetting;

/**
 Create video compression settings for a track
 
 @param track Source track
 @return Video compression settings dictionary
 */
- (NSMutableDictionary<NSString*,id>*)videoCompressionSettingFor:(AVMovieTrack*)track;

/**
 Prepare video channels for transcoding
 
 @param movie Source movie
 @param ar Asset reader
 @param aw Asset writer
 */
- (void)prepareVideoChannelsWith:(AVMovie*)movie from:(AVAssetReader*)ar to:(AVAssetWriter*)aw;

/**
 Prepare video ME channels for transcoding
 
 @param movie Source movie
 @param ar Asset reader
 @param aw Asset writer
 */
- (void)prepareVideoMEChannelsWith:(AVMovie*)movie from:(AVAssetReader*)ar to:(AVAssetWriter*)aw;

@end

NS_ASSUME_NONNULL_END

#endif /* MEVideoProcessor_h */