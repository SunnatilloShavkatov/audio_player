#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html
#
Pod::Spec.new do |s|
  s.name             = 'audio_player'
  s.version          = '1.1.0'
  s.summary          = 'Flutter audio player'
  s.description      = <<-DESC
A flutter plugin for playing audio.
                       DESC
  s.homepage         = 'https://github.com/SunnatilloShavkatov/audio_player'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Sunnatillo Shavkatov' => 'sunnatilloshavkatov@gmail.com' }
  s.source           = { :path => '.' }
  s.source_files = 'audio_player/Sources/audio_player/**/*.swift',
                   'audio_player/Sources/audio_player_c/audio_player_darwin.m',
                   'audio_player/Sources/audio_player_c/audio_player_api.h',
                   'audio_player/Sources/audio_player_c/include/*.h'
  s.public_header_files = 'audio_player/Sources/audio_player_c/include/*.h'
  s.ios.dependency 'Flutter'
  s.osx.dependency 'FlutterMacOS'
  s.ios.deployment_target = '15.0'
  s.osx.deployment_target = '11.0'
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'HEADER_SEARCH_PATHS' => '"$(PODS_TARGET_SRCROOT)/audio_player/Sources/audio_player_c/include"',
  }
  s.swift_version = '5.0'
end
