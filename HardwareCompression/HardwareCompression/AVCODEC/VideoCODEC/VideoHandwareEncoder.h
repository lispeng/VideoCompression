//
//  VideoHandwareEncoder.h
//  HardwareCompression
//
//  Created by iOS－MacBook on 2017/5/2.
//  Copyright © 2017年 Lispeng. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <VideoToolbox/VideoToolbox.h>
#import <UIKit/UIKit.h>
@interface VideoHandwareEncoder : NSObject
- (void)encodeSampleBuffer:(CMSampleBufferRef)sampleBuffer;
- (void)endEncode;
@end
