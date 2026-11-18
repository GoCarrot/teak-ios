#import <Foundation/Foundation.h>
#import <os/log.h>

// %{public} so idevicesyslog shows the text instead of <private>.
#define PLOG(fmt, ...) os_log(OS_LOG_DEFAULT, "C392PROBE " fmt, ##__VA_ARGS__)

void ProbeScreen(const char* where, const char* wantCase);
