/* Teak -- Copyright (C) 2016 GoCarrot Inc.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#import <Teak/Teak.h>
#import "TeakCache.h"
#import "TeakCachedRequest.h"

#define LOG_TAG "Teak:Cache"

// Cache schema version
#define kCacheSchemaCreateSQL "CREATE TABLE IF NOT EXISTS cache_schema(schema_version INTEGER)"
#define kCacheSchemaReadSQL "SELECT MAX(schema_version) FROM cache_schema"
#define kCacheSchemaInsertSQL "INSERT INTO cache_schema(schema_version) VALUES (%d)"

// v0
#define kCacheCreateV0SQL "CREATE TABLE IF NOT EXISTS cache(request_service INTEGER, request_endpoint TEXT, request_payload TEXT, request_id TEXT, request_date REAL, retry_count INTEGER)"

#define kCacheReadSQL "SELECT rowid, request_service, request_endpoint, request_payload, request_id, request_date, retry_count FROM cache ORDER BY retry_count LIMIT 10"
#define kCacheInsertSQL "INSERT INTO cache (request_service, request_endpoint, request_payload, request_id, request_date, retry_count) VALUES (%d, %Q, %Q, %Q, %f, %d)"
#define kCacheUpdateSQL "UPDATE cache SET retry_count=%d WHERE rowid=%lld"
#define kCacheDeleteSQL "DELETE FROM cache WHERE rowid=%lld"

@interface TeakCache ()

@property (nonatomic, readwrite) sqlite3* sqliteDb;

@end

static BOOL teakcache_begin(sqlite3* cache);
static BOOL teakcache_rollback(sqlite3* cache);
static BOOL teakcache_commit(sqlite3* cache);
#define TEAKCACHE_ROLLBACK_FAIL(test, cache) if(!(test)){ teakcache_rollback(cache); return NO; }

@implementation TeakCache

- (id)init {
   NSError* error = nil;
   NSString* dataPath = nil;

   @try {
      NSArray* searchPaths = [[NSFileManager defaultManager] URLsForDirectory:NSLibraryDirectory inDomains:NSUserDomainMask];
      dataPath = [[[searchPaths lastObject] URLByAppendingPathComponent:@"Teak"] path];
   
   
      BOOL succeeded = [[NSFileManager defaultManager] createDirectoryAtPath:dataPath
                                                 withIntermediateDirectories:YES
                                                                  attributes:nil
                                                                       error:&error];
      if (!succeeded) {
         TeakLog(@"Unable to create Teak data path. %@.", error);
         return nil;
      }
   } @catch (NSException* exception) {
      TeakLog("Error creating Teak data path. %@", exception);
   }

   sqlite3* sqliteDb;
   @try {
      int sql3Err = sqlite3_open([[dataPath stringByAppendingPathComponent:@"RequestQueue.db"] UTF8String], &sqliteDb);
      if (sql3Err != SQLITE_OK) {
         TeakLog(@"Error creating Teak data store at: %@", dataPath);
         return nil;
      }
   } @catch (NSException* exception) {
      TeakLog("Error creating Teak data store. %@", exception);
   }

   self = [super init];
   if (self) {
      self.sqliteDb = sqliteDb;
      if (![self prepareCache]) {
         return nil;
      }
   }
   return self;
}

- (void)dealloc
{
   sqlite3_close(_sqliteDb);
   _sqliteDb = nil;
}

- (sqlite_uint64)cacheRequest:(TeakCachedRequest*)request
{
   sqlite_uint64 cacheId = 0;
   NSError* error = nil;
   NSString* payloadJSON = nil;
   NSData* payloadJSONData = [NSJSONSerialization dataWithJSONObject:[TeakRequest finalPayloadForPayload:request.payload] options:0 error:&error];
   if(error)
   {
      NSLog(@"[Teak] Error converting payload to JSON: %@", error);
      return 0;
   }
   else
   {
      payloadJSON = [[NSString alloc] initWithData:payloadJSONData encoding:NSUTF8StringEncoding];
   }

   sqlite3_stmt* sqlStatement;
   char* sqlString = sqlite3_mprintf(kCacheInsertSQL,
                                     request.serviceType,
                                     [request.endpoint UTF8String],
                                     [payloadJSON UTF8String],
                                     [request.requestId UTF8String],
                                     [request.dateIssued timeIntervalSince1970],
                                     request.retryCount);
   @synchronized(self)
   {
      if(sqlite3_prepare_v2(self.sqliteDb, sqlString, -1, &sqlStatement, NULL) == SQLITE_OK)
      {
         if(sqlite3_step(sqlStatement) == SQLITE_DONE)
         {
            cacheId = sqlite3_last_insert_rowid(self.sqliteDb);
         }
         else
         {
            NSLog(@"[Teak] Failed to write request to Teak cache. Error: '%s'",
                  sqlite3_errmsg(self.sqliteDb));
         }
      }
      else
      {
         NSLog(@"[Teak] Failed to create Teak cache statement for request. Error: '%s'",
               sqlite3_errmsg(self.sqliteDb));
      }
      sqlite3_finalize(sqlStatement);
   }
   sqlite3_free(sqlString);
   return cacheId;
}


- (BOOL)removeRequestFromCache:(TeakCachedRequest*)request
{
   BOOL ret = YES;
   sqlite3_stmt* sqlStatement;
   char* sqlString = sqlite3_mprintf(kCacheDeleteSQL, request.cacheId);

   @synchronized(self)
   {
      if(sqlite3_prepare_v2(self.sqliteDb, sqlString, -1, &sqlStatement, NULL) == SQLITE_OK)
      {
         if(sqlite3_step(sqlStatement) != SQLITE_DONE)
         {
            NSLog(@"[Teak] Failed to delete Teak request id %lld from cache. Error: '%s'",
                  request.cacheId, sqlite3_errmsg(self.sqliteDb));
            ret = NO;
         }
      }
      else
      {
         NSLog(@"[Teak] Failed to create cache delete statement for Teak request id %lld. "
               "Error: '%s'", request.cacheId, sqlite3_errmsg(self.sqliteDb));
         ret = NO;
      }
      sqlite3_finalize(sqlStatement);
      sqlite3_free(sqlString);
   }

   return ret;
}

- (BOOL)addRetryInCacheForRequest:(TeakCachedRequest*)request
{
   BOOL ret = YES;
   sqlite3_stmt* sqlStatement;
   char* sqlString = sqlite3_mprintf(kCacheUpdateSQL, request.retryCount + 1, request.cacheId);

   @synchronized(self)
   {
      if(sqlite3_prepare_v2(self.sqliteDb, sqlString, -1, &sqlStatement, NULL) == SQLITE_OK)
      {
         if(sqlite3_step(sqlStatement) != SQLITE_DONE)
         {
            NSLog(@"[Teak] Failed to update Teak request id %lld in cache. Error: '%s'",
                  request.cacheId, sqlite3_errmsg(self.sqliteDb));
            ret = NO;
         }
      }
      else
      {
         NSLog(@"[Teak] Failed to create cache update statement for Teak request id %lld. "
               "Error: '%s'", request.cacheId, sqlite3_errmsg(self.sqliteDb));
         ret = NO;
      }
      sqlite3_finalize(sqlStatement);
   }
   sqlite3_free(sqlString);

   return ret;
}

- (uint64_t)addRequestsIntoArray:(NSMutableArray*)cacheArray
{
   uint64_t numAdded = 0;
   sqlite3_stmt* sqlStatement;
   @synchronized(self)
   {
      if(sqlite3_prepare_v2(self.sqliteDb, kCacheReadSQL, -1, &sqlStatement, NULL) == SQLITE_OK)
      {
         while(sqlite3_step(sqlStatement) == SQLITE_ROW)
         {
            sqlite_uint64 cacheId = sqlite3_column_int64(sqlStatement, 0);
            NSInteger serviceType = sqlite3_column_int(sqlStatement, 1);
            NSString* requestEndpoint = [NSString stringWithUTF8String:(const char*)sqlite3_column_text(sqlStatement, 2)];
            NSString* requestPayloadJSON = (sqlite3_column_text(sqlStatement, 3) == NULL ? nil : [NSString stringWithUTF8String:(const char*)sqlite3_column_text(sqlStatement, 3)]);
            NSString* requestId = [NSString stringWithUTF8String:(const char*)sqlite3_column_text(sqlStatement, 4)];
            NSDate* requestDate = [NSDate dateWithTimeIntervalSince1970:sqlite3_column_double(sqlStatement, 5)];
            NSUInteger retryCount = sqlite3_column_int(sqlStatement, 6);

            NSError* error = nil;
            NSDictionary* requestPayload = [NSJSONSerialization JSONObjectWithData:[requestPayloadJSON dataUsingEncoding:NSUTF8StringEncoding] options:0 error:&error];

            // Add to array
            if(error)
            {
               NSLog(@"[Teak] Error converting JSON payload to NSDictionary: %@", error);
            }
            else
            {
               TeakCachedRequest* request = [[TeakCachedRequest alloc]
                                             initForService:(TeakRequestServiceType)serviceType
                                             atEndpoint:requestEndpoint
                                             payload:requestPayload
                                             requestId:requestId
                                             dateIssued:requestDate
                                             cacheId:cacheId
                                             retryCount:retryCount
                                             callback:nil];
               if(request)
               {
                  [cacheArray addObject:request];
                  numAdded++;
               }
            }
         }
      }
      else
      {
         NSLog(@"[Teak] Failed to load Teak request cache.\n\t%s", sqlite3_errmsg(self.sqliteDb));
      }
      sqlite3_finalize(sqlStatement);
   }

   return numAdded;
}

- (BOOL)prepareCache {
   BOOL ret = YES;

   sqlite3_stmt* sqlStatement;

   // Create schema version table
   if (sqlite3_prepare_v2(self.sqliteDb, kCacheSchemaCreateSQL, -1, &sqlStatement, NULL) == SQLITE_OK) {
      if (sqlite3_step(sqlStatement) != SQLITE_DONE) {
         TeakLog(@"Failed to create Teak cache schema. Error: %s'", sqlite3_errmsg(self.sqliteDb));
         ret = NO;
      }
   }
   else
   {
      TeakLog(@"Failed to create Teak cache schema statement. Error: '%s'", sqlite3_errmsg(self.sqliteDb));
      ret = NO;
   }
   sqlite3_finalize(sqlStatement);
   if (!ret) return ret;

   // Read cache schema version
   NSUInteger cacheSchemaVersion = 0;
   if (sqlite3_prepare_v2(self.sqliteDb, kCacheSchemaReadSQL, -1, &sqlStatement, NULL) == SQLITE_OK) {
      while(sqlite3_step(sqlStatement) == SQLITE_ROW) {
         cacheSchemaVersion = sqlite3_column_int(sqlStatement, 0);
      }
   }
   sqlite3_finalize(sqlStatement);

   // Create v0 cache if needed
   if (sqlite3_prepare_v2(self.sqliteDb, kCacheCreateV0SQL, -1, &sqlStatement, NULL) == SQLITE_OK) {
      if (sqlite3_step(sqlStatement) != SQLITE_DONE) {
         TeakLog(@"Failed to create Teak cache. Error: %s'", sqlite3_errmsg(self.sqliteDb));
         ret = NO;
      }
   } else {
      TeakLog(@"Failed to create Teak cache statement. Error: '%s'", sqlite3_errmsg(self.sqliteDb));
      ret = NO;
   }
   sqlite3_finalize(sqlStatement);

   return ret;
}

@end

/*
 * Preserving the following for future use:
*/
/*
static BOOL teakcache_begin(sqlite3* cache)
{
   if(sqlite3_exec(cache, "BEGIN TRANSACTION", 0, 0, 0) != SQLITE_OK)
   {
      NSLog(@"[Teak] Failed to begin Teak cache transaction. Error: %s'", sqlite3_errmsg(cache));
      return NO;
   }
   return YES;
}

static BOOL teakcache_rollback(sqlite3* cache)
{
   if(sqlite3_exec(cache, "ROLLBACK", 0, 0, 0) != SQLITE_OK)
   {
      NSLog(@"[Teak] Failed to rollback Teak cache transaction. Error: %s'", sqlite3_errmsg(cache));
      return NO;
   }
   return YES;
}

static BOOL teakcache_commit(sqlite3* cache)
{
   if(sqlite3_exec(cache, "COMMIT", 0, 0, 0) != SQLITE_OK)
   {
      NSLog(@"[Teak] Failed to commit Teak cache transaction. Error: %s'", sqlite3_errmsg(cache));
      return NO;
   }
   return YES;
}
*/