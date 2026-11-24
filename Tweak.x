// CallGuard, callservicesd part (iOS 15 to 18): silently filters incoming cellular calls whose number starts with one of
// the user's prefixes, unless the number belongs to a contact. See RESEARCH.md.
// The Phone app part lives in TweakPhone.x; the decisions and preferences are in CGPolicy.m.
#import <Foundation/Foundation.h>
#import <UserNotifications/UserNotifications.h>
#import "CGPrivate.h"
#import "CGPolicy.h"
#import "CGLog.h"

@interface CSDCallFilterController : NSObject
@end

// iOS 15 calls the same thing CSDCallFilterManager. It has no filters getter, only an ivar of that name.
@interface CSDCallFilterManager : NSObject
@end

// Same value CSDCallFilterController uses itself when one of its filters rejects a call
static const int kFilteredOutReason = 2;

%group iOS16

%hook CSDCallFilterController

- (BOOL)shouldFilterIncomingCall:(id)call {
	if (CGShouldBlock(self, call, [call handle], [[call provider] isTelephonyProvider])) {
		[call setFilteredOutReason:kFilteredOutReason];
		return YES;
	}
	return %orig;
}

%end

%end

%group iOS15

%hook CSDCallFilterManager

- (BOOL)shouldFilterIncomingCall:(id)call {
	if (CGShouldBlock(self, call, [call handle], [[call provider] isTelephonyProvider])) {
		[call setFilteredOutReason:kFilteredOutReason];
		return YES;
	}
	return %orig;
}

%end

%end

%group iOS17

%hook CSDCallFilterController

- (BOOL)shouldFilterIncomingCall:(id)update from:(id)provider {
	if (CGShouldBlock(self, update, [update remoteHandle], [provider isTelephonyProvider])) {
		if (![update filteredOutReason]) [update setFilteredOutReason:kFilteredOutReason];
		return YES;
	}
	return %orig;
}

%end

%end

%group Daemon

%hook UNUserNotificationCenter

- (void)addNotificationRequest:(UNNotificationRequest *)request withCompletionHandler:(void (^)(NSError *))completionHandler {
	if (CGShouldDropNotification(request)) {
		CGLog(@"dropped notification %@", request.identifier);
		if (completionHandler) completionHandler(nil);
		return;
	}
	%orig;
}

%end

%end

%ctor {
	NSString *process = NSProcessInfo.processInfo.processName;
	if ([process isEqualToString:@"MobilePhone"]) return;   // handled by TweakPhone.x
	CGPolicyInit();
	// No iOS 17 constant in version.h: tell the two APIs apart by the selector
	CGUpdateAPI = [%c(CSDCallFilterController) instancesRespondToSelector:@selector(shouldFilterIncomingCall:from:)];
	CGLog(@"loaded in %@, update API (iOS 17): %d", process, CGUpdateAPI);
	if (CGUpdateAPI) {
		%init(iOS17);
	} else if (%c(CSDCallFilterController)) {
		%init(iOS16);
	} else {
		%init(iOS15);   // the filter class was still called CSDCallFilterManager
	}
	%init(Daemon);
}
