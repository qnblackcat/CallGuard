#import <Foundation/Foundation.h>

#ifdef __cplusplus
extern "C" {
#endif

// CGLog does nothing unless the Debug switch is on (Settings → CallGuard → Troubleshooting). A macro, so the arguments
// are not evaluated while Debug is off. While on, each line goes to the unified log with the "[CallGuard]" prefix and is
// appended to a log file (capped at CGLogFileMaxBytes, rotated to <name>.1).

#define CGLogFileMaxBytes (128 * 1024)

#define CGLog(fmt, ...) do { if (CGDebugOn) CGLogWrite(@"" fmt, ##__VA_ARGS__); } while (0)

// Set by the tweak (callservicesd) from the Debug preference.
extern BOOL CGDebugOn;

void CGLogWrite(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);

// Used by the preference bundle: the log merged by time, newest last, limited to the last maxBytes characters.
NSString *CGLogFileRead(NSUInteger maxBytes);
void CGLogFileClear(void);

#ifdef __cplusplus
}
#endif
