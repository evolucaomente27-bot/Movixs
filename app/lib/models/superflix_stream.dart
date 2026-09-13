class SuperFlixStreamResult {
  final String url;
  final String audioType; // 'Dublado' ou 'Legendado'
  final bool isDirectStream; // true = arquivo de mídia (.m3u8/.mp4), false = player embutido (embed)
  final Map<String, String> headers; // Referer, Origin, User-Agent, etc.
  final String serverName;
  final String quality;
  final String format; // 'hls', 'mp4', 'embed'

  SuperFlixStreamResult({
    required this.url,
    required this.audioType,
    required this.isDirectStream,
    this.headers = const {},
    String? serverName,
    this.quality = '1080p Ultra HD',
    String? format,
  })  : serverName = serverName ??
            (isDirectStream
                ? 'SuperFlix Stream ($audioType)'
                : 'SuperFlix Player Embed ($audioType)'),
        format = format ??
            (url.toLowerCase().contains('.m3u8')
                ? 'hls'
                : (url.toLowerCase().contains('.mp4') ? 'mp4' : 'embed'));

  bool get isDublado => audioType.toLowerCase().contains('dublado');
  bool get isLegendado => audioType.toLowerCase().contains('legendado');
  bool get isHls => format == 'hls' || url.toLowerCase().contains('.m3u8');
  bool get isMp4 => format == 'mp4' || url.toLowerCase().contains('.mp4');

  SuperFlixStreamResult copyWith({
    String? url,
    String? audioType,
    bool? isDirectStream,
    Map<String, String>? headers,
    String? serverName,
    String? quality,
    String? format,
  }) {
    return SuperFlixStreamResult(
      url: url ?? this.url,
      audioType: audioType ?? this.audioType,
      isDirectStream: isDirectStream ?? this.isDirectStream,
      headers: headers ?? this.headers,
      serverName: serverName ?? this.serverName,
      quality: quality ?? this.quality,
      format: format ?? this.format,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'url': url,
      'audioType': audioType,
      'isDirectStream': isDirectStream,
      'headers': headers,
      'serverName': serverName,
      'quality': quality,
      'format': format,
    };
  }

  factory SuperFlixStreamResult.fromJson(Map<String, dynamic> json) {
    return SuperFlixStreamResult(
      url: json['url'] ?? '',
      audioType: json['audioType'] ?? 'Dublado',
      isDirectStream: json['isDirectStream'] ?? false,
      headers: json['headers'] != null
          ? Map<String, String>.from(json['headers'])
          : {},
      serverName: json['serverName'],
      quality: json['quality'] ?? '1080p Ultra HD',
      format: json['format'],
    );
  }

  @override
  String toString() {
    return 'SuperFlixStreamResult(server: $serverName, audio: $audioType, direct: $isDirectStream, url: $url)';
  }
}
