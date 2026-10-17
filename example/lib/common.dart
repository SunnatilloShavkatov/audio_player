import 'dart:async';

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:rxdart/rxdart.dart';

class SeekBar extends StatefulWidget {
  const new({
    super.key,
    required this.duration,
    required this.position,
    required this.bufferedPosition,
    this.onChanged,
    this.onChangeEnd,
  });

  final Duration duration;
  final Duration position;
  final Duration bufferedPosition;
  final ValueChanged<Duration>? onChanged;
  final ValueChanged<Duration>? onChangeEnd;

  @override
  SeekBarState createState() => SeekBarState();
}

class SeekBarState extends State<SeekBar> {
  double? _dragValue;
  late SliderThemeData _sliderThemeData;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    _sliderThemeData = SliderTheme.of(context).copyWith(trackHeight: 2);
  }

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      SliderTheme(
        data: _sliderThemeData.copyWith(
          thumbShape: HiddenThumbComponentShape(),
          activeTrackColor: Colors.blue.shade100,
          inactiveTrackColor: Colors.grey.shade300,
        ),
        child: ExcludeSemantics(
          child: Slider(
            max: widget.duration.inMilliseconds.toDouble(),
            value: min(widget.bufferedPosition.inMilliseconds.toDouble(), widget.duration.inMilliseconds.toDouble()),
            onChanged: (value) {
              setState(() {
                _dragValue = value;
              });
              widget.onChanged?.call(Duration(milliseconds: value.round()));
            },
            onChangeEnd: (value) {
              widget.onChangeEnd?.call(Duration(milliseconds: value.round()));
              _dragValue = null;
            },
          ),
        ),
      ),
      SliderTheme(
        data: _sliderThemeData.copyWith(inactiveTrackColor: Colors.transparent),
        child: Slider(
          max: widget.duration.inMilliseconds.toDouble(),
          value: min(
            _dragValue ?? widget.position.inMilliseconds.toDouble(),
            widget.duration.inMilliseconds.toDouble(),
          ),
          onChanged: (value) {
            setState(() {
              _dragValue = value;
            });
            widget.onChanged?.call(Duration(milliseconds: value.round()));
          },
          onChangeEnd: (value) {
            widget.onChangeEnd?.call(Duration(milliseconds: value.round()));
            _dragValue = null;
          },
        ),
      ),
      Positioned(
        right: 16,
        bottom: 0,
        child: Text(
          RegExp(r'((^0*[1-9]\d*:)?\d{2}:\d{2})\.\d+$').firstMatch('$_remaining')?.group(1) ?? '$_remaining',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
    ],
  );

  Duration get _remaining => widget.duration - widget.position;
}

class HiddenThumbComponentShape extends SliderComponentShape {
  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) => Size.zero;

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {}
}

class PositionData {
  new(this.position, this.bufferedPosition, this.duration);

  final Duration position;
  final Duration bufferedPosition;
  final Duration duration;
}

void showSliderDialog({
  required BuildContext context,
  required String title,
  required int divisions,
  required double min,
  required double max,
  String valueSuffix = '',
  required ValueStream<double> stream,
  required ValueChanged<double> onChanged,
}) {
  unawaited(
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title, textAlign: TextAlign.center),
        content: StreamBuilder<double>(
          stream: stream,
          initialData: stream.valueOrNull,
          builder: (context, snapshot) => SizedBox(
            height: 100,
            child: Column(
              children: [
                Text(
                  '${snapshot.data?.toStringAsFixed(1)}$valueSuffix',
                  style: const TextStyle(fontFamily: 'Fixed', fontWeight: FontWeight.bold, fontSize: 24),
                ),
                Slider(divisions: divisions, min: min, max: max, value: snapshot.data ?? min, onChanged: onChanged),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

T? ambiguate<T>(T? value) => value;
