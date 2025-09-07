//
//  SBChannel.h
//  movencoder2
//
//  Created by Takashi Mochizuki on 2018/11/24.
//  Copyright © 2018-2025 MyCometG3. All rights reserved.
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
