//
//  iTermGraphEncoder.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 7/26/20.
//

#import "iTermGraphEncoder.h"

#import "DebugLogging.h"
#import "NSArray+iTerm.h"
#import "NSDictionary+iTerm.h"
#import "NSObject+iTerm.h"
#import "iTermTuple.h"

NSInteger iTermGenerationAlwaysEncode = NSIntegerMax;

@implementation iTermGraphEncoder {
    NSMutableDictionary<NSString *, iTermEncoderPODRecord *> *_pod;
    NSString *_identifier;
    NSInteger _generation;
    NSString *_key;
    NSMutableArray<iTermEncoderGraphRecord *> *_children;
    iTermEncoderGraphRecord *_record;
}

- (instancetype)initWithKey:(NSString *)key
                 identifier:(NSString *)identifier
                 generation:(NSInteger)generation {
    assert(identifier);
    self = [super init];
    if (self) {
        _key = key;
        _identifier = identifier;
        _generation = generation;
        _pod = [NSMutableDictionary dictionary];
        _children = [NSMutableArray array];
        _state = iTermGraphEncoderStateLive;
    }
    return self;
}

- (void)encodeString:(NSString *)string forKey:(NSString *)key {
    assert(_state == iTermGraphEncoderStateLive);
    _pod[key] = [iTermEncoderPODRecord withString:string key:key];
}

- (void)encodeNumber:(NSNumber *)number forKey:(NSString *)key {
    assert(_state == iTermGraphEncoderStateLive);
    _pod[key] = [iTermEncoderPODRecord withNumber:number key:key];
}

- (void)encodeData:(NSData *)data forKey:(NSString *)key {
    assert(_state == iTermGraphEncoderStateLive);
    _pod[key] = [iTermEncoderPODRecord withData:data key:key];
}

- (void)encodeDate:(NSDate *)date forKey:(NSString *)key {
    assert(_state == iTermGraphEncoderStateLive);
    _pod[key] = [iTermEncoderPODRecord withDate:date key:key];
}

- (void)encodeNullForKey:(NSString *)key {
    assert(_state == iTermGraphEncoderStateLive);
    _pod[key] = [iTermEncoderPODRecord withNullForKey:key];
}

- (BOOL)encodeObject:(id)obj key:(NSString *)key {
    if ([obj conformsToProtocol:@protocol(iTermGraphEncodable)] &&
        [(id<iTermGraphEncodable>)obj graphEncoderShouldIgnore]) {
        return NO;
    }
    if ([obj isKindOfClass:[NSString class]]) {
        [self encodeString:obj forKey:key];
        return YES;
    }
    if ([obj isKindOfClass:[NSData class]]) {
        [self encodeData:obj forKey:key];
        return YES;
    }
    if ([obj isKindOfClass:[NSDate class]]) {
        [self encodeData:obj forKey:key];
        return YES;
    }
    if ([obj isKindOfClass:[NSNumber class]]) {
        [self encodeNumber:obj forKey:key];
        return YES;
    }
    if ([obj isKindOfClass:[NSNull class]]) {
        [self encodeNullForKey:key];
        return YES;
    }
    if ([obj isKindOfClass:[NSArray class]]) {
        NSArray *array = obj;
        [self encodeArrayWithKey:key
                      generation:_generation
                     identifiers:[NSArray stringSequenceWithRange:NSMakeRange(0, array.count)]
                         options:0
                           block:^BOOL (NSString * _Nonnull identifier,
                                   NSInteger index,
                                   iTermGraphEncoder * _Nonnull subencoder) {
            [subencoder encodeObject:array[index] key:identifier];
            return YES;
        }];
        return YES;
    }
    if ([obj isKindOfClass:[NSDictionary class]]) {
        NSDictionary *dict = obj;
        [self encodeDictionary:dict withKey:key generation:_generation];
        return YES;
    }
    assert(NO);
}

- (void)encodeDictionary:(NSDictionary *)dict
                 withKey:(NSString *)key
              generation:(NSInteger)generation {
    [self encodeChildWithKey:@"__dict"
                  identifier:key
                  generation:generation
                       block:^BOOL(iTermGraphEncoder * _Nonnull subencoder) {
        [dict enumerateKeysAndObjectsUsingBlock:^(NSString * _Nonnull key, id  _Nonnull obj, BOOL * _Nonnull stop) {
            [subencoder encodeObject:obj key:key];
        }];
        return YES;
    }];
}

- (void)encodeGraph:(iTermEncoderGraphRecord *)record {
    assert(_state == iTermGraphEncoderStateLive);
    [_children addObject:record];
}

- (BOOL)encodeChildWithKey:(NSString *)key
                identifier:(NSString *)identifier
                generation:(NSInteger)generation
                     block:(BOOL (^ NS_NOESCAPE)(iTermGraphEncoder *subencoder))block {
    assert(_state == iTermGraphEncoderStateLive);
    iTermGraphEncoder *encoder = [[iTermGraphEncoder alloc] initWithKey:key
                                                             identifier:identifier
                                                             generation:generation];
    if (!block(encoder)) {
        return NO;
    }
    [self encodeGraph:encoder.record];
    return YES;
}

- (void)encodeArrayWithKey:(NSString *)key
                generation:(NSInteger)generation
               identifiers:(NSArray<NSString *> *)identifiers
                   options:(iTermGraphEncoderArrayOptions)options
                     block:(BOOL (^ NS_NOESCAPE)(NSString *identifier,
                                                 NSInteger index,
                                                 iTermGraphEncoder *subencoder))block {
    [self encodeChildWithKey:@"__array"
                  identifier:key
                  generation:generation
                       block:^BOOL(iTermGraphEncoder * _Nonnull subencoder) {
        [identifiers enumerateObjectsUsingBlock:^(NSString * _Nonnull identifier,
                                                  NSUInteger idx,
                                                  BOOL * _Nonnull stop) {
            [subencoder transaction:^BOOL {
                return [subencoder encodeChildWithKey:@"" identifier:identifier generation:iTermGenerationAlwaysEncode block:^BOOL(iTermGraphEncoder * _Nonnull subencoder) {
                    return block(identifier, idx, subencoder);
                }];
            }];
        }];
        NSArray<NSString *> *orderedIdentifiers = identifiers;
        if (options & iTermGraphEncoderArrayOptionsReverse) {
            orderedIdentifiers = orderedIdentifiers.reversed;
        }
        [subencoder encodeString:[orderedIdentifiers componentsJoinedByString:@"\t"] forKey:@"__order"];
        return YES;
    }];
}

- (iTermEncoderGraphRecord *)record {
    switch (_state) {
        case iTermGraphEncoderStateLive:
            _record = [iTermEncoderGraphRecord withPODs:_pod.allValues
                                                 graphs:_children
                                             generation:_generation
                                                    key:_key
                                             identifier:_identifier
                                                  rowid:nil];
            _state = iTermGraphEncoderStateCommitted;
            return _record;

        case iTermGraphEncoderStateCommitted:
            return _record;

        case iTermGraphEncoderStateRolledBack:
            return nil;
    }
}

- (void)rollback {
    assert(_state == iTermGraphEncoderStateLive);
    [_pod removeAllObjects];
    [_children removeAllObjects];
    _state = iTermGraphEncoderStateRolledBack;
}

- (void)transaction:(BOOL (^)(void))block {
    NSMutableDictionary<NSString *, iTermEncoderPODRecord *> *savedPOD = [_pod mutableCopy];
    NSMutableArray<iTermEncoderGraphRecord *> *savedChildren = [_children mutableCopy];
    const BOOL commit = block();
    if (commit) {
        return;
    }
    _pod = savedPOD;
    _children = savedChildren;
}

@end