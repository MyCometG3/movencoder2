//
//  SBChannel.h
//  movencoder2
//
//  Created by Takashi Mochizuki on 2018/11/24.
//
//  Copyright (C) 2018-2026 MyCometG3
//  SPDX-License-Identifier: GPL-2.0-or-later
//

/**
 * @header SBChannel.h
 * @abstract Internal API - Sample buffer channel coordination
 * @discussion
 * This header is part of the internal implementation of movencoder2.
 * It is not intended for public use and its interface may change without notice.
 *
 * @internal This is an internal API. Do not use directly.
 */

#ifndef SBChannel_h
#define SBChannel_h

@import Foundation;
@import AVFoundation;

@class MEInput;
@class MEOutput;

/* =================================================================================== */
// MARK: -
/* =================================================================================== */

typedef void (^CompletionHandler)(void);

/* =================================================================================== */
// MARK: -
/* =================================================================================== */

@class SBChannel;
@protocol SBChannelDelegate <NSObject>
- (void)didReadBuffer:(CMSampleBufferRef _Nonnull)buffer from:(SBChannel* _Nonnull)channel;
@end

/* =================================================================================== */
// MARK: -
/* =================================================================================== */

NS_ASSUME_NONNULL_BEGIN

@interface SBChannel : NSObject

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

@property(nonatomic, assign, readonly) CMPersistentTrackID track;
@property(nonatomic, copy, readonly) AVMediaType mediaType;
@property(nonatomic, assign, readonly, getter=isFinished) BOOL finished;
@property(nonatomic, strong, readonly) MEOutput* meOutput;
@property(nonatomic, strong, readonly) MEInput* meInput;
@property(nonatomic, assign) BOOL showProgress;
@property(nonatomic) int count;
@property(nonatomic, strong, readonly) NSDictionary* info;

- (instancetype)initWithProducerME:(MEOutput*)meOutput
                        consumerME:(MEInput*)meInput
                           TrackID:(CMPersistentTrackID)track NS_DESIGNATED_INITIALIZER;
+ (instancetype)sbChannelWithProducerME:(MEOutput*)meOutput
                             consumerME:(MEInput*)meInput
                                TrackID:(CMPersistentTrackID)track ;

- (void)startWithDelegate:(nullable id<SBChannelDelegate>)delegate
  completionHandler:(CompletionHandler)handler;
- (void)cancel;

@end

NS_ASSUME_NONNULL_END

#endif /* SBChannel_h */
