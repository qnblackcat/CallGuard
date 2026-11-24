#import "CGShared.h"
#include <notify.h>

// Everything that is not an ASCII digit is dropped, so the spaces iOS inserts when a number is copied ("028 5671 2345"),
// no-break spaces, the invisible direction marks (U+202A, U+202C, U+200E...) around it, dashes and brackets all go. A "+"
// is only kept in front of the first digit.
NSString *CGNormalizeNumber(NSString *raw) {
	if (![raw isKindOfClass:[NSString class]]) return @"";
	NSMutableString *out = [NSMutableString string];
	for (NSUInteger i = 0; i < raw.length; i++) {
		unichar c = [raw characterAtIndex:i];
		if (c >= '0' && c <= '9') [out appendFormat:@"%C", c];
		else if (c == '+' && out.length == 0) [out appendString:@"+"];
	}
	if ([out hasPrefix:@"+84"]) return [@"0" stringByAppendingString:[out substringFromIndex:3]];
	if ([out hasPrefix:@"0084"]) return [@"0" stringByAppendingString:[out substringFromIndex:4]];
	// Some carriers deliver the number without the "+": 84946134510. Vietnamese numbers are 10-11 digits after the 0,
	// so 84 followed by 9-10 digits can only be the international form.
	if ([out hasPrefix:@"84"] && (out.length == 11 || out.length == 12)) return [@"0" stringByAppendingString:[out substringFromIndex:2]];
	return out;
}

NSString *CGNormalizePrefix(NSString *raw) {
	NSString *prefix = CGNormalizeNumber(raw);
	NSString *digits = [prefix hasPrefix:@"+"] ? [prefix substringFromIndex:1] : prefix;
	return digits.length >= CGMinPrefixLength ? prefix : nil;
}

BOOL CGNumberMatchesPrefixes(NSString *number, NSArray<NSString *> *prefixes) {
	if (!number.length) return NO;
	for (NSString *prefix in prefixes) {
		if (prefix.length >= CGMinPrefixLength && [number hasPrefix:prefix]) return YES;
	}
	return NO;
}

id CGPrefObject(NSString *key) {
	CFPropertyListRef value = CFPreferencesCopyValue((__bridge CFStringRef)key, (__bridge CFStringRef)CG_PREFS_DOMAIN,
	                                                 kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
	return CFBridgingRelease(value);
}

BOOL CGPrefBool(NSString *key, BOOL fallback) {
	id value = CGPrefObject(key);
	return [value respondsToSelector:@selector(boolValue)] ? [value boolValue] : fallback;
}

NSArray<NSString *> *CGPrefPrefixes(void) {
	id value = CGPrefObject(@"Prefixes");
	if (![value isKindOfClass:[NSArray class]]) return @[];
	NSMutableArray *prefixes = [NSMutableArray array];
	for (id item in value) {
		NSString *prefix = [item isKindOfClass:[NSString class]] ? CGNormalizePrefix(item) : nil;
		if (prefix && ![prefixes containsObject:prefix]) [prefixes addObject:prefix];
	}
	return prefixes;
}

void CGPrefRefresh(void) {
	CFPreferencesSynchronize((__bridge CFStringRef)CG_PREFS_DOMAIN, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
}

void CGPrefSet(NSString *key, id value) {
	CFPreferencesSetValue((__bridge CFStringRef)key, (__bridge CFPropertyListRef)value, (__bridge CFStringRef)CG_PREFS_DOMAIN,
	                      kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
	CFPreferencesSynchronize((__bridge CFStringRef)CG_PREFS_DOMAIN, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
	notify_post(CG_PREFS_CHANGED);
}
