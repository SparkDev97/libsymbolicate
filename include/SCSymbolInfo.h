/**
 * Name: libsymbolicate
 * Type: iOS/OS X shared library
 * Desc: Library for parsing and symbolicating iOS crash log files.
 *
 * Author: Lance Fetters (aka. ashikase)
 * License: GPL v3 (See LICENSE file for details)
 */

@interface SCSymbolInfo : NSObject
@property(nonatomic, copy) NSString *name;
@property(nonatomic) uint64_t offset;
@property(nonatomic, copy) NSString *sourcePath;
@property(nonatomic) NSUInteger sourceLineNumber;
@end

/* vim: set ft=objcpp ff=unix sw=4 ts=4 tw=80 expandtab: */