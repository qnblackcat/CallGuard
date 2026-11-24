#import <Foundation/Foundation.h>
#include <notify.h>
#import "CGPolicy.h"
#import "CGShared.h"
#import "CGLog.h"

BOOL CGUpdateAPI = NO;

static BOOL sEnabled = YES;
static BOOL sHideMissedAlert = YES;
static BOOL sAllowCalled = YES;
static BOOL sBlockContacts = NO;
static NSArray<NSString *> *sPrefixes;
static BOOL sConfirmCalls = NO;     // read from prefs in callservicesd, published to the Phone app (see CGPublishConfirmState)
static BOOL sIsPhoneApp = NO;

#define CG_CONFIRM_STATE "com.qn.callguard/confirmstate"

static void CGPublishConfirmState(void) {
	static int token = -1;
	if (token < 0 && notify_register_check(CG_CONFIRM_STATE, &token) != NOTIFY_STATUS_OK) { token = -1; return; }
	notify_set_state(token, sConfirmCalls ? 1 : 0);
}

BOOL CGPhoneConfirmCalls(void) {
	static int token = -1;
	if (token < 0 && notify_register_check(CG_CONFIRM_STATE, &token) != NOTIFY_STATUS_OK) { token = -1; return NO; }
	uint64_t state = 0;
	if (notify_get_state(token, &state) != NOTIFY_STATUS_OK) return NO;
	return state != 0;
}

static void CGReloadPrefs(void) {
	CGPrefRefresh();
	sEnabled = CGPrefBool(@"Enabled", YES);
	sHideMissedAlert = CGPrefBool(@"HideMissedAlert", YES);
	sAllowCalled = CGPrefBool(@"AllowCalledNumbers", YES);
	sBlockContacts = CGPrefBool(@"BlockContacts", NO);
	sConfirmCalls = CGPrefBool(@"ConfirmCalls", NO);
	CGDebugOn = CGPrefBool(@"Debug", NO);
	sPrefixes = CGPrefPrefixes();
	if (!sIsPhoneApp) CGPublishConfirmState();
	CGLog(@"prefs: enabled=%d hideMissedAlert=%d allowCalled=%d blockContacts=%d confirmCalls=%d prefixes=%lu", sEnabled, sHideMissedAlert, sAllowCalled, sBlockContacts, sConfirmCalls, (unsigned long)sPrefixes.count);
}

void CGPolicyInit(void) {
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		sIsPhoneApp = [NSProcessInfo.processInfo.processName isEqualToString:@"MobilePhone"];
		CGReloadPrefs();
		static int token;
		notify_register_dispatch(CG_PREFS_CHANGED, &token, dispatch_get_main_queue(), ^(int t) {
			CGReloadPrefs();
		});
	});
}

// The individual filters of the controller (iOS 16+) or manager (iOS 15, no getter: read the ivar through KVC)
static NSArray *CGFilters(id controller) {
	id filters = [controller respondsToSelector:@selector(filters)] ? [controller filters] : [controller valueForKey:@"filters"];
	return [filters isKindOfClass:[NSArray class]] ? filters : [filters allObjects];
}

static BOOL CGIsUnknown(id object, id subject) {
	return CGUpdateAPI ? [object isUnknownCaller:subject] : [object isUnknownCall:subject];
}

// YES only if the number is saved in Contacts. CSDContactsCallFilter's own verdict is wider: it also counts Siri
// "suggested" names (numbers seen in Messages, Mail, Safari...), Apple Care and the carrier's number. While it works it
// records the strict answer in the call's silencingUserInfo under CSDCallMetricsKnownContact, so ask for that.
// If there is no contacts filter we fall back to the controller's aggregate check (which also trusts the call history).
static BOOL CGCallerIsContact(id controller, id subject) {
	Class contactsFilter = NSClassFromString(@"CSDContactsCallFilter");
	if (contactsFilter) {
		for (id filter in CGFilters(controller)) {
			if (![filter isKindOfClass:contactsFilter]) continue;
			BOOL unknown = CGIsUnknown(filter, subject);   // fills silencingUserInfo
			id info = [subject respondsToSelector:@selector(silencingUserInfo)] ? [subject silencingUserInfo] : nil;
			id known = [info isKindOfClass:[NSDictionary class]] ? info[@"CSDCallMetricsKnownContact"] : nil;
			CGLog(@"contacts filter: unknown=%d knownContact=%@ info=%@", unknown, known, info);
			return known ? [known boolValue] : !unknown;
		}
	}
	CGLog(@"no CSDContactsCallFilter among the filters, using the controller's own check");
	return !CGIsUnknown(controller, subject);
}

// YES if Recents holds an outgoing call to this number (CSDCallHistoryCallFilter: any call you placed, no time limit
// other than how long iOS keeps it in Recents), e.g. a clinic or a courier from a blocked range calling you back.
static BOOL CGCallerWasCalled(id controller, id subject) {
	Class historyFilter = NSClassFromString(@"CSDCallHistoryCallFilter");
	if (!historyFilter) return NO;
	for (id filter in CGFilters(controller)) {
		if ([filter isKindOfClass:historyFilter]) return !CGIsUnknown(filter, subject);
	}
	return NO;
}

BOOL CGShouldBlock(id controller, id subject, TUHandle *handle, BOOL telephony) {
	if (!sEnabled || !sPrefixes.count || !telephony) return NO;
	NSString *number = CGNormalizeNumber(handle.value);
	if (!number.length) return NO;                               // hidden number: leave it alone
	if (!CGNumberMatchesPrefixes(number, sPrefixes)) return NO;
	if (!sBlockContacts && CGCallerIsContact(controller, subject)) {
		CGLog(@"%@ matches a rule but is a contact: allowed", number);
		return NO;
	}
	if (sAllowCalled && CGCallerWasCalled(controller, subject)) {
		CGLog(@"%@ matches a rule but you called it before: allowed", number);
		return NO;
	}
	CGLog(@"%@ matches a rule: blocked", number);
	return YES;
}

// A missed-call notification for a number we blocked: its text carries the number (a contact would show a name instead)
static BOOL CGNotificationIsForBlockedNumber(UNNotificationRequest *request) {
	UNNotificationContent *content = request.content;
	NSMutableString *text = [NSMutableString string];
	for (NSString *part in @[content.title ?: @"", content.subtitle ?: @"", content.body ?: @"", [content.userInfo description] ?: @""]) {
		[text appendFormat:@"%@\n", part];
	}
	static NSRegularExpression *regex;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		regex = [NSRegularExpression regularExpressionWithPattern:@"\\+?[0-9][0-9 ()\\-.]{5,}[0-9]" options:0 error:NULL];
	});
	// Only drop it if every number in it is one we block, so a notification that also names someone else survives
	BOOL any = NO;
	for (NSTextCheckingResult *match in [regex matchesInString:text options:0 range:NSMakeRange(0, text.length)]) {
		NSString *number = CGNormalizeNumber([text substringWithRange:match.range]);
		if (!CGNumberMatchesPrefixes(number, sPrefixes)) return NO;
		any = YES;
	}
	return any;
}

BOOL CGShouldDropNotification(UNNotificationRequest *request) {
	return sEnabled && sHideMissedAlert && sPrefixes.count && CGNotificationIsForBlockedNumber(request);
}
