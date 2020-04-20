#import <Foundation/Foundation.h>

@interface TeakAppConfiguration : NSObject
@property (strong, nonatomic, readonly) NSString* _Nonnull appId;
@property (strong, nonatomic, readonly) NSString* _Nonnull apiKey;
@property (strong, nonatomic, readonly) NSString* _Nonnull bundleId;
@property (strong, nonatomic, readonly) NSString* _Nonnull appVersion;
@property (strong, nonatomic, readonly) NSString* _Nonnull appVersionName;
@property (strong, nonatomic, readonly) NSSet* _Nonnull urlSchemes;
@property (nonatomic, readonly) BOOL isProduction;
@property (nonatomic, readonly) BOOL traceLog;

- (nullable id)initWithAppId:(nonnull NSString*)appId apiKey:(nonnull NSString*)apiKey;
- (nonnull NSDictionary*)to_h;
@end
