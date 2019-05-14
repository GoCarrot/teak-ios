//
//  User.m
//  Sample
//
//  Created by Alexander Scarborough on 5/14/19.
//  Copyright © 2019 GoCarrot Inc. All rights reserved.
//

#import "User.h"
#import <Teak/Teak.h>

static User* user = nil;
static NSUInteger RecurringBonus = 10000;
static NSUInteger DefaultCoins = 50000;
static NSUInteger Wager = 1000;
static NSString* coinKey = @"userCoins";
static NSString* slotKey = @"userLastSlot";

@implementation User

@synthesize coins = _coins;
@synthesize lastSlot = _lastSlot;

+ (User*)user
{
  if(!user) {
    user = [[self alloc] init];
  }
  return user;
}

- (User*)init
{
  if(self = [super init]) {
    NSNumber* coinBalance = [[NSUserDefaults standardUserDefaults] objectForKey:coinKey];
    if(!coinBalance) {
      [self resetCoins];
    } else {
      self.coins = [coinBalance unsignedIntegerValue];
    }
    
    NSString* lastSlot = [[NSUserDefaults standardUserDefaults] objectForKey:slotKey];
    if(!lastSlot) {
      self.lastSlot = @"";
    } else {
      self.lastSlot = lastSlot;
    }
  }
  return self;
}

- (void)collectRecurringBonus
{
  self.coins += RecurringBonus;
}

- (SlotWin)playSlot:(NSString *)slot
{
  self.coins -= Wager;
  [[Teak sharedInstance] incrementEventWithActionId:@"bet" forObjectTypeId:slot andObjectInstanceId:nil count:Wager];
  
  NSUInteger result = arc4random_uniform(10);
  NSUInteger win = 0;
  if(result >= 9) {
    win = Wager * 5;
  } else if (result >= 7) {
    win = Wager * 2;
  } else if(result == 6) {
    win = Wager;
  } else if(result >= 3) {
    win = Wager / 2;
  }
  
  [[Teak sharedInstance] incrementEventWithActionId:@"win" forObjectTypeId:slot andObjectInstanceId:nil count:win];

  self.coins += win;
  self.lastSlot = slot;
  
  SlotWin winInfo;
  winInfo.wager = Wager;
  winInfo.win = win;
  
  return winInfo;
}

- (void)resetCoins
{
  self.coins = DefaultCoins;
}

- (void)setCoins:(NSUInteger)coins
{
  @synchronized (self) {
    [[Teak sharedInstance] setNumericAttribute:coins forKey:@"coins"];
    [[NSUserDefaults standardUserDefaults] setObject:[NSNumber numberWithUnsignedInteger:coins] forKey:coinKey];
    _coins = coins;
  }
}

- (NSUInteger)coins
{
  @synchronized (self) {
    return _coins;
  }
}

- (void)setLastSlot:(NSString *)lastSlot
{
  @synchronized (self) {
    [[Teak sharedInstance] setStringAttribute:lastSlot forKey:@"lastSlot"];
    [[NSUserDefaults standardUserDefaults] setObject:lastSlot forKey:slotKey];
    _lastSlot = lastSlot;
  }
}

- (NSString*)lastSlot
{
  @synchronized (self) {
    return _lastSlot;
  }
}

@end
