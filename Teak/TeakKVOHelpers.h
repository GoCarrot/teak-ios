#ifndef TeakKVOHelpers_h
#define TeakKVOHelpers_h

#define TeakUnusedKVOValues TeakUnused(oldValue); TeakUnused(newValue);

#define KeyValueObserverSupported(_thisClass)                                                                                                                                            \
  NSMutableDictionary* kvoRegDictionaryForClassName##_thisClass(NSString* className) {                                                                                                   \
    static NSMutableDictionary* dict;                                                                                                                                                    \
    static dispatch_once_t onceToken;                                                                                                                                                    \
    dispatch_once(&onceToken, ^{ dict = [[NSMutableDictionary alloc] init]; });                                                                                                          \
    NSMutableDictionary* dictForClassName = [dict objectForKey:className];                                                                                                               \
    if (dictForClassName == nil) {                                                                                                                                                       \
      dictForClassName = [[NSMutableDictionary alloc] init];                                                                                                                             \
      [dict setObject:dictForClassName forKey:className];                                                                                                                                \
    }                                                                                                                                                                                    \
    return dictForClassName;                                                                                                                                                             \
  }                                                                                                                                                                                      \
  -(void)observeValueForKeyPath : (NSString*)keyPath ofObject : (id)object change : (NSDictionary<NSString*, id>*)change context : (void*)context {                                      \
    NSString* selector = [kvoRegDictionaryForClassName##_thisClass(NSStringFromClass([object class])) objectForKey:keyPath];                                                             \
    if (selector) {                                                                                                                                                                      \
      SEL sel = NSSelectorFromString(selector);                                                                                                                                          \
      if ([self respondsToSelector:sel]) { [self performSelector:sel withObject:[change objectForKey:NSKeyValueChangeOldKey] withObject:[change objectForKey:NSKeyValueChangeNewKey]]; } \
    }                                                                                                                                                                                    \
  }

#define KeyValueObserverFor(_thisClass, _className, _key)                                                                                                                                                                                                                         \
  __attribute__((constructor)) void _##_thisClass##_className##_##_key##Reg(void) { [kvoRegDictionaryForClassName##_thisClass(@ #_className) setObject:NSStringFromSelector(@selector(_##_className##_##_key##_ChangedFrom:to:)) forKey:NSStringFromSelector(@selector(_key))]; } \
  -(void)_##_className##_##_key##_ChangedFrom : (id)oldValue to : (id)newValue

#define RegisterKeyValueObserverFor(_object, _key) [_object addObserver:self forKeyPath:NSStringFromSelector(@selector(_key)) options:NSKeyValueObservingOptionNew | NSKeyValueObservingOptionOld context:nil]

#define UnRegisterKeyValueObserverFor(_object, _key) [_object removeObserver:self forKeyPath:NSStringFromSelector(@selector(_key))]

#endif /* TeakKVOHelpers_h */
