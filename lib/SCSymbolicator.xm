/**
 * Name: libsymbolicate
 * Type: iOS/OS X shared library
 * Desc: Library for symbolicating memory addresses.
 *
 * Author: Lance Fetters (aka. ashikase)
 * License: LGPL v3 (See LICENSE file for details)
 */

#import "SCSymbolicator.h"

#import "SCBinaryInfo.h"
#import "SCMethodInfo.h"
#import "SCSymbolInfo.h"

#include <objc/runtime.h>
#include <string.h>
#include "demangle.h"
#include "sharedCache.h"

@implementation SCSymbolicator

@synthesize architecture = architecture_;
@synthesize symbolMaps = symbolMaps_;
@synthesize systemRoot = systemRoot_;

+ (instancetype)sharedInstance {
    static dispatch_once_t once;
    static id instance;
    dispatch_once(&once, ^{
        instance = [self new];
    });
    return instance;
}

- (void)dealloc {
    [architecture_ release];
    [symbolMaps_ release];
    [systemRoot_ release];
    [super dealloc];
}

- (NSString *)architecture {
    return architecture_ ?: @"armv7";
}

- (NSString *)systemRoot {
    return systemRoot_ ?: @"/";
}

- (NSString *)sharedCachePath {
    NSString *sharedCachePath = @"/System/Library/Caches/com.apple.dyld/dyld_shared_cache_";

    // Prepend the system root.
    sharedCachePath = [[self systemRoot] stringByAppendingPathComponent:sharedCachePath];

    // Add the architecture and return.
    return [sharedCachePath stringByAppendingString:[self architecture]];
}

CFComparisonResult reverseCompareUnsignedLongLong(CFNumberRef a, CFNumberRef b) {
    unsigned long long aValue;
    unsigned long long bValue;
    CFNumberGetValue(a, kCFNumberLongLongType, &aValue);
    CFNumberGetValue(b, kCFNumberLongLongType, &bValue);
    if (bValue < aValue) return kCFCompareLessThan;
    if (bValue > aValue) return kCFCompareGreaterThan;
    return kCFCompareEqualTo;
}

- (SCSymbolInfo *)symbolInfoForAddress:(uint64_t)address inBinary:(SCBinaryInfo *)binaryInfo {

    SCSymbolInfo *symbolInfo = nil;

    if (binaryInfo != nil) {
        address += [binaryInfo slide];
        symbolInfo = [binaryInfo sourceInfoForAddress:address];
        if (symbolInfo == nil) {
            // Determine symbol address.
            // NOTE: Only possible if LC_FUNCTION_STARTS exists in the binary.
            uint64_t symbolAddress = 0;
            NSArray *symbolAddresses = [binaryInfo symbolAddresses];
            NSUInteger count = [symbolAddresses count];
            if (count != 0) {
                NSNumber *targetAddress = [[NSNumber alloc] initWithUnsignedLongLong:address];
                CFIndex matchIndex = CFArrayBSearchValues((CFArrayRef)symbolAddresses, CFRangeMake(0, count), targetAddress, (CFComparatorFunction)reverseCompareUnsignedLongLong, NULL);
                [targetAddress release];
                if (matchIndex < (CFIndex)count) {
                    symbolAddress = [[symbolAddresses objectAtIndex:matchIndex] unsignedLongLongValue];
                }
            }

            // Attempt to retrieve symbol name and hex offset.
            // NOTE: (symbolAddress & ~1) is to account for Thumb.
            NSString *name = nil;
            uint64_t offset = 0;
            symbolInfo = [binaryInfo symbolInfoForAddress:address];
            if (symbolInfo != nil && ([symbolInfo addressRange].location == (symbolAddress & ~1) || symbolAddress == 0)) {
                name = [symbolInfo name];
                if ([name isEqualToString:@"<redacted>"]) {
                    NSString *sharedCachePath = [self sharedCachePath];
                    if (sharedCachePath != nil) {
                        // NOTE: In the past, the dylib offset was retrieved via
                        //       -[VMUMachOHeader address]. For some unknown
                        //       reason, the value retrieved using our own
                        //       function always differs by 0x200000.
                        // TODO: Determine the reason for this difference.
                        const char *cachePath = [sharedCachePath UTF8String];
                        uint64_t dylibOffset = offsetOfDylibInSharedCache(cachePath, [[binaryInfo path] UTF8String]);
                        const char *localName = nameForLocalSymbol(cachePath, dylibOffset, [symbolInfo addressRange].location);
                        if ((localName != NULL) && (strlen(localName) > 0)) {
                            name = [NSString stringWithCString:localName encoding:NSASCIIStringEncoding];
                        } else {
                            fprintf(stderr, "Unable to determine name for: %s, 0x%08llx\n", [[binaryInfo path] UTF8String], [symbolInfo addressRange].location);
                        }
                    }
                }
                // Attempt to demangle name
                // NOTE: It seems that Apple's demangler fails for some
                //       names, so we attempt to do it ourselves.
                [symbolInfo setName:demangle(name)];
                [symbolInfo setOffset:(address - [symbolInfo addressRange].location)];
            } else {
                NSDictionary *symbolMap = [[self symbolMaps] objectForKey:[binaryInfo path]];
                if (symbolMap != nil) {
                    for (NSNumber *number in [[[symbolMap allKeys] sortedArrayUsingSelector:@selector(compare:)] reverseObjectEnumerator]) {
                        uint64_t mapSymbolAddress = [number unsignedLongLongValue];
                        if (address > mapSymbolAddress) {
                            name = demangle([symbolMap objectForKey:number]);
                            offset = address - mapSymbolAddress;
                            break;
                        }
                    }
                } else if (![binaryInfo isEncrypted]) {
                    // Determine methods, attempt to match with symbol address.
                    if (symbolAddress != 0) {
                        SCMethodInfo *method = nil;
                        NSArray *methods = [binaryInfo methods];
                        count = [methods count];
                        if (count != 0) {
                            SCMethodInfo *targetMethod = [SCMethodInfo new];
                            [targetMethod setAddress:address];
                            CFIndex matchIndex = CFArrayBSearchValues((CFArrayRef)methods, CFRangeMake(0, count), targetMethod, (CFComparatorFunction)reversedCompareMethodInfos, NULL);
                            [targetMethod release];

                            if (matchIndex < (CFIndex)count) {
                                method = [methods objectAtIndex:matchIndex];
                            }
                        }

                        if (method != nil && [method address] >= symbolAddress) {
                            name = [method name];
                            offset = address - [method address];
                        } else {
                            uint64_t textStart = [binaryInfo baseAddress];
                            name = [NSString stringWithFormat:@"0x%08llx", (symbolAddress - textStart)];
                            offset = address - symbolAddress;
                        }
                    }
                }

                if (name != nil) {
                    symbolInfo = [[[SCSymbolInfo alloc] init] autorelease];
                    [symbolInfo setName:name];
                    [symbolInfo setOffset:offset];
                }
            }
        }
    }

    return symbolInfo;
}

@end

/* vim: set ft=objcpp ff=unix sw=4 ts=4 tw=80 expandtab: */
