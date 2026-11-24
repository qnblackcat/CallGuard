#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import "../CGShared.h"
#import "../CGLog.h"
#include <sys/utsname.h>

#define CGLogCopyMaxBytes (200 * 1024)
#define LOC(key) [[NSBundle bundleForClass:CGRootListController.class] localizedStringForKey:key value:nil table:nil]

@interface CGRootListController : PSListController
@end

@implementation CGRootListController

- (NSArray *)specifiers {
	if (!_specifiers) {
		_specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
		// the saved prefixes go between the block-list group and the Add button
		PSSpecifier *group = nil;
		for (PSSpecifier *specifier in _specifiers) {
			if ([specifier.identifier isEqualToString:@"prefixGroup"]) { group = specifier; break; }
		}
		// group icons live in the plist (cgIcon), not in the translated strings
		for (PSSpecifier *specifier in _specifiers) {
			NSString *icon = [specifier propertyForKey:@"cgIcon"];
			if (icon && specifier.name.length) specifier.name = [NSString stringWithFormat:@"%@ %@", icon, specifier.name];
		}
		NSUInteger index = group ? [_specifiers indexOfObject:group] + 1 : _specifiers.count;
		for (NSString *prefix in CGPrefPrefixes()) {
			[_specifiers insertObject:[self rowForPrefix:prefix] atIndex:index++];
		}
	}
	return _specifiers;
}

- (PSSpecifier *)rowForPrefix:(NSString *)prefix {
	// PSStaticTextCell is greyed out and cannot be tapped; a button cell can (didSelectRowAtIndexPath: below catches the tap)
	PSSpecifier *row = [PSSpecifier preferenceSpecifierNamed:prefix target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
	row.buttonAction = @selector(noAction);
	[row setProperty:prefix forKey:@"cgPrefix"];
	return row;
}

- (void)noAction {}

// Make the prefix rows look like plain list rows, not centred blue buttons
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	UITableViewCell *cell = [super tableView:tableView cellForRowAtIndexPath:indexPath];
	if ([[self specifierAtIndexPath:indexPath] propertyForKey:@"cgPrefix"]) {
		cell.textLabel.textColor = [UIColor labelColor];
		cell.textLabel.textAlignment = NSTextAlignmentNatural;
		cell.selectionStyle = UITableViewCellSelectionStyleDefault;
		cell.userInteractionEnabled = YES;
	}
	return cell;
}

- (PSSpecifier *)lastPrefixRow {
	PSSpecifier *last = nil;
	for (PSSpecifier *specifier in self.specifiers) {
		if ([specifier propertyForKey:@"cgPrefix"]) last = specifier;
	}
	return last;
}

#pragma mark - Prefixes

- (void)addPrefix {
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:LOC(@"ADD_RULE_TITLE") message:LOC(@"ADD_RULE_MESSAGE") preferredStyle:UIAlertControllerStyleAlert];
	[alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
		field.keyboardType = UIKeyboardTypePhonePad;
		field.placeholder = @"0285671";
	}];
	[alert addAction:[UIAlertAction actionWithTitle:LOC(@"CANCEL") style:UIAlertActionStyleCancel handler:nil]];
	[alert addAction:[UIAlertAction actionWithTitle:LOC(@"ADD") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
		[self savePrefix:alert.textFields.firstObject.text];
	}]];
	[self presentViewController:alert animated:YES completion:nil];
}

// A rule with fewer than 5 digits (like 094) can swallow a whole carrier's numbers: ask before saving it
- (void)confirmIfShort:(NSString *)prefix thenSave:(void (^)(void))save {
	NSString *digits = [prefix hasPrefix:@"+"] ? [prefix substringFromIndex:1] : prefix;
	if (digits.length >= 5) {
		save();
		return;
	}
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:LOC(@"SHORT_PREFIX_TITLE") message:[NSString stringWithFormat:LOC(@"SHORT_PREFIX_MESSAGE"), prefix, (unsigned long)digits.length] preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:LOC(@"CANCEL") style:UIAlertActionStyleCancel handler:nil]];
	[alert addAction:[UIAlertAction actionWithTitle:LOC(@"SAVE_ANYWAY") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) { save(); }]];
	[self presentViewController:alert animated:YES completion:nil];
}

- (void)savePrefix:(NSString *)text {
	NSString *prefix = CGNormalizePrefix(text);
	if (!prefix) {
		[self showAlertWithTitle:LOC(@"INVALID_PREFIX_TITLE") message:LOC(@"INVALID_PREFIX_MESSAGE")];
		return;
	}
	NSArray<NSString *> *current = CGPrefPrefixes();
	if ([current containsObject:prefix]) return;
	[self confirmIfShort:prefix thenSave:^{
		CGPrefSet(@"Prefixes", [CGPrefPrefixes() arrayByAddingObject:prefix]);
		PSSpecifier *after = [self lastPrefixRow] ?: [self specifierForID:@"prefixGroup"];
		[self insertSpecifier:[self rowForPrefix:prefix] afterSpecifier:after animated:YES];
	}];
}

// Tap a saved prefix to change it
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	PSSpecifier *row = [self specifierAtIndexPath:indexPath];
	NSString *prefix = [row propertyForKey:@"cgPrefix"];
	if (!prefix) {
		[super tableView:tableView didSelectRowAtIndexPath:indexPath];
		return;
	}
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	[self editPrefix:prefix];
}

- (void)editPrefix:(NSString *)oldPrefix {
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:LOC(@"EDIT_RULE_TITLE") message:LOC(@"EDIT_RULE_MESSAGE") preferredStyle:UIAlertControllerStyleAlert];
	[alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
		field.keyboardType = UIKeyboardTypePhonePad;
		field.text = oldPrefix;
	}];
	[alert addAction:[UIAlertAction actionWithTitle:LOC(@"CANCEL") style:UIAlertActionStyleCancel handler:nil]];
	[alert addAction:[UIAlertAction actionWithTitle:LOC(@"SAVE") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
		[self replacePrefix:oldPrefix with:alert.textFields.firstObject.text];
	}]];
	[self presentViewController:alert animated:YES completion:nil];
}

- (void)replacePrefix:(NSString *)oldPrefix with:(NSString *)text {
	NSString *newPrefix = CGNormalizePrefix(text);
	if (!newPrefix) {
		[self showAlertWithTitle:LOC(@"INVALID_PREFIX_TITLE") message:LOC(@"INVALID_PREFIX_MESSAGE")];
		return;
	}
	if ([newPrefix isEqualToString:oldPrefix]) return;
	[self confirmIfShort:newPrefix thenSave:^{
		NSMutableArray<NSString *> *prefixes = [CGPrefPrefixes() mutableCopy];
		NSUInteger index = [prefixes indexOfObject:oldPrefix];
		if (index == NSNotFound) return;
		if ([prefixes containsObject:newPrefix]) [prefixes removeObjectAtIndex:index];   // already there: just drop the old one
		else prefixes[index] = newPrefix;
		CGPrefSet(@"Prefixes", prefixes);
		self->_specifiers = nil;
		[self reloadSpecifiers];
	}];
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
	return [[self specifierAtIndexPath:indexPath] propertyForKey:@"cgPrefix"] != nil;
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath {
	return [self tableView:tableView canEditRowAtIndexPath:indexPath] ? UITableViewCellEditingStyleDelete : UITableViewCellEditingStyleNone;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)style forRowAtIndexPath:(NSIndexPath *)indexPath {
	PSSpecifier *row = [self specifierAtIndexPath:indexPath];
	NSString *prefix = [row propertyForKey:@"cgPrefix"];
	if (style != UITableViewCellEditingStyleDelete || !prefix) return;
	NSMutableArray *current = [CGPrefPrefixes() mutableCopy];
	[current removeObject:prefix];
	CGPrefSet(@"Prefixes", current);
	[self removeSpecifier:row animated:YES];
}

#pragma mark - Troubleshooting

- (void)openURLString:(NSString *)string {
	[[UIApplication sharedApplication] openURL:[NSURL URLWithString:string] options:@{} completionHandler:nil];
}

- (void)openTwitter {
	[self openURLString:@"https://x.com/t70438299"];
}

- (void)openSourceCode {
	[self openURLString:@"https://github.com/qnblackcat/CallGuard"];
}

- (NSString *)tweakVersion:(PSSpecifier *)specifier {
	return @CG_VERSION;
}

- (void)showAlertWithTitle:(NSString *)title message:(NSString *)message {
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
	[self presentViewController:alert animated:YES completion:nil];
}

// The log with a header saying what it came from, or nil (after telling the user) if there is nothing to send
- (NSString *)debugLogForSending {
	NSString *log = CGLogFileRead(CGLogCopyMaxBytes);
	if (!log.length) {
		[self showAlertWithTitle:LOC(@"LOG_EMPTY_TITLE") message:LOC(@"LOG_EMPTY_MESSAGE")];
		return nil;
	}
	struct utsname system;
	uname(&system);
	NSString *header = [NSString stringWithFormat:@"CallGuard %@ debug log, iOS %@, %s\n", @CG_VERSION, [UIDevice currentDevice].systemVersion, system.machine];
	return [header stringByAppendingString:log];
}

- (void)copyDebugLog {
	NSString *log = [self debugLogForSending];
	if (!log) return;
	[UIPasteboard generalPasteboard].string = log;
	[self showAlertWithTitle:LOC(@"COPIED_TITLE") message:[NSString stringWithFormat:LOC(@"COPIED_MESSAGE"), (unsigned long)(log.length / 1024 + 1)]];
}

- (void)shareDebugLog {
	NSString *log = [self debugLogForSending];
	if (!log) return;
	NSURL *url = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:@"CallGuard-debug-log.txt"]];
	if (![log writeToURL:url atomically:YES encoding:NSUTF8StringEncoding error:NULL]) {
		[self showAlertWithTitle:LOC(@"LOG_FILE_ERROR") message:nil];
		return;
	}
	UIActivityViewController *sheet = [[UIActivityViewController alloc] initWithActivityItems:@[url] applicationActivities:nil];
	sheet.popoverPresentationController.sourceView = self.view;
	[self presentViewController:sheet animated:YES completion:nil];
}

- (void)clearDebugLog {
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:LOC(@"CLEAR_LOG_TITLE") message:nil preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:LOC(@"CANCEL") style:UIAlertActionStyleCancel handler:nil]];
	[alert addAction:[UIAlertAction actionWithTitle:LOC(@"DELETE") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
		CGLogFileClear();
	}]];
	[self presentViewController:alert animated:YES completion:nil];
}

@end
