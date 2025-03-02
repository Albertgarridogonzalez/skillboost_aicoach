// video_downloader_web.dart
import 'dart:html' as html;

Future<void> downloadVideo(String videoPath) async {
  final anchor = html.AnchorElement(href: videoPath)
    ..setAttribute("download", "video.mp4")
    ..click();
}
