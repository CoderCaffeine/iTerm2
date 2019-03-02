//
//  iTermFunctionCallParser.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/20/18.
//

#import <Foundation/Foundation.h>
#import <CoreParse/CoreParse.h>
#import "iTermParsedExpression.h"

@interface iTermFunctionCallParser : NSObject <CPParserDelegate, CPTokeniserDelegate>

// Use this to get an instance. Only on the main thread.
// Parses strings like: foo(x:y)
+ (instancetype)callParser;

// Parses expressions, like:
// 1
// "foo \(bar)"
// [1, 2]
+ (instancetype)expressionParser;

- (instancetype)init NS_UNAVAILABLE;

- (iTermParsedExpression *)parse:(NSString *)invocation scope:(iTermVariableScope *)scope;

+ (iTermParsedExpression *)parsedExpressionWithInterpolatedString:(NSString *)swifty
                                                            scope:(iTermVariableScope *)scope;

+ (NSString *)signatureForTopLevelInvocation:(NSString *)invocation;

@end

