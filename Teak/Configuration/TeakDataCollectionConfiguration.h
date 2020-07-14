#import "TeakEvent.h"
#import <Foundation/Foundation.h>

@interface TeakDataCollectionConfiguration : NSObject <TeakEventHandler>

@property (nonatomic, readonly) BOOL enableIDFA;
@property (nonatomic, readonly) BOOL enableFacebookAccessToken;
@property (nonatomic, readonly) BOOL enablePushKey;

- (NSDictionary*)to_h;

// Future-Pat: No, we do *not* want to ever configure what data is collected as the result of a server call,
//             because that would change us from being a "data processor" to a "data controller" under the GDPR
- (void)addConfigurationFromDeveloper:(NSArray*)optOutList;
@end
