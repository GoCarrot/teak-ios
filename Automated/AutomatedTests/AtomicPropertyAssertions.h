#import <objc/runtime.h>

// YES if `name` is declared on `cls` as an atomic property, i.e. its runtime attribute string has no
// "N" (nonatomic) token. A property that doesn't exist also returns NO, so a rename fails the
// assertion instead of silently passing. Use with XCTAssertTrue.
static inline BOOL isAtomicProperty(Class cls, const char* name) {
  objc_property_t property = class_getProperty(cls, name);
  if (property == NULL) return NO;
  NSArray* attributes = [@(property_getAttributes(property)) componentsSeparatedByString:@","];
  return ![attributes containsObject:@"N"];
}
