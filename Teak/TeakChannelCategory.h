#import <Foundation/Foundation.h>

@interface TeakChannelCategory : NSObject
@property (strong, nonatomic, readonly) NSString* _Nonnull id;
@property (strong, nonatomic, readonly) NSString* _Nonnull name;
// the 'description' property is already taken by NSObject
@property (strong, nonatomic, readonly) NSString* _Nullable categoryDescription;

+ (nonnull NSArray*)createFromRemoteConfiguration:(nullable NSDictionary*)availableCategories;
- (nonnull TeakChannelCategory*)initWithId:(nonnull NSString*)id name:(nonnull NSString*)name andDescription:(nullable NSString*)description;
- (nonnull NSDictionary*)toDictionary;
@end
