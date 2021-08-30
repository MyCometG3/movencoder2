//
//  MEInput.h
//  movencoder2
//
//  Created by Takashi Mochizuki on 2018/11/24.
//  Copyright © 2018-2021 MyCometG3. All rights reserved.
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

#ifndef MEInput_h
#define MEInput_h

@import Foundation;
@import AVFoundation;
@import CoreMedia;

@class MEManager;

/* =================================================================================== */
// MARK: -
/* =================================================================================== */

typedef void (^RequestHandler)(void);

/* =================================================================================== */
// MARK: -
/* =================================================================================== */

/*
 Similar interface to AVAssetWriterInput
 libavXX consumer class
 */

NS_ASSUME_NONNULL_BEGIN

@interface MEInput : NSObject

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

- (instancetype)initWithManager:(MEManager*)manager;
+ (instancetype)inputWithManager:(MEManager*)manager;

- (instancetype)initWithAssetWriterInput:(AVAssetWriterInput*) awInput;
+ (instancetype)inputWithAssetWriterInput:(AVAssetWriterInput*) awInput;

@property(nonatomic, nullable, readonly) MEManager* meManager;
@property(nonatomic, nullable, readonly) AVAssetWriterInput* awInput;

/* =================================================================================== */
// MARK: - mimic AVAssetWriterInput
/* =================================================================================== */

- (BOOL)appendSampleBuffer:(CMSampleBufferRef)sampleBuffer;
@property(nonatomic, readonly, getter=isReadyForMoreMediaData) BOOL readyForMoreMediaData;
- (void)markAsFinished;
- (void)requestMediaDataWhenReadyOnQueue:(dispatch_queue_t)queue usingBlock:(RequestHandler)block;

@property(nonatomic, readonly) AVMediaType mediaType;
@property(nonatomic) CMTimeScale mediaTimeScale;
@property(nonatomic) CGSize naturalSize;
@end

NS_ASSUME_NONNULL_END

#endif /* MEInput_h */
