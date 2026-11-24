// MobilePhone (the Phone app): optional "Are you sure you want to call?" alert for calls placed from Keypad / Recents / Favorites.
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "CGPrivate.h"
#import "CGPolicy.h"
#import "CGLog.h"

@interface DialerController : NSObject
- (NSUInteger)digitsEntered;
- (id)dialerView;
- (void)_callButtonPressedActionWithCallProvider:(id)provider;
@end

@interface PHRecentsController : NSObject
- (void)performDialRequestForRecentCall:(id)call;
@end

@interface MPFavoritesTableViewController : NSObject
- (id)favoritesEntryAtIndex:(NSInteger)index;
- (void)tableView:(id)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath;
@end

static BOOL sBypassConfirm = NO;    // set while we re-run the original call action after the user said yes
static BOOL sConfirmShowing = NO;   // a second tap while the alert is up is ignored

static UIViewController *CGTopViewController(void) {
	UIWindow *window = nil;
	for (UIScene *scene in [%c(UIApplication) sharedApplication].connectedScenes) {
		if (![scene isKindOfClass:%c(UIWindowScene)] || scene.activationState != UISceneActivationStateForegroundActive) continue;
		for (UIWindow *candidate in ((UIWindowScene *)scene).windows) {
			if (candidate.isKeyWindow) { window = candidate; break; }
		}
		if (window) break;
	}
	UIViewController *top = window.rootViewController;
	while (top.presentedViewController) top = top.presentedViewController;
	return top;
}

// "who" is the contact name when there is one, otherwise the number. proceed() starts the call.
// With no view controller to show the alert on we let the call through rather than swallow it.
static void CGConfirmCall(NSString *who, void (^proceed)(void), void (^cancel)(void)) {
	UIViewController *top = CGTopViewController();
	if (!top) { proceed(); return; }
	if (sConfirmShowing) return;
	BOOL vietnamese = [[NSLocale preferredLanguages].firstObject hasPrefix:@"vi"];
	NSString *title = [NSString stringWithFormat:vietnamese ? @"Gọi %@?" : @"Call %@?", who];
	UIAlertController *alert = [%c(UIAlertController) alertControllerWithTitle:title message:nil preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[%c(UIAlertAction) actionWithTitle:vietnamese ? @"Huỷ" : @"Cancel" style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
		sConfirmShowing = NO;
		if (cancel) cancel();
	}]];
	[alert addAction:[%c(UIAlertAction) actionWithTitle:vietnamese ? @"Gọi" : @"Call" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
		sConfirmShowing = NO;
		proceed();
	}]];
	sConfirmShowing = YES;
	[top presentViewController:alert animated:YES completion:nil];
}

%group Phone

// Keypad: the green call button. With no digits typed the button only restores the last dialed number, so leave that alone.
%hook DialerController

- (void)_callButtonPressedActionWithCallProvider:(id)provider {
	if (!CGPhoneConfirmCalls() || sBypassConfirm || ![self digitsEntered]) {
		%orig;
		return;
	}
	id lcdView = [[self dialerView] lcdView];
	NSString *number = [lcdView text];
	if (!number.length) {
		%orig;
		return;
	}
	id nameLabel = [lcdView contactLabel];
	NSString *name = [nameLabel respondsToSelector:@selector(displayedName)] ? [nameLabel displayedName] : nil;
	CGConfirmCall(name.length ? name : number, ^{
		sBypassConfirm = YES;
		[self _callButtonPressedActionWithCallProvider:provider];
		sBypassConfirm = NO;
	}, nil);
}

%end

// Recents: tapping a row, or the call-back button of a row, ends up here with the CHRecentCall
%hook PHRecentsController

- (void)performDialRequestForRecentCall:(id)call {
	if (!CGPhoneConfirmCalls() || sBypassConfirm) {
		%orig;
		return;
	}
	NSString *name = [call callerName];
	NSString *who = name.length ? name : [call callerId];
	if (!who.length) {
		%orig;
		return;
	}
	CGConfirmCall(who, ^{
		sBypassConfirm = YES;
		[self performDialRequestForRecentCall:call];
		sBypassConfirm = NO;
	}, nil);
}

%end

// Favorites: tapping a row performs the favorite's action (call, message, mail...). Only call actions are confirmed.
// iOS 18 can instead open the contact card on a tap and place the call from a button on it (feature flag
// favoritesCallTapTargetsEnabled), which this hook does not cover, so it stays out of the way in that case.
%hook MPFavoritesTableViewController

- (void)tableView:(id)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	if (!CGPhoneConfirmCalls() || sBypassConfirm || !indexPath || indexPath.row == NSNotFound) {
		%orig;
		return;
	}
	id flags = [self respondsToSelector:@selector(featureFlags)] ? [self featureFlags] : nil;
	if ([flags respondsToSelector:@selector(favoritesCallTapTargetsEnabled)] && [flags favoritesCallTapTargetsEnabled]) {
		%orig;
		return;
	}
	id entry = [self favoritesEntryAtIndex:indexPath.row];
	NSString *action = [[entry actionType] lowercaseString];
	BOOL notACall = [action containsString:@"message"] || [action containsString:@"mail"] || [action containsString:@"sms"] || [action containsString:@"text"];
	NSString *name = [entry name];
	NSString *who = name.length ? name : [entry valueForKey:@"value"];
	if (!entry || notACall || !who.length) {
		%orig;
		return;
	}
	CGConfirmCall(who, ^{
		sBypassConfirm = YES;
		[self tableView:tableView didSelectRowAtIndexPath:indexPath];
		sBypassConfirm = NO;
	}, ^{
		[tableView deselectRowAtIndexPath:indexPath animated:YES];
	});
}

%end

%end

%ctor {
	NSString *process = NSProcessInfo.processInfo.processName;
	if (![process isEqualToString:@"MobilePhone"]) return;
	CGPolicyInit();
	CGLog(@"loaded in %@", process);
	%init(Phone);
}
