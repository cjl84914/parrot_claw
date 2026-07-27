// import 'package:flutter/cupertino.dart';
// import 'package:video_player/video_player.dart';
//
// class VideoMessageWidget extends StatefulWidget {
//   final String url;
//
//   const VideoMessageWidget({super.key, required this.url});
//
//   @override
//   State<VideoMessageWidget> createState() => _VideoMessageState();
// }
//
// class _VideoMessageState extends State<VideoMessageWidget> {
//   late VideoPlayerController _controller;
//
//   @override
//   void initState() {
//     super.initState();
//     _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url))
//       ..initialize().then((_) {
//         setState(() {});
//       });
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     return _controller.value.isInitialized
//         ? AspectRatio(
//           aspectRatio: _controller.value.aspectRatio,
//           child: VideoPlayer(_controller),
//         )
//         : Container();
//   }
//
//   @override
//   void dispose() {
//     _controller.dispose();
//     super.dispose();
//   }
// }
