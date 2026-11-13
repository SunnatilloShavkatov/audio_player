// Objective-C view of `AudioPlayerApi` (AudioPlayerApi.swift), read by `dart run tool/ffigen.dart` and by the
// generated wrapper audio_player_darwin.m. It is private (not in include/), so it never clashes with the Swift
// class. Keep it identical to the Swift @objc API: selectors, parameter types and block signatures are matched at
// runtime, and a mismatch crashes.
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface AudioPlayerApi : NSObject

+ (void)setPlaybackListenersWithPlaybackEvent:(nullable void (^)(NSString *playerId, NSString *json))playbackEvent
                                   playerData:(nullable void (^)(NSString *playerId, NSString *json))playerData
                                playbackError:(nullable void (^)(NSString *playerId, NSString *code, NSString *_Nullable message, NSString *_Nullable details))playbackError;

+ (void)callMain:(NSString *)method request:(NSString *)request callback:(void (^)(NSString *_Nullable json, NSString *_Nullable code, NSString *_Nullable message, NSString *_Nullable details))callback;
+ (void)callPlayer:(NSString *)playerId method:(NSString *)method request:(NSString *)request callback:(void (^)(NSString *_Nullable json, NSString *_Nullable code, NSString *_Nullable message, NSString *_Nullable details))callback;

@end

NS_ASSUME_NONNULL_END
