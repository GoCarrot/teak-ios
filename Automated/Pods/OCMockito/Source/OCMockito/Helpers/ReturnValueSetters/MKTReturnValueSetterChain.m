//  OCMockito by Jon Reid, https://qualitycoding.org/
//  Copyright 2018 Jonathan M. Reid. See LICENSE.txt

#import "MKTReturnValueSetterChain.h"

#import "MKTBoolReturnSetter.h"
#import "MKTCharReturnSetter.h"
#import "MKTClassReturnSetter.h"
#import "MKTDoubleReturnSetter.h"
#import "MKTFloatReturnSetter.h"
#import "MKTIntReturnSetter.h"
#import "MKTLongLongReturnSetter.h"
#import "MKTLongReturnSetter.h"
#import "MKTObjectReturnSetter.h"
#import "MKTShortReturnSetter.h"
#import "MKTStructReturnSetter.h"
#import "MKTUnsignedCharReturnSetter.h"
#import "MKTUnsignedIntReturnSetter.h"
#import "MKTUnsignedLongLongReturnSetter.h"
#import "MKTUnsignedLongReturnSetter.h"
#import "MKTUnsignedShortReturnSetter.h"

MKTReturnValueSetter* MKTReturnValueSetterChain(void) {
  static MKTReturnValueSetter* chain = nil;
  if (!chain) {
    MKTReturnValueSetter* structSetter = [[MKTStructReturnSetter alloc] initWithSuccessor:nil];
    MKTReturnValueSetter* doubleSetter = [[MKTDoubleReturnSetter alloc] initWithSuccessor:structSetter];
    MKTReturnValueSetter* floatSetter = [[MKTFloatReturnSetter alloc] initWithSuccessor:doubleSetter];
    MKTReturnValueSetter* uLongLongSetter = [[MKTUnsignedLongLongReturnSetter alloc] initWithSuccessor:floatSetter];
    MKTReturnValueSetter* uLongSetter = [[MKTUnsignedLongReturnSetter alloc] initWithSuccessor:uLongLongSetter];
    MKTReturnValueSetter* uShortSetter = [[MKTUnsignedShortReturnSetter alloc] initWithSuccessor:uLongSetter];
    MKTReturnValueSetter* uIntSetter = [[MKTUnsignedIntReturnSetter alloc] initWithSuccessor:uShortSetter];
    MKTReturnValueSetter* uCharSetter = [[MKTUnsignedCharReturnSetter alloc] initWithSuccessor:uIntSetter];
    MKTReturnValueSetter* longLongSetter = [[MKTLongLongReturnSetter alloc] initWithSuccessor:uCharSetter];
    MKTReturnValueSetter* longSetter = [[MKTLongReturnSetter alloc] initWithSuccessor:longLongSetter];
    MKTReturnValueSetter* shortSetter = [[MKTShortReturnSetter alloc] initWithSuccessor:longSetter];
    MKTReturnValueSetter* intSetter = [[MKTIntReturnSetter alloc] initWithSuccessor:shortSetter];
    MKTReturnValueSetter* boolSetter = [[MKTBoolReturnSetter alloc] initWithSuccessor:intSetter];
    MKTReturnValueSetter* charSetter = [[MKTCharReturnSetter alloc] initWithSuccessor:boolSetter];
    MKTReturnValueSetter* classSetter = [[MKTClassReturnSetter alloc] initWithSuccessor:charSetter];
    MKTReturnValueSetter* objectSetter = [[MKTObjectReturnSetter alloc] initWithSuccessor:classSetter];
    chain = objectSetter;
  }
  return chain;
}
