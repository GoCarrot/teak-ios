#import <Foundation/Foundation.h>

#import "TeakAppConfiguration.h"
#import "TeakDataCollectionConfiguration.h"
#import "TeakDebugConfiguration.h"
#import "TeakDeviceConfiguration.h"

@interface TeakConfiguration : NSObject
@property (strong, nonatomic, readonly) TeakDebugConfiguration* _Nonnull debugConfiguration;
@property (strong, nonatomic, readonly) TeakAppConfiguration* _Nonnull appConfiguration;
@property (strong, nonatomic, readonly) TeakDeviceConfiguration* _Nonnull deviceConfiguration;
@property (strong, nonatomic, readonly) TeakDataCollectionConfiguration* _Nonnull dataCollectionConfiguration;

+ (nonnull TeakConfiguration*)configuration;
+ (BOOL)configureForAppId:(NSString* _Nonnull)appId andSecret:(NSString* _Nonnull)appSecret;
@end
