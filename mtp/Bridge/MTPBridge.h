//
//  MTPBridge.h
//  mtp
//
//  Created by Li on 2026/4/18.
//

#ifndef MTPBridge_h
#define MTPBridge_h

#import <Foundation/Foundation.h>

// MTP 设备信息
@interface MTPDeviceInfo : NSObject
@property (nonatomic, copy) NSString * _Nullable deviceId;
@property (nonatomic, copy) NSString * _Nonnull manufacturer;
@property (nonatomic, copy) NSString * _Nonnull model;
@property (nonatomic, copy) NSString * _Nonnull serialNumber;
@property (nonatomic, copy) NSString * _Nonnull deviceVersion;
@property (nonatomic, assign) NSInteger batteryLevel;
@property (nonatomic, assign) uint64_t totalStorage;
@property (nonatomic, assign) uint64_t freeStorage;
@end

// MTP 文件信息
@interface MTPFileInfo : NSObject
@property (nonatomic, copy) NSString * _Nonnull fileId;
@property (nonatomic, copy) NSString * _Nonnull fileName;
@property (nonatomic, copy) NSString * _Nullable filePath;
@property (nonatomic, assign) uint64_t fileSize;
@property (nonatomic, assign) BOOL isDirectory;
@property (nonatomic, strong) NSDate * _Nullable modifiedDate;
@property (nonatomic, copy) NSString * _Nullable mimeType;
@property (nonatomic, copy) NSString * _Nullable parentId;
@end

// 进度回调
typedef void (^MTPProgressCallback)(double progress, uint64_t bytesTransferred, uint64_t totalBytes);

// MTP 桥接接口
@interface MTPBridge : NSObject

// 初始化 libmtp
+ (BOOL)initializeMTP;

// 扫描设备
+ (nullable NSArray<MTPDeviceInfo *> *)scanDevices:(NSError * _Nullable * _Nullable)error;

// 打开设备
+ (BOOL)openDevice:(NSString * _Nonnull)deviceId error:(NSError * _Nullable * _Nullable)error;

// 关闭设备
+ (void)closeDevice:(NSString * _Nonnull)deviceId;

// 获取设备信息
+ (nullable MTPDeviceInfo *)getDeviceInfo:(NSString * _Nonnull)deviceId error:(NSError * _Nullable * _Nullable)error;

// 列出文件
+ (nullable NSArray<MTPFileInfo *> *)listFiles:(NSString * _Nonnull)deviceId 
                                      parentId:(NSString * _Nullable)parentId 
                                         error:(NSError * _Nullable * _Nullable)error;

// 下载文件
+ (BOOL)downloadFile:(NSString * _Nonnull)deviceId
              fileId:(NSString * _Nonnull)fileId
       toDestination:(NSString * _Nonnull)destinationPath
            progress:(nullable MTPProgressCallback)progressCallback
               error:(NSError * _Nullable * _Nullable)error;

// 上传文件
+ (nullable NSString *)uploadFile:(NSString * _Nonnull)deviceId
                       sourcePath:(NSString * _Nonnull)sourcePath
                       toParentId:(NSString * _Nullable)parentId
                         fileName:(NSString * _Nonnull)fileName
                         progress:(nullable MTPProgressCallback)progressCallback
                            error:(NSError * _Nullable * _Nullable)error;

// 删除文件
+ (BOOL)deleteFile:(NSString * _Nonnull)deviceId 
            fileId:(NSString * _Nonnull)fileId 
             error:(NSError * _Nullable * _Nullable)error;

// 创建文件夹
+ (nullable NSString *)createFolder:(NSString * _Nonnull)deviceId
                               name:(NSString * _Nonnull)name
                           parentId:(NSString * _Nullable)parentId
                              error:(NSError * _Nullable * _Nullable)error;

// 重命名文件
+ (BOOL)renameFile:(NSString * _Nonnull)deviceId
            fileId:(NSString * _Nonnull)fileId
           newName:(NSString * _Nonnull)newName
             error:(NSError * _Nullable * _Nullable)error;

@end

#endif /* MTPBridge_h */
