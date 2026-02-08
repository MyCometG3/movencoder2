//
//  METranscodeConfiguration.m
//  movencoder2
//
//  Created by OpenCode.
//

#import "METranscodeConfiguration.h"

NS_ASSUME_NONNULL_BEGIN

@implementation METranscodeConfiguration

- (instancetype)init
{
    if (self = [super init]) {
        _encodingParams = [NSMutableDictionary dictionary];
        _timeRange = CMTimeRangeMake(kCMTimeInvalid, kCMTimeInvalid);
        _verbose = NO;
        _logLevel = MELogLevelInfo;
        _callbackQueue = nil;
        _startCallback = nil;
        _progressCallback = nil;
        _completionCallback = nil;
        return self;
    }
    return nil;
}

@end

NS_ASSUME_NONNULL_END
