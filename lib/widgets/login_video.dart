import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// Looping, muted background footage with the poster as a fallback.
class LoginVideo extends StatefulWidget {
  const LoginVideo({super.key});
  @override
  State<LoginVideo> createState() => _LoginVideoState();
}

class _LoginVideoState extends State<LoginVideo> {
  VideoPlayerController? _v;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    final v = VideoPlayerController.asset('assets/images/login-bg.mp4', videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true));
    _v = v;
    v.initialize().then((_) {
      v
        ..setLooping(true)
        ..setVolume(0)
        ..play();
      if (mounted) setState(() => _ready = true);
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _v?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final v = _v;
    return Stack(fit: StackFit.expand, children: [
      Image.asset('assets/images/login-poster.jpg', fit: BoxFit.cover),
      if (_ready && v != null)
        FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(width: v.value.size.width, height: v.value.size.height, child: VideoPlayer(v)),
        ),
    ]);
  }
}
