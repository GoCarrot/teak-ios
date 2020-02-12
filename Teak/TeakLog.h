#import <Foundation/Foundation.h>

@class TeakDeviceConfiguration;
@class TeakAppConfiguration;
@class TeakRemoteConfiguration;
@class TeakDataCollectionConfiguration;
@class Teak;

@interface TeakLog : NSObject
- (void)useSdk:(nonnull NSDictionary*)sdkVersion andXcode:(nonnull NSDictionary*)xcodeVersion;
- (void)useDeviceConfiguration:(nonnull TeakDeviceConfiguration*)deviceConfiguration;
- (void)useAppConfiguration:(nonnull TeakAppConfiguration*)appConfiguration;
- (void)useRemoteConfiguration:(nonnull TeakRemoteConfiguration*)remoteConfiguration;
- (void)useDataCollectionConfiguration:(nonnull TeakDataCollectionConfiguration*)dataCollectionConfiguration;
- (void)logEvent:(nonnull NSString*)eventType level:(nonnull NSString*)logLevel eventData:(nullable NSDictionary*)eventData;

- (nullable id)initForTeak:(nonnull Teak*)teak withAppId:(nonnull NSString*)appId;
@end

extern __attribute__((overloadable)) void TeakLog_t(NSString* _Nonnull method, NSDictionary* _Nullable eventData);

extern __attribute__((overloadable)) void TeakLog_e(NSString* _Nonnull eventType);
extern __attribute__((overloadable)) void TeakLog_e(NSString* _Nonnull eventType, NSDictionary* _Nullable eventData);
extern __attribute__((overloadable)) void TeakLog_e(NSString* _Nonnull eventType, NSString* _Nullable message);
extern __attribute__((overloadable)) void TeakLog_e(NSString* _Nonnull eventType, NSString* _Nullable message, NSDictionary* _Nullable eventData);

extern __attribute__((overloadable)) void TeakLog_i(NSString* _Nonnull eventType);
extern __attribute__((overloadable)) void TeakLog_i(NSString* _Nonnull eventType, NSDictionary* _Nullable eventData);
extern __attribute__((overloadable)) void TeakLog_i(NSString* _Nonnull eventType, NSString* _Nullable message);
extern __attribute__((overloadable)) void TeakLog_i(NSString* _Nonnull eventType, NSString* _Nullable message, NSDictionary* _Nullable eventData);
