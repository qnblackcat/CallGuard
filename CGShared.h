#import <Foundation/Foundation.h>

#define CG_PREFS_DOMAIN @"com.qn.callguard"
#define CG_PREFS_CHANGED "com.qn.callguard/settingschanged"

#ifdef __cplusplus
extern "C" {
#endif

// Digits only, "+84..." / "0084..." become "0...", other international numbers keep their leading "+".
NSString *CGNormalizeNumber(NSString *raw);

// A rule is stored normalized and needs at least CGMinPrefixLength digits.
#define CGMinPrefixLength 3
NSString *CGNormalizePrefix(NSString *raw);   // nil if it is not a valid rule

BOOL CGNumberMatchesPrefixes(NSString *normalizedNumber, NSArray<NSString *> *prefixes);

// Preferences (CFPreferences domain com.qn.callguard; the daemon, Settings and the tweak all use these)
id CGPrefObject(NSString *key);
BOOL CGPrefBool(NSString *key, BOOL fallback);
NSArray<NSString *> *CGPrefPrefixes(void);
void CGPrefSet(NSString *key, id value);      // also posts CG_PREFS_CHANGED
void CGPrefRefresh(void);                      // drop the cache before re-reading (after CG_PREFS_CHANGED)

#ifdef __cplusplus
}
#endif
