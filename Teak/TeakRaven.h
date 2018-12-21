#import "UserIdEvent.h"

extern NSString* _Nonnull const TeakRavenLevelError;
extern NSString* _Nonnull const TeakRavenLevelFatal;

@class Teak;

@interface TeakRavenLocationHelper : NSObject

@property (strong, nonatomic) NSException* _Nonnull exception;

+ (nonnull TeakRavenLocationHelper*)pushHelperForFile:(const char* _Nonnull)file line:(int)line function:(const char* _Nonnull)function;
+ (nullable TeakRavenLocationHelper*)popHelper;
+ (nullable TeakRavenLocationHelper*)peekHelper;

- (void)addBreadcrumb:(nonnull NSString*)category message:(nullable NSString*)message data:(nullable NSDictionary*)data file:(const char* _Nonnull)file line:(int)line;

@end

@interface TeakRaven : NSObject <TeakEventHandler>

+ (nullable TeakRaven*)ravenForTeak:(nonnull Teak*)teak;
+ (nullable TeakRaven*)ravenForAppWithTeak:(nonnull Teak*)teak;

- (BOOL)setDSN:(nonnull NSString*)dsn;
- (void)setAsUncaughtExceptionHandler;
- (void)unsetAsUncaughtExceptionHandler;

- (void)reportWithHelper:(nonnull TeakRavenLocationHelper*)helper;

+ (nonnull NSArray*)stacktraceSkippingFrames:(int)skipFrames;
+ (nonnull NSArray*)reverseStacktraceSkippingFrames:(int)skipFrames;
@end

#define teak_try                                                                                   \
  [TeakRavenLocationHelper pushHelperForFile:__FILE__ line:__LINE__ function:__PRETTY_FUNCTION__]; \
  @try
#define teak_catch_report                                                                   \
  @catch (NSException * exception) {                                                        \
    [TeakRavenLocationHelper peekHelper].exception = exception;                             \
    [[Teak sharedInstance].sdkRaven reportWithHelper:[TeakRavenLocationHelper peekHelper]]; \
  }                                                                                         \
  @finally {                                                                                \
    [TeakRavenLocationHelper popHelper];                                                    \
  }                                                                                         \
  ((void)0) // This is so clang-format doesn't indent the lines following a teak_catch_report

#define teak_log_breadcrumb(message_nsstr) [[TeakRavenLocationHelper peekHelper] addBreadcrumb:@"log" message:message_nsstr data:nil file:__FILE__ line:__LINE__]
#define teak_log_data_breadcrumb(message_nsstr, data_nsdict) [[TeakRavenLocationHelper peekHelper] addBreadcrumb:@"log" message:message_nsstr data:data_nsdict file:__FILE__ line:__LINE__]
