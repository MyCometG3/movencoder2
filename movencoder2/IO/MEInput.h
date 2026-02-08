//
//  MEInput.h
//  movencoder2
//
//  Created by Takashi Mochizuki on 2018/11/24.
//
//  Copyright (C) 2018-2026 MyCometG3
//  SPDX-License-Identifier: GPL-2.0-or-later
//

/**
 * @header MEInput.h
 * @abstract Internal API - Asset reading abstraction
 * @discussion
 * This header is part of the internal implementation of movencoder2.
 * It is not intended for public use and its interface may change without notice.
 *
 * @internal This is an internal API. Do not use directly.
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
