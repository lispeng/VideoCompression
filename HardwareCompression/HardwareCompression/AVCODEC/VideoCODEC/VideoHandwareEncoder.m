//
//  VideoHandwareEncoder.m
//  HardwareCompression
//
//  Created by iOS－MacBook on 2017/5/2.
//  Copyright © 2017年 Lispeng. All rights reserved.
//

#import "VideoHandwareEncoder.h"

@interface VideoHandwareEncoder()
/**
 文件写入对象
 */
@property (nonatomic,strong) NSFileHandle *fileHandle;
/**
 压缩编码会话对象
 */
@property (nonatomic,assign) VTCompressionSessionRef compressionSession;
/**
 当前帧数
 */
@property (nonatomic,assign) NSInteger currentFrame;

@end

@implementation VideoHandwareEncoder
- (instancetype)init
{
    if (self = [super init]) {
        //1.初始化文件写入对象
        [self setupVideoHandwareEncoderFileHandle];
        //2.初始化压缩编码会话
        [self setupVideoHandwareEncoderCompressionSession];
    }
    return self;
}
/**
 初始化文件写入对象
 */
- (void)setupVideoHandwareEncoderFileHandle
{
  //1.创建存储路径
    NSString *filePath = [[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) lastObject] stringByAppendingPathComponent:@"videoToolBox.h264"];
    //2.检查文件是否存在
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if (![fileManager fileExistsAtPath:filePath]) {
        //3.文件不存在，创建文件夹
        [fileManager createFileAtPath:filePath contents:nil attributes:nil];
    }
    //4.创建写入对象
    self.fileHandle = [NSFileHandle fileHandleForWritingAtPath:filePath];
    //5.移动文件的末尾继续写入
    [self.fileHandle seekToEndOfFile];
}
/**
 初始化压缩编码会话
 */
- (void)setupVideoHandwareEncoderCompressionSession
{
    //1.设置当前帧为0
    self.currentFrame = 0;
    //2.录制视频的宽和高
    int32_t VideoWidth = [UIScreen mainScreen].bounds.size.width;
    int32_t VideoHeight = [UIScreen mainScreen].bounds.size.height;
    //3.创建压缩编码的会话
    VTCompressionSessionCreate(NULL, VideoWidth, VideoHeight, kCMVideoCodecType_H264, NULL, NULL, NULL, compressionOutputCallback, (__bridge void *)(self), &_compressionSession);
    //4.设置编码会话属性
    //（1）设置实时编码输出，降低编码延迟
    VTSessionSetProperty(self.compressionSession, kVTCompressionPropertyKey_RealTime, kCFBooleanTrue);
    //(2)H264 profile,直播一般使用baseLine,可减少由B帧带来的延迟
    VTSessionSetProperty(self.compressionSession, kVTCompressionPropertyKey_ProfileLevel, kVTProfileLevel_H264_Baseline_AutoLevel);
    //(3)设置帧率：每秒多少帧，如果帧率过低，就会造成会面卡顿，大于16帧，人眼就很难识别出来了
    int fps = 32;
    CFNumberRef fpsRef = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &fps);
    VTSessionSetProperty(self.compressionSession, kVTCompressionPropertyKey_ExpectedFrameRate, fpsRef);
    //(4)设置码率：码率即编码效率，码率越高画面越清晰，码率较低会引起马赛克，码率高有利于还原原始画面，但是不利于视频传输
    int bitRate = VideoWidth * VideoHeight * 3 * 4 * 8;
    CFNumberRef bitRateRef = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &bitRate);
    VTSessionSetProperty(self.compressionSession, kVTCompressionPropertyKey_AverageBitRate, bitRateRef);
    //设置平均码率
    int bitRateLimit = VideoWidth * VideoHeight * 3 * 4;
    CFNumberRef bitRateLimitRef = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &bitRateLimit);
    VTSessionSetProperty(self.compressionSession, kVTCompressionPropertyKey_DataRateLimits, bitRateLimitRef);
    //(5)设置关键帧间隔
    int frameInterval = 32;
    CFNumberRef frameIntervalRef = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &frameInterval);
    VTSessionSetProperty(self.compressionSession, kVTCompressionPropertyKey_MaxKeyFrameInterval, frameIntervalRef);
    //5.基本设置结束，开始编码
    VTCompressionSessionPrepareToEncodeFrames(self.compressionSession);
    
}
//压缩编码的回调
void compressionOutputCallback(void * CM_NULLABLE outputCallbackRefCon,void * CM_NULLABLE sourceFrameRefCon,OSStatus status,VTEncodeInfoFlags infoFlags,CM_NULLABLE CMSampleBufferRef sampleBuffer )
{
    //sampleBuffer不存在则代表压缩不成功或帧丢失
    if(!sampleBuffer)return;
    if (status != noErr)return;
    //根据传入的参数引用来获取对象
    VideoHandwareEncoder *encoder = (__bridge VideoHandwareEncoder *)outputCallbackRefCon;
    //返回sampleBuffer中可变字典中的不可变数组，如果有错误则返回NULL
    CFArrayRef array = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, true);
    if(!array) return;
    CFDictionaryRef dic = CFArrayGetValueAtIndex(array, 0);
    if(!dic) return;
    //没有kCMSampleAttachmentKey_NotSync这个键意味着是关键帧
    bool isKeyFrame = !CFDictionaryContainsKey(dic, kCMSampleAttachmentKey_NotSync);
    if (isKeyFrame) {
        NSLog(@"关键帧");
        //获取编码后的格式描述信息CMFormatDescriptionRef
        CMFormatDescriptionRef formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer);
        //获取sps序列参数集
        size_t sparameterSetSize,sparameterSetCount;
        const uint8_t *sparameterSet;
       OSStatus spsStatus = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(formatDesc, 0, &sparameterSet, &sparameterSetSize, &sparameterSetCount, 0);
        //获取PPS图像参数集
        if (spsStatus == noErr) {
            size_t pparameterSetSize,pparameterSetCount;
            const uint8_t *pparameterSet;
           OSStatus ppStatus = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(formatDesc, 1, &pparameterSet, &pparameterSetSize, &pparameterSetCount, 0);
            if (ppStatus == noErr) {
                //将sps和pps转换成NSData对象
                NSData *sps = [NSData dataWithBytes:sparameterSet length:sparameterSetSize];
                NSData *pps = [NSData dataWithBytes:pparameterSet length:pparameterSetSize];
                //写入文件
                [encoder writeSps:sps pps:pps];
            }
        }
    }
    /////////////////////////////////////
    //获取CMBlockBuffer对象并转换成数据
    CMBlockBufferRef blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer);
    
    //接收到的数据展示
    size_t lengthAtOffset,totalLength;
    char *dataPointer;
    OSStatus blockBufferStatus = CMBlockBufferGetDataPointer(blockBuffer, 0, &lengthAtOffset, &totalLength, &dataPointer);
    if (blockBufferStatus == noErr) {
        size_t bufferOffset = 0;
        //H.264NALU数据的前四个字节代表帧长度的length
        static const int AVCCHeaderLength = 4;
        //通过指针偏移循环读取NALU数据
        while (bufferOffset < totalLength - AVCCHeaderLength) {
            //NAL unit的内存起始位置
            char *startPointer = dataPointer + bufferOffset;
            //读取NAL单元的长度
            uint32_t NALUnitLength = 0;
            /*
             * memcpy(<#void *__dst#>, <#const void *__src#>, <#size_t __n#>)
             *  由src指向地址为起始地址的连续n个字节的数据复制到以destin指向地址为起始地址的空间内。

             *
             */
/*   AVCCHeaderLength                  NALUnitLength
 *  |---:---:---:---|------------------------------------------------------|
    |   NAL Header  |    NAL  DATA                                         |
  --|---:---:---:---|------------------------------------------------------|
 *  |<----4bytes--->|<---------NALU前四个字节大端转化代表NAL-Data长度---------->|
 *  |<-------------------------NAL Unit----------------------------------->|
 *
 *
 *
 *
 */
            memcpy(&NALUnitLength, startPointer, AVCCHeaderLength);
            //host Big-endian 大端转化,获取压缩帧的长度
            NALUnitLength = CFSwapInt32BigToHost(NALUnitLength);
            //读取数据
            NSData *data = [[NSData alloc] initWithBytes:(startPointer + AVCCHeaderLength) length:NALUnitLength];
            //对数据进行编码
            [encoder encodedData:data isKeyFrame:isKeyFrame];
            //修改指针偏移量移动到下一个NAL unit区域
            bufferOffset += AVCCHeaderLength + NALUnitLength;
        }
        
        
    }
    
}
/**
 将sps和pps写入文件

 @param sps NSData类型的序列参数集
 @param pps NSDate类型的图像参数集
 */
- (void)writeSps:(NSDate *)sps pps:(NSDate *)pps
{
    //拼接NALU的Header
    const char bytes[] = "\x00\x00\x00\x00";
    size_t length = (sizeof bytes) - 1;
    NSData *ByteHeader = [NSData dataWithBytes:bytes length:length];
    //将NALU的Header和NALU数据体写入文件
    [self.fileHandle writeData:ByteHeader];
    [self.fileHandle writeData:sps];
    [self.fileHandle writeData:ByteHeader];
    [self.fileHandle writeData:pps];
}
/**
 将视频数据编码后写入文件

 @param data 视频数据
 @param isKeyFrame 是否是关键帧
 */
- (void)encodedData:(NSData *)data isKeyFrame:(BOOL)isKeyFrame
{
    if(self.fileHandle != NULL)
    {
        //帧头部
        const char bytes[] = "\x00\x00\x00\x01";
        //因为字符串的结尾有隐式的“\0”做结尾标记
        size_t length = (sizeof bytes) - 1;
        NSData *header = [[NSData alloc] initWithBytes:bytes length:length];
        //写入文件
        [self.fileHandle writeData:header];
        [self.fileHandle writeData:data];
    }
}
/**
 编码的方法

 @param sampleBuffer 编码对象
 */
- (void)encodeSampleBuffer:(CMSampleBufferRef)sampleBuffer
{
    //1.获取CVImageBufferRef对象
    CVImageBufferRef imageBuffer = (CVImageBufferRef)CMSampleBufferGetImageBuffer(sampleBuffer);
    //2.根据当前帧数创建CMTime时间
    CMTime presentationTimeStamp = CMTimeMake(self.currentFrame ++, 1000);
    //3.开始编码当前帧
    //有关编码操作的信息，例如：正在进行、帧丢失等
    VTEncodeInfoFlags flags;
   //开始编码
    OSStatus statusCode = VTCompressionSessionEncodeFrame(self.compressionSession, imageBuffer, presentationTimeStamp, kCMTimeInvalid, NULL, (__bridge void * _Nullable)(self), &flags);
    
    if (statusCode == noErr) {
        
        NSLog(@"H264: VTCompressionSessionEncodeFrame Success");

    }
    
}
/**
 停止编码
 */
- (void)endEncode
{
    VTCompressionSessionCompleteFrames(self.compressionSession, kCMTimeInvalid);
    VTCompressionSessionInvalidate(self.compressionSession);
    CFRelease(self.compressionSession);
    self.compressionSession = NULL;
}
@end
