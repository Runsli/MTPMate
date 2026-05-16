//
//  MTPBridge.m
//  mtp
//
//  Created by Li on 2026/4/18.
//

#import "MTPBridge.h"
#import <libmtp.h>

@implementation MTPDeviceInfo
@end

@implementation MTPFileInfo
@end

@implementation MTPBridge

static NSMutableDictionary<NSString *, NSValue *> *deviceHandles;
static dispatch_queue_t deviceHandlesQueue;
static NSMutableDictionary<NSString *, NSLock *> *deviceOperationLocks;
static NSLock *deviceOperationLocksGuard;
static NSMutableDictionary<NSString *, NSNumber *> *folderStorageIds;

#ifdef DEBUG
#define MTPDebugLog(...) NSLog(__VA_ARGS__)
#else
#define MTPDebugLog(...)
#endif

static int MTPProgressBridge(uint64_t const sent, uint64_t const total, void const * const data) {
    MTPProgressCallback callback = (__bridge MTPProgressCallback)data;
    if (callback && total > 0) {
        callback((double)sent / (double)total, sent, total);
    }
    return 0;
}

+ (void)initialize {
    if (self == [MTPBridge class]) {
        deviceHandles = [NSMutableDictionary dictionary];
        deviceHandlesQueue = dispatch_queue_create("com.mtp.deviceHandles", DISPATCH_QUEUE_SERIAL);
        deviceOperationLocks = [NSMutableDictionary dictionary];
        deviceOperationLocksGuard = [[NSLock alloc] init];
        folderStorageIds = [NSMutableDictionary dictionary];
        
        LIBMTP_Init();
    }
}

+ (BOOL)initializeMTP {
    LIBMTP_Init();
    return YES;
}

// 线程安全地获取设备指针
+ (LIBMTP_mtpdevice_t *)getDevicePointer:(NSString *)deviceId {
    __block LIBMTP_mtpdevice_t *device = NULL;
    dispatch_sync(deviceHandlesQueue, ^{
        NSValue *value = deviceHandles[deviceId];
        if (value) {
            device = [value pointerValue];
        }
    });
    return device;
}

+ (NSLock *)operationLockForDeviceId:(NSString *)deviceId {
    [deviceOperationLocksGuard lock];
    NSLock *lock = deviceOperationLocks[deviceId];
    if (!lock) {
        lock = [[NSLock alloc] init];
        deviceOperationLocks[deviceId] = lock;
    }
    [deviceOperationLocksGuard unlock];
    return lock;
}

+ (NSString *)storageCacheKeyForDeviceId:(NSString *)deviceId folderId:(NSString *)folderId {
    return [NSString stringWithFormat:@"%@:%@", deviceId, folderId];
}

+ (nullable NSArray<MTPDeviceInfo *> *)scanDevices:(NSError * _Nullable * _Nullable)error {
    NSMutableArray<MTPDeviceInfo *> *devices = [NSMutableArray array];
    
    LIBMTP_raw_device_t *rawDevices = NULL;
    int numDevices = 0;
    
    NSLog(@"🔍 开始检测 MTP 设备...");
    LIBMTP_error_number_t err = LIBMTP_Detect_Raw_Devices(&rawDevices, &numDevices);
    
    if (err != LIBMTP_ERROR_NONE) {
        NSLog(@"❌ 检测设备失败，错误码: %d", err);
        if (error) {
            *error = [NSError errorWithDomain:@"MTPBridge"
                                         code:err
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to detect MTP devices"}];
        }
        return devices;
    }
    
    NSLog(@"📱 检测到 %d 个原始设备", numDevices);
    NSLog(@"🔍 当前设备句柄数量: %lu", (unsigned long)deviceHandles.count);
    
    // 记录当前扫描到的设备ID
    NSMutableSet<NSString *> *currentDeviceIds = [NSMutableSet set];
    
    for (int i = 0; i < numDevices; i++) {
        // 生成基于总线位置的临时ID
        NSString *busId = [NSString stringWithFormat:@"bus-%d-%d", 
                           rawDevices[i].bus_location, 
                           rawDevices[i].devnum];
        
        // 检查是否已经有这个设备的连接（可能使用不同的ID格式）
        LIBMTP_mtpdevice_t *device = nil;
        NSString *existingDeviceId = nil;
        
        // 先尝试直接匹配总线ID
        NSValue *existingHandle = deviceHandles[busId];
        if (existingHandle) {
            device = [existingHandle pointerValue];
            existingDeviceId = busId;
            NSLog(@"🔄 重用已连接的设备（总线ID）: %@", busId);
        } else {
            // 遍历所有已有设备，查找可能匹配的设备
            for (NSString *key in deviceHandles.allKeys) {
                // 如果key包含相同的总线位置信息，可能是同一设备
                if ([key containsString:[NSString stringWithFormat:@"%d-%d", 
                                         rawDevices[i].bus_location, 
                                         rawDevices[i].devnum]]) {
                    device = [[deviceHandles objectForKey:key] pointerValue];
                    existingDeviceId = key;
                    NSLog(@"🔄 重用已连接的设备（匹配ID）: %@", key);
                    break;
                }
            }
        }
        
        // 如果没有找到已存在的连接，打开新设备
        if (!device) {
            NSLog(@"🔌 正在打开新设备 %d/%d...", i + 1, numDevices);
            device = LIBMTP_Open_Raw_Device_Uncached(&rawDevices[i]);
            if (!device) {
                NSLog(@"❌ 无法打开设备 %d", i + 1);
                continue;
            }
            
            // 获取序列号用于生成稳定ID
            char *serial = LIBMTP_Get_Serialnumber(device);
            NSString *serialNumber = serial ? [NSString stringWithUTF8String:serial] : nil;
            free(serial);
            
            // 生成设备ID
            NSString *deviceId;
            if (serialNumber && serialNumber.length > 0 && ![serialNumber isEqualToString:@"Unknown"]) {
                deviceId = [NSString stringWithFormat:@"serial-%@", serialNumber];
                NSLog(@"✅ 使用序列号作为设备ID: %@", deviceId);
            } else {
                deviceId = busId;
                NSLog(@"⚠️ 设备没有序列号，使用总线位置作为ID: %@", deviceId);
            }
            
            // 保存新设备句柄
            deviceHandles[deviceId] = [NSValue valueWithPointer:device];
            existingDeviceId = deviceId;
            NSLog(@"✅ 新设备已连接，保存句柄: %@", deviceId);
        }
        
        // 将设备ID添加到当前设备列表
        if (existingDeviceId) {
            [currentDeviceIds addObject:existingDeviceId];
        }
        
        if (device) {
            MTPDeviceInfo *info = [[MTPDeviceInfo alloc] init];
            info.deviceId = existingDeviceId;
            
            // 获取设备信息
            char *manufacturer = LIBMTP_Get_Manufacturername(device);
            char *model = LIBMTP_Get_Modelname(device);
            char *serial = LIBMTP_Get_Serialnumber(device);
            char *version = LIBMTP_Get_Deviceversion(device);
            
            info.manufacturer = manufacturer ? [NSString stringWithUTF8String:manufacturer] : @"Unknown";
            info.model = model ? [NSString stringWithUTF8String:model] : @"Unknown";
            info.serialNumber = serial ? [NSString stringWithUTF8String:serial] : @"Unknown";
            info.deviceVersion = version ? [NSString stringWithUTF8String:version] : @"Unknown";
            
            NSLog(@"📋 设备信息: %@ %@ (序列号: %@, 设备ID: %@)", info.manufacturer, info.model, info.serialNumber, existingDeviceId);
            
            free(manufacturer);
            free(model);
            free(serial);
            free(version);
            
            // 获取电池信息
            uint8_t maxLevel, currentLevel;
            if (LIBMTP_Get_Batterylevel(device, &maxLevel, &currentLevel) == 0) {
                info.batteryLevel = (maxLevel > 0) ? (currentLevel * 100 / maxLevel) : -1;
                NSLog(@"🔋 电池电量: %ld%%", (long)info.batteryLevel);
            } else {
                info.batteryLevel = -1;
                NSLog(@"⚠️ 无法获取电池信息");
            }
            
            // 获取存储信息
            LIBMTP_devicestorage_t *storage = device->storage;
            int storageCount = 0;
            while (storage) {
                storageCount++;
                NSLog(@"💾 存储 %d: ID=%u, 描述=%s, 总容量=%llu, 可用=%llu", 
                      storageCount, storage->id, 
                      storage->StorageDescription ?: "Unknown",
                      storage->MaxCapacity, storage->FreeSpaceInBytes);
                
                if (storageCount == 1) {
                    info.totalStorage = storage->MaxCapacity;
                    info.freeStorage = storage->FreeSpaceInBytes;
                }
                
                storage = storage->next;
            }
            
            [devices addObject:info];
        }
    }
    
    // 清理已断开的设备连接
    NSLog(@"🔍 检查需要清理的设备，当前句柄数: %lu, 当前设备数: %lu", 
          (unsigned long)deviceHandles.count, 
          (unsigned long)currentDeviceIds.count);
    
    NSMutableArray<NSString *> *devicesToRemove = [NSMutableArray array];
    for (NSString *deviceId in deviceHandles.allKeys) {
        if (![currentDeviceIds containsObject:deviceId]) {
            NSLog(@"🔌 设备已断开，清理连接: %@", deviceId);
            NSValue *value = deviceHandles[deviceId];
            if (value) {
                LIBMTP_mtpdevice_t *device = [value pointerValue];
                LIBMTP_Release_Device(device);
            }
            [devicesToRemove addObject:deviceId];
        }
    }
    
    for (NSString *deviceId in devicesToRemove) {
        [deviceHandles removeObjectForKey:deviceId];
    }
    
    NSLog(@"✅ 清理完成，剩余句柄数: %lu", (unsigned long)deviceHandles.count);
    
    free(rawDevices);
    
    NSLog(@"✅ 扫描完成，成功管理 %lu 个设备", (unsigned long)devices.count);
    
    return devices;
}

+ (BOOL)openDevice:(NSString * _Nonnull)deviceId error:(NSError * _Nullable * _Nullable)error {
    // 设备已在 scanDevices 中打开
    return deviceHandles[deviceId] != nil;
}

+ (void)closeDevice:(NSString * _Nonnull)deviceId {
    NSValue *value = deviceHandles[deviceId];
    if (value) {
        LIBMTP_mtpdevice_t *device = [value pointerValue];
        LIBMTP_Release_Device(device);
        [deviceHandles removeObjectForKey:deviceId];
        [deviceOperationLocksGuard lock];
        [deviceOperationLocks removeObjectForKey:deviceId];
        [deviceOperationLocksGuard unlock];
        
        NSString *prefix = [NSString stringWithFormat:@"%@:", deviceId];
        for (NSString *key in folderStorageIds.allKeys) {
            if ([key hasPrefix:prefix]) {
                [folderStorageIds removeObjectForKey:key];
            }
        }
    }
}

+ (nullable MTPDeviceInfo *)getDeviceInfo:(NSString * _Nonnull)deviceId error:(NSError * _Nullable * _Nullable)error {
    NSValue *value = deviceHandles[deviceId];
    if (!value) {
        if (error) {
            *error = [NSError errorWithDomain:@"MTPBridge"
                                         code:-1
                                     userInfo:@{NSLocalizedDescriptionKey: @"Device not found"}];
        }
        return nil;
    }
    
    LIBMTP_mtpdevice_t *device = [value pointerValue];
    MTPDeviceInfo *info = [[MTPDeviceInfo alloc] init];
    info.deviceId = deviceId;
    
    char *manufacturer = LIBMTP_Get_Manufacturername(device);
    char *model = LIBMTP_Get_Modelname(device);
    char *serial = LIBMTP_Get_Serialnumber(device);
    
    info.manufacturer = manufacturer ? [NSString stringWithUTF8String:manufacturer] : @"Unknown";
    info.model = model ? [NSString stringWithUTF8String:model] : @"Unknown";
    info.serialNumber = serial ? [NSString stringWithUTF8String:serial] : @"Unknown";
    
    free(manufacturer);
    free(model);
    free(serial);
    
    return info;
}

+ (nullable NSArray<MTPFileInfo *> *)listFiles:(NSString * _Nonnull)deviceId 
                                      parentId:(NSString * _Nullable)parentId 
                                         error:(NSError * _Nullable * _Nullable)error {
    NSValue *value = deviceHandles[deviceId];
    if (!value) {
        if (error) {
            *error = [NSError errorWithDomain:@"MTPBridge"
                                         code:-1
                                     userInfo:@{NSLocalizedDescriptionKey: @"Device not found"}];
        }
        return nil;
    }
    
    LIBMTP_mtpdevice_t *device = [value pointerValue];
    NSMutableArray<MTPFileInfo *> *files = [NSMutableArray array];
    
    uint32_t parent = parentId ? (uint32_t)[parentId integerValue] : LIBMTP_FILES_AND_FOLDERS_ROOT;
    NSLock *operationLock = [self operationLockForDeviceId:deviceId];
    [operationLock lock];
    
    @try {
    NSNumber *cachedStorageId = parentId ? folderStorageIds[[self storageCacheKeyForDeviceId:deviceId folderId:parentId]] : nil;
    
    // 遍历所有存储设备
    LIBMTP_devicestorage_t *storage = device->storage;
    while (storage) {
        if (cachedStorageId && storage->id != cachedStorageId.unsignedIntValue) {
            storage = storage->next;
            continue;
        }
        
        MTPDebugLog(@"📦 正在列出存储 ID: %u, 名称: %s", storage->id, storage->StorageDescription ?: "Unknown");
        
        LIBMTP_file_t *fileList = LIBMTP_Get_Files_And_Folders(device, storage->id, parent);
        
        if (!fileList) {
            NSLog(@"⚠️ 存储 %u 返回空文件列表", storage->id);
        }
        
        LIBMTP_file_t *current = fileList;
        while (current) {
            MTPFileInfo *info = [[MTPFileInfo alloc] init];
            info.fileId = [NSString stringWithFormat:@"%u", current->item_id];
            info.fileName = current->filename ? [NSString stringWithUTF8String:current->filename] : @"Unknown";
            info.fileSize = current->filesize;
            info.isDirectory = (current->filetype == LIBMTP_FILETYPE_FOLDER);
            info.modifiedDate = [NSDate dateWithTimeIntervalSince1970:current->modificationdate];
            info.parentId = [NSString stringWithFormat:@"%u", current->parent_id];
            
            if (info.isDirectory) {
                folderStorageIds[[self storageCacheKeyForDeviceId:deviceId folderId:info.fileId]] = @(storage->id);
            }
            
            // 构建文件路径
            if (parent == LIBMTP_FILES_AND_FOLDERS_ROOT) {
                info.filePath = [NSString stringWithFormat:@"/%@", info.fileName];
            } else {
                info.filePath = info.fileName; // 子目录的路径需要由上层维护
            }
            
            MTPDebugLog(@"📄 文件: %@ (ID: %@, 类型: %@, 大小: %llu)", 
                  info.fileName, info.fileId, 
                  info.isDirectory ? @"文件夹" : @"文件", 
                  info.fileSize);
            
            [files addObject:info];
            current = current->next;
        }
        
        LIBMTP_destroy_file_t(fileList);
        
        storage = storage->next;
    }
    
    MTPDebugLog(@"✅ 总共找到 %lu 个文件/文件夹", (unsigned long)files.count);
    }
    @finally {
        [operationLock unlock];
    }
    
    return files;
}

+ (BOOL)downloadFile:(NSString * _Nonnull)deviceId
              fileId:(NSString * _Nonnull)fileId
       toDestination:(NSString * _Nonnull)destinationPath
            progress:(nullable MTPProgressCallback)progressCallback
               error:(NSError * _Nullable * _Nullable)error {
    
    MTPDebugLog(@"📥 MTPBridge downloadFile 开始:");
    MTPDebugLog(@"   - deviceId: %@", deviceId);
    MTPDebugLog(@"   - fileId: %@", fileId);
    MTPDebugLog(@"   - destination: %@", destinationPath);
    
    NSLock *operationLock = [self operationLockForDeviceId:deviceId];
    [operationLock lock];
    
    // 确保在任何情况下都释放锁
    BOOL success = NO;
    @try {
        // 线程安全地获取设备指针
        LIBMTP_mtpdevice_t *device = [self getDevicePointer:deviceId];
        
        if (!device) {
            NSLog(@"❌ 设备未找到或指针无效: %@", deviceId);
            if (error) {
                *error = [NSError errorWithDomain:@"MTPBridge"
                                             code:-1
                                         userInfo:@{NSLocalizedDescriptionKey: @"Device not found"}];
            }
            return NO;
        }
        
        // 转换文件 ID
        uint32_t fileIdInt = (uint32_t)[fileId integerValue];
        MTPDebugLog(@"   - fileIdInt: %u", fileIdInt);
        
        if (fileIdInt == 0) {
            NSLog(@"❌ 文件 ID 无效: %@", fileId);
            if (error) {
                *error = [NSError errorWithDomain:@"MTPBridge"
                                             code:-1
                                         userInfo:@{NSLocalizedDescriptionKey: @"Invalid file ID"}];
            }
            return NO;
        }
        
        // 获取目标路径（确保字符串生命周期）
        NSString *destPathString = [destinationPath copy];
        const char *destPath = [destPathString UTF8String];
        
        if (!destPath) {
            NSLog(@"❌ 目标路径转换失败");
            if (error) {
                *error = [NSError errorWithDomain:@"MTPBridge"
                                             code:-1
                                         userInfo:@{NSLocalizedDescriptionKey: @"Invalid destination path"}];
            }
            return NO;
        }
        
        MTPDebugLog(@"📥 调用 LIBMTP_Get_File_To_File...");
        
        MTPProgressCallback callback = [progressCallback copy];
        void *callbackContext = callback ? (__bridge void *)callback : NULL;
        
        // 调用 libmtp 下载文件
        int result = LIBMTP_Get_File_To_File(
            device,
            fileIdInt,
            (char *)destPath,
            callback ? MTPProgressBridge : NULL,
            callbackContext
        );
        
        MTPDebugLog(@"📥 LIBMTP_Get_File_To_File 返回: %d", result);
        
        if (result != 0) {
            NSLog(@"❌ 下载失败，错误码: %d", result);
            
            // 获取 libmtp 错误信息
            LIBMTP_error_t *errors = LIBMTP_Get_Errorstack(device);
            if (errors) {
                NSLog(@"   libmtp 错误:");
                LIBMTP_error_t *current = errors;
                while (current) {
                    NSLog(@"   - %s", current->error_text);
                    current = current->next;
                }
                LIBMTP_Clear_Errorstack(device);
            }
            
            if (error) {
                *error = [NSError errorWithDomain:@"MTPBridge"
                                             code:result
                                         userInfo:@{NSLocalizedDescriptionKey: @"Failed to download file"}];
            }
            success = NO;
        } else {
            MTPDebugLog(@"✅ 文件下载成功");
            success = YES;
        }
    }
    @finally {
        [operationLock unlock];
    }
    
    return success;
}

+ (nullable NSString *)uploadFile:(NSString * _Nonnull)deviceId
                       sourcePath:(NSString * _Nonnull)sourcePath
                       toParentId:(NSString * _Nullable)parentId
                         fileName:(NSString * _Nonnull)fileName
                         progress:(nullable MTPProgressCallback)progressCallback
                            error:(NSError * _Nullable * _Nullable)error {
    NSValue *value = deviceHandles[deviceId];
    if (!value) {
        if (error) {
            *error = [NSError errorWithDomain:@"MTPBridge"
                                         code:-1
                                     userInfo:@{NSLocalizedDescriptionKey: @"Device not found"}];
        }
        return nil;
    }
    
    LIBMTP_mtpdevice_t *device = [value pointerValue];
    NSLock *operationLock = [self operationLockForDeviceId:deviceId];
    [operationLock lock];
    
    @try {
    // 获取文件大小
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSDictionary *attributes = [fileManager attributesOfItemAtPath:sourcePath error:error];
    if (!attributes) {
        return nil;
    }
    
    uint64_t fileSize = [attributes fileSize];
    uint32_t parent = parentId ? (uint32_t)[parentId integerValue] : LIBMTP_FILES_AND_FOLDERS_ROOT;
    
    LIBMTP_file_t *genfile = LIBMTP_new_file_t();
    genfile->filesize = fileSize;
    genfile->filename = strdup([fileName UTF8String]);
    genfile->filetype = LIBMTP_FILETYPE_UNKNOWN;
    genfile->parent_id = parent;
    genfile->storage_id = 0;
    
    const char *srcPath = [sourcePath UTF8String];
    MTPProgressCallback callback = [progressCallback copy];
    void *callbackContext = callback ? (__bridge void *)callback : NULL;
    int result = LIBMTP_Send_File_From_File(
        device,
        (char *)srcPath,
        genfile,
        callback ? MTPProgressBridge : NULL,
        callbackContext
    );
    
    NSString *newFileId = nil;
    if (result == 0) {
        newFileId = [NSString stringWithFormat:@"%u", genfile->item_id];
    } else {
        if (error) {
            *error = [NSError errorWithDomain:@"MTPBridge"
                                         code:result
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to upload file"}];
        }
    }
    
    LIBMTP_destroy_file_t(genfile);
    
    return newFileId;
    }
    @finally {
        [operationLock unlock];
    }
}

+ (BOOL)deleteFile:(NSString * _Nonnull)deviceId 
            fileId:(NSString * _Nonnull)fileId 
             error:(NSError * _Nullable * _Nullable)error {
    NSValue *value = deviceHandles[deviceId];
    if (!value) {
        if (error) {
            *error = [NSError errorWithDomain:@"MTPBridge"
                                         code:-1
                                     userInfo:@{NSLocalizedDescriptionKey: @"Device not found"}];
        }
        return NO;
    }
    
    LIBMTP_mtpdevice_t *device = [value pointerValue];
    uint32_t fileIdInt = (uint32_t)[fileId integerValue];
    NSLock *operationLock = [self operationLockForDeviceId:deviceId];
    [operationLock lock];
    
    @try {
    int result = LIBMTP_Delete_Object(device, fileIdInt);
    
    if (result != 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"MTPBridge"
                                         code:result
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to delete file"}];
        }
        return NO;
    }
    
    return YES;
    }
    @finally {
        [operationLock unlock];
    }
}

+ (nullable NSString *)createFolder:(NSString * _Nonnull)deviceId
                               name:(NSString * _Nonnull)name
                           parentId:(NSString * _Nullable)parentId
                              error:(NSError * _Nullable * _Nullable)error {
    NSValue *value = deviceHandles[deviceId];
    if (!value) {
        if (error) {
            *error = [NSError errorWithDomain:@"MTPBridge"
                                         code:-1
                                     userInfo:@{NSLocalizedDescriptionKey: @"Device not found"}];
        }
        return nil;
    }
    
    LIBMTP_mtpdevice_t *device = [value pointerValue];
    uint32_t parent = parentId ? (uint32_t)[parentId integerValue] : LIBMTP_FILES_AND_FOLDERS_ROOT;
    NSLock *operationLock = [self operationLockForDeviceId:deviceId];
    [operationLock lock];
    
    @try {
    const char *folderName = [name UTF8String];
    uint32_t newFolderId = LIBMTP_Create_Folder(device, (char *)folderName, parent, 0);
    
    if (newFolderId == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"MTPBridge"
                                         code:-1
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to create folder"}];
        }
        return nil;
    }
    
    return [NSString stringWithFormat:@"%u", newFolderId];
    }
    @finally {
        [operationLock unlock];
    }
}

+ (BOOL)renameFile:(NSString * _Nonnull)deviceId
            fileId:(NSString * _Nonnull)fileId
           newName:(NSString * _Nonnull)newName
             error:(NSError * _Nullable * _Nullable)error {
    NSValue *value = deviceHandles[deviceId];
    if (!value) {
        if (error) {
            *error = [NSError errorWithDomain:@"MTPBridge"
                                         code:-1
                                     userInfo:@{NSLocalizedDescriptionKey: @"Device not found"}];
        }
        return NO;
    }
    
    LIBMTP_mtpdevice_t *device = [value pointerValue];
    uint32_t fileIdInt = (uint32_t)[fileId integerValue];
    NSLock *operationLock = [self operationLockForDeviceId:deviceId];
    [operationLock lock];
    
    @try {
    // First get the file metadata to obtain the LIBMTP_file_t object
    LIBMTP_file_t *fileObject = LIBMTP_Get_Filemetadata(device, fileIdInt);
    if (!fileObject) {
        if (error) {
            *error = [NSError errorWithDomain:@"MTPBridge"
                                         code:-1
                                     userInfo:@{NSLocalizedDescriptionKey: @"File not found"}];
        }
        return NO;
    }
    
    // Update the filename in the file object
    if (fileObject->filename) {
        free(fileObject->filename);
    }
    fileObject->filename = strdup([newName UTF8String]);
    
    // Now call LIBMTP_Set_File_Name with the correct file object
    int result = LIBMTP_Set_File_Name(device, fileObject, fileObject->filename);
    
    LIBMTP_destroy_file_t(fileObject);
    
    if (result != 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"MTPBridge"
                                         code:result
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to rename file"}];
        }
        return NO;
    }
    
    return YES;
    }
    @finally {
        [operationLock unlock];
    }
}

@end
