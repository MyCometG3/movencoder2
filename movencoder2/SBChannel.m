//
//  SBChannel.m
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

#import "MECommon.h"
#import "SBChannel.h"
#import "MEInput.h"
#import "MEOutput.h"
#import "MEManager.h"
#import "MESecureLogging.h"

/* =================================================================================== */
// MARK: -
/* =================================================================================== */

NS_ASSUME_NONNULL_BEGIN

@interface SBChannel ()

@property(nonatomic, strong) NSDictionary* info;

@property(nonatomic, assign, getter=isFinished) BOOL finished;
@property(nonatomic, assign) char* queueLabel;
@property(nonatomic, strong) dispatch_queue_t queue;
@property(nonatomic, copy, nullable) CompletionHandler completionHandler;
@property(nonatomic, weak) id<SBChannelDelegate> delegate;
- (void)callCompletionHandlerIfNecessary;

@end

NS_ASSUME_NONNULL_END

/* =================================================================================== */
// MARK: -
/* =================================================================================== */

NS_ASSUME_NONNULL_BEGIN

@implementation SBChannel

@synthesize info;
@synthesize showProgress;

static void* sbChannelQueueKey = &sbChannelQueueKey;

char* createLabel(CMPersistentTrackID track) {
    @autoreleasepool {
        NSString* label = [NSString stringWithFormat:@"com.movencoder2.SBChannel.track%d", track];
        const char *temp = label.UTF8String;
        size_t size = strlen(temp) + 1;
        char * queueLabel = malloc(size);
        strlcpy(queueLabel, temp, size);
        return queueLabel;
    }
}

- (instancetype)initWithProducerME:(MEOutput*)meOutput
                        consumerME:(MEInput*)meInput
                           TrackID:(CMPersistentTrackID)track
{
    if (self = [super init]) {
        _meOutput = meOutput;
        _meInput = meInput;
        _track = track;
        _queueLabel = createLabel(track);
        _queue = dispatch_queue_create(_queueLabel, DISPATCH_QUEUE_SERIAL);
        // assign queue-specific to detect same-queue calls
        void* unused = (__bridge void*)self;
        dispatch_queue_set_specific(_queue, sbChannelQueueKey, unused, NULL);
        _count = 0;
    }
    return self;
}

+ (instancetype)sbChannelWithProducerME:(MEOutput*)meOutput
               consumerME:(MEInput*)meInput
                  TrackID:(CMPersistentTrackID)track
{
    return [[self alloc] initWithProducerME:meOutput consumerME:meInput TrackID:track];
}

- (void)dealloc
{
    if (_queueLabel) {
        free(_queueLabel);
    }
}

/* =================================================================================== */

- (AVMediaType)mediaType
{
    return self.meOutput.mediaType;
}

void dumpTiming(CMSampleBufferRef sb, NSString* typeString, NSString* tag, int count) {
    CMTime dur = CMSampleBufferGetDuration(sb);
    CMTime pts = CMSampleBufferGetPresentationTimeStamp(sb);
    int64_t dtsValue = dur.value;
    int32_t dtsScale = dur.timescale;
    int64_t ptsValue = pts.value;
    int32_t ptsScale = pts.timescale;
    float dtime = CMTimeGetSeconds(dur);
    float ptime = CMTimeGetSeconds(pts);
    SecureLogf(@"%@ [%@] : %lld/%d(%.2f), %lld/%d(%.2f) %d",
          typeString, tag, dtsValue, dtsScale, dtime, ptsValue, ptsScale, ptime, count);
}

int countUp(SBChannel* self) {
    int count = self.count + 1;
    self.count = count;
    return count;
}

- (void)startWithDelegate:(nullable id<SBChannelDelegate>)delegate
  completionHandler:(CompletionHandler)block
{
    self.delegate = delegate;
    self.completionHandler = block;
    
    __weak typeof(self) wself = self;
    [self.meInput requestMediaDataWhenReadyOnQueue:self.queue usingBlock:^{
        if (wself.finished) return;
        
        id<SBChannelDelegate> delegate = wself.delegate;
        MEOutput* meOutput = wself.meOutput;
        MEInput* meInput = wself.meInput;
        
        BOOL isFromME = [meOutput isMemberOfClass:[MEOutput class]];
        BOOL isToME = [meInput isMemberOfClass:[MEInput class]];
        BOOL isPassThru = (!isFromME && !isToME);
        BOOL isVideo = [meOutput.mediaType isEqualToString:@"vide"];
        BOOL isAudio = [meOutput.mediaType isEqualToString:@"soun"];
        NSString* tag = (isVideo ? @"video" : (isAudio ? @"audio" : @"other"));
        if (isVideo)
            tag = (isFromME ? @"out" : (isToME ? @"in " : @"p/t"));
        BOOL showProgress = wself.showProgress;
        
        NSMutableDictionary* info = [NSMutableDictionary new];
        info[kProgressTrackIDKey] = @(wself.track);
        info[kProgressMediaTypeKey] = wself.mediaType;
        info[kProgressTagKey] = tag;
        wself.info = info;

        BOOL result = TRUE;
        while (meInput.isReadyForMoreMediaData && result) {
            @autoreleasepool {
                CMSampleBufferRef sb = [meOutput copyNextSampleBuffer];
                if (sb) {
                    int count = countUp(wself);
                    
                    if (showProgress) {
                        if (isToME) { // input
                            dumpTiming(sb, meOutput.mediaType, tag, count);
                        }
                    }
                    [delegate didReadBuffer:sb from:wself];
                    result = [meInput appendSampleBuffer:sb];
                    
                    if (showProgress) {
                        if (isFromME || isPassThru) { // output
                            dumpTiming(sb, meOutput.mediaType, tag, count);
                        }
                    }
                    
                    CFRelease(sb);
                } else {
                    result = FALSE;
                }
            }
        }
        if (!result) {
            [wself callCompletionHandlerIfNecessary];
        }
    }];
}

- (void)cancel
{
    if (dispatch_get_specific(sbChannelQueueKey) != NULL) {
        // already on the same queue; avoid dispatch_sync deadlock
        [self callCompletionHandlerIfNecessary];
    } else {
        dispatch_sync(self.queue, ^{
            [self callCompletionHandlerIfNecessary];
        });
    }
}

- (void)callCompletionHandlerIfNecessary
{
    CompletionHandler block = nil;
    @synchronized (self) {
        if (self.finished) return;
        
        self.finished = TRUE;
        [self.meInput markAsFinished];
        
        if (self.completionHandler) {
            block = self.completionHandler;
            self.completionHandler = nil;
        }
    }
    if (block) {
        // run on the caller's queue (normally self.queue)
        block();
    }
}

@end

NS_ASSUME_NONNULL_END
