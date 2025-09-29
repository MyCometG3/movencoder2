//
//  MEPipelineIntegrationTests.m
//  movencoder2Tests
//
//  Created by Copilot on 2025-09-29.
//  Copyright © 2018-2025 MyCometG3. All rights reserved.
//

@import XCTest;
@import Foundation;
@import CoreMedia;

#import "MEFilterPipeline.h"
#import "MEEncoderPipeline.h" 
#import "MESampleBufferFactory.h"

@interface MEPipelineIntegrationTests : XCTestCase
@property (strong, nonatomic) MEFilterPipeline *filterPipeline;
@property (strong, nonatomic) MEEncoderPipeline *encoderPipeline;
@property (strong, nonatomic) MESampleBufferFactory *sampleBufferFactory;
@end

@implementation MEPipelineIntegrationTests

- (void)setUp {
    [super setUp];
    self.filterPipeline = [[MEFilterPipeline alloc] init];
    self.encoderPipeline = [[MEEncoderPipeline alloc] init];
    self.sampleBufferFactory = [[MESampleBufferFactory alloc] init];
}

- (void)tearDown {
    [self.filterPipeline cleanup];
    [self.encoderPipeline cleanup];  
    [self.sampleBufferFactory cleanup];
    
    self.filterPipeline = nil;
    self.encoderPipeline = nil;
    self.sampleBufferFactory = nil;
    
    [super tearDown];
}

- (void)testPipelineComponentInitialization {
    // Test that pipeline components are properly initialized
    XCTAssertNotNil(self.filterPipeline);
    XCTAssertNotNil(self.encoderPipeline);
    XCTAssertNotNil(self.sampleBufferFactory);
    
    // Test initial states
    XCTAssertFalse(self.filterPipeline.isReady);
    XCTAssertFalse(self.filterPipeline.isEOF);
    XCTAssertFalse(self.filterPipeline.hasValidFilteredFrame);
    
    XCTAssertFalse(self.encoderPipeline.isReady);
    XCTAssertFalse(self.encoderPipeline.isEOF);
    XCTAssertFalse(self.encoderPipeline.isFlushed);
}

- (void)testPipelineComponentProperties {
    // Test property setting and synchronization
    self.filterPipeline.verbose = YES;
    self.filterPipeline.logLevel = AV_LOG_DEBUG;
    self.filterPipeline.timeBase = 30000;
    self.filterPipeline.filterString = @"scale=640:480";
    
    XCTAssertTrue(self.filterPipeline.verbose);
    XCTAssertEqual(self.filterPipeline.logLevel, AV_LOG_DEBUG);
    XCTAssertEqual(self.filterPipeline.timeBase, 30000);
    XCTAssertEqualObjects(self.filterPipeline.filterString, @"scale=640:480");
    
    // Test encoder pipeline properties
    NSMutableDictionary *encoderSettings = [@{@"codecName": @"libx264"} mutableCopy];
    self.encoderPipeline.videoEncoderSetting = encoderSettings;
    self.encoderPipeline.verbose = YES;
    self.encoderPipeline.logLevel = AV_LOG_DEBUG;
    self.encoderPipeline.timeBase = 30000;
    
    XCTAssertEqualObjects(self.encoderPipeline.videoEncoderSetting, encoderSettings);
    XCTAssertTrue(self.encoderPipeline.verbose);
    XCTAssertEqual(self.encoderPipeline.logLevel, AV_LOG_DEBUG);
    XCTAssertEqual(self.encoderPipeline.timeBase, 30000);
    
    // Test sample buffer factory properties
    self.sampleBufferFactory.verbose = YES;
    self.sampleBufferFactory.timeBase = 30000;
    self.sampleBufferFactory.videoEncoderSetting = encoderSettings;
    
    XCTAssertTrue(self.sampleBufferFactory.verbose);
    XCTAssertEqual(self.sampleBufferFactory.timeBase, 30000);
    XCTAssertEqualObjects(self.sampleBufferFactory.videoEncoderSetting, encoderSettings);
}

- (void)testPipelineComponentCleanup {
    // Test cleanup functionality
    self.filterPipeline.filterString = @"scale=640:480";
    self.encoderPipeline.videoEncoderSetting = [@{@"codecName": @"libx264"} mutableCopy];
    
    [self.filterPipeline cleanup];
    [self.encoderPipeline cleanup];
    [self.sampleBufferFactory cleanup];
    
    // After cleanup, components should be in initial state
    XCTAssertFalse(self.filterPipeline.isReady);
    XCTAssertFalse(self.filterPipeline.isEOF);
    XCTAssertFalse(self.encoderPipeline.isReady);
    XCTAssertFalse(self.encoderPipeline.isEOF);
}

- (void)testUtilityMethods {
    // Test utility methods in sample buffer factory
    XCTAssertFalse([self.sampleBufferFactory isUsingVideoFilter]);
    XCTAssertFalse([self.sampleBufferFactory isUsingVideoEncoder]);
    
    // After setting encoder settings, should detect encoder usage
    self.sampleBufferFactory.videoEncoderSetting = [@{@"codecName": @"libx264"} mutableCopy];
    XCTAssertTrue([self.sampleBufferFactory isUsingVideoEncoder]);
}

@end