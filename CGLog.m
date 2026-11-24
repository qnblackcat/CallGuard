#import <Foundation/Foundation.h>
#import "CGLog.h"
#include <roothide.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>

BOOL CGDebugOn = NO;

static NSString *const CGRecordSeparator = @"\x1e";

// The first directory the process may really write to wins; the reader looks in all of them.
static NSArray<NSString *> *CGLogDirectories(void) {
	return @[
		jbroot(@"/var/mobile/Library/Caches/CallGuard"),
		jbroot(@"/var/mobile/Library/CallGuard/Logs"),
		jbroot(@"/var/tmp/CallGuard"),
		@"/var/mobile/tmp/CallGuard",
	];
}

static NSString *CGWritableDirectory(void) {
	static NSString *directory;
	static BOOL failed;
	if (directory || failed) return directory;
	for (NSString *candidate in CGLogDirectories()) {
		if (![[NSFileManager defaultManager] createDirectoryAtPath:candidate withIntermediateDirectories:YES attributes:nil error:NULL]) continue;
		// access() can say yes where the sandbox still refuses open(): try a real file
		NSString *probe = [candidate stringByAppendingPathComponent:@".probe"];
		int fd = open(probe.fileSystemRepresentation, O_WRONLY | O_CREAT, 0644);
		if (fd < 0) continue;
		close(fd);
		unlink(probe.fileSystemRepresentation);
		directory = candidate;
		return directory;
	}
	failed = YES;
	NSLog(@"[CallGuard] no writable log directory, debug log file disabled");
	return nil;
}

static void CGLogFileAppend(NSString *text) {
	static dispatch_queue_t queue;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		queue = dispatch_queue_create("com.qn.callguard.log", DISPATCH_QUEUE_SERIAL);
	});
	long long millis = (long long)([[NSDate date] timeIntervalSince1970] * 1000);
	NSString *process = [[NSProcessInfo processInfo] processName];
	NSString *record = [NSString stringWithFormat:@"%@%lld %@ %@\n", CGRecordSeparator, millis, process, text];
	dispatch_async(queue, ^{
		NSString *directory = CGWritableDirectory();
		if (!directory) return;
		NSString *path = [directory stringByAppendingPathComponent:[process stringByAppendingString:@".log"]];
		struct stat st;
		if (stat(path.fileSystemRepresentation, &st) == 0 && st.st_size >= CGLogFileMaxBytes) {
			rename(path.fileSystemRepresentation, [path stringByAppendingString:@".1"].fileSystemRepresentation);
		}
		int fd = open(path.fileSystemRepresentation, O_WRONLY | O_APPEND | O_CREAT, 0644);
		if (fd < 0) return;
		NSData *data = [record dataUsingEncoding:NSUTF8StringEncoding];
		write(fd, data.bytes, data.length);
		close(fd);
	});
}

void CGLogWrite(NSString *format, ...) {
	va_list args;
	va_start(args, format);
	NSString *text = [[NSString alloc] initWithFormat:format arguments:args];
	va_end(args);
	NSLog(@"[CallGuard] %@", text);
	CGLogFileAppend(text);
}

static NSArray<NSString *> *CGLogPaths(void) {
	NSMutableArray *paths = [NSMutableArray array];
	for (NSString *directory in CGLogDirectories()) {
		for (NSString *name in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:directory error:NULL]) {
			if ([name hasSuffix:@".log"] || [name hasSuffix:@".log.1"]) [paths addObject:[directory stringByAppendingPathComponent:name]];
		}
	}
	return paths;
}

NSString *CGLogFileRead(NSUInteger maxBytes) {
	NSMutableArray<NSArray *> *records = [NSMutableArray array];   // [millis, line]
	for (NSString *path in CGLogPaths()) {
		NSString *content = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:NULL];
		for (NSString *record in [content componentsSeparatedByString:CGRecordSeparator]) {
			NSRange space = [record rangeOfString:@" "];
			if (space.location == NSNotFound) continue;
			long long millis = [[record substringToIndex:space.location] longLongValue];
			if (millis <= 0) continue;
			[records addObject:@[@(millis), [record substringFromIndex:NSMaxRange(space)]]];
		}
	}
	[records sortUsingComparator:^NSComparisonResult(NSArray *a, NSArray *b) {
		return [a[0] compare:b[0]];
	}];
	NSDateFormatter *formatter = [NSDateFormatter new];
	formatter.dateFormat = @"MM-dd HH:mm:ss.SSS";
	NSMutableArray<NSString *> *lines = [NSMutableArray array];
	NSUInteger total = 0;
	// newest first, so the cut at maxBytes drops the oldest records
	for (NSArray *record in [records reverseObjectEnumerator]) {
		NSString *time = [formatter stringFromDate:[NSDate dateWithTimeIntervalSince1970:[record[0] longLongValue] / 1000.0]];
		NSString *line = [NSString stringWithFormat:@"%@ %@", time, record[1]];
		if (total + line.length > maxBytes && lines.count) break;
		total += line.length;
		[lines addObject:line];
	}
	return [[[lines reverseObjectEnumerator] allObjects] componentsJoinedByString:@""];
}

void CGLogFileClear(void) {
	for (NSString *path in CGLogPaths()) [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
}
