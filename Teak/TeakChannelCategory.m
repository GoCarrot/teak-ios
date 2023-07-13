#import "TeakChannelCategory.h"

@interface TeakChannelCategory ()
@property (strong, nonatomic, readwrite) NSString* _Nonnull id;
@property (strong, nonatomic, readwrite) NSString* _Nonnull name;
@property (strong, nonatomic, readwrite) NSString* _Nullable categoryDescription;
@end

@implementation TeakChannelCategory

+ (nonnull NSArray*)createFromRemoteConfiguration:(nullable NSDictionary*)availableCategories {
  if(NSNullOrNil(availableCategories)) {
    return @[];
  }

  NSMutableArray* categories = [[NSMutableArray alloc] init];
  for (NSString* key in availableCategories) {
    NSDictionary* categoryInfo = availableCategories[key];
    TeakChannelCategory* category = [[TeakChannelCategory alloc] initWithId:key name:categoryInfo[@"name"] andDescription:categoryInfo[@"description"]];
    [categories addObject:category];
  }
  return [NSArray arrayWithArray:categories];
}

- (nonnull TeakChannelCategory*)initWithId:(nonnull NSString*)id name:(nonnull NSString*)name andDescription:(nullable NSString*)description {
  self = [super init];
  if(self) {
    self.id = id;
    self.name = name;
    self.categoryDescription = description;
  }

  return self;
}

- (nonnull NSDictionary*)toDictionary {
  NSMutableDictionary* ret = [[NSMutableDictionary alloc] init];
  ret[@"id"] = self.id;
  ret[@"name"] = self.name;
  ret[@"description"] = self.categoryDescription;
  return ret;
}

@end
