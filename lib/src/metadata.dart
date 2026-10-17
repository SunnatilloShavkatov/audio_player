part of 'audio_player.dart';

@immutable
class IcyInfo {
  const new({required this.title, required this.url});

  factory _fromMessage(IcyInfoMessage message) => IcyInfo(title: message.title, url: message.url);

  final String? title;
  final String? url;

  @override
  String toString() => 'title=$title,url=$url';

  @override
  int get hashCode => Object.hash(title, url);

  @override
  bool operator ==(Object other) =>
      other.runtimeType == runtimeType && other is IcyInfo && other.title == title && other.url == url;
}

@immutable
class IcyHeaders {
  const new({
    required this.bitrate,
    required this.genre,
    required this.name,
    required this.metadataInterval,
    required this.url,
    required this.isPublic,
  });

  factory _fromMessage(IcyHeadersMessage message) => IcyHeaders(
    bitrate: message.bitrate,
    genre: message.genre,
    name: message.name,
    metadataInterval: message.metadataInterval,
    url: message.url,
    isPublic: message.isPublic,
  );

  final int? bitrate;
  final String? genre;
  final String? name;
  final int? metadataInterval;
  final String? url;
  final bool? isPublic;

  @override
  String toString() =>
      'bitrate=$bitrate,genre=$genre,name=$name,metadataInterval=$metadataInterval,url=$url,isPublic=$isPublic';

  @override
  int get hashCode => toString().hashCode;

  @override
  bool operator ==(Object other) =>
      other.runtimeType == runtimeType &&
      other is IcyHeaders &&
      other.bitrate == bitrate &&
      other.genre == genre &&
      other.name == name &&
      other.metadataInterval == metadataInterval &&
      other.url == url &&
      other.isPublic == isPublic;
}

@immutable
class IcyMetadata {
  const new({required this.info, required this.headers});

  factory _fromMessage(IcyMetadataMessage message) => IcyMetadata(
    info: message.info == null ? null : IcyInfo._fromMessage(message.info!),
    headers: message.headers == null ? null : IcyHeaders._fromMessage(message.headers!),
  );

  final IcyInfo? info;
  final IcyHeaders? headers;

  @override
  int get hashCode => Object.hash(info, headers);

  @override
  bool operator ==(Object other) =>
      other.runtimeType == runtimeType && other is IcyMetadata && other.info == info && other.headers == headers;
}
