import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A compact 24-hour picker with scroll wheels and direct numeric entry.
Future<int?> showTimeWheelPicker(
  BuildContext context, {
  required int initialMinute,
  String title = 'Choose time',
}) =>
    showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _TimeWheelSheet(
        initialMinute: initialMinute,
        title: title,
      ),
    );

class _TimeWheelSheet extends StatefulWidget {
  const _TimeWheelSheet({
    required this.initialMinute,
    required this.title,
  });

  final int initialMinute;
  final String title;

  @override
  State<_TimeWheelSheet> createState() => _TimeWheelSheetState();
}

class _TimeWheelSheetState extends State<_TimeWheelSheet> {
  late int _hour;
  late int _minute;
  late final TextEditingController _hourText;
  late final TextEditingController _minuteText;
  late final FixedExtentScrollController _hourWheel;
  late final FixedExtentScrollController _minuteWheel;

  @override
  void initState() {
    super.initState();
    _hour = (widget.initialMinute ~/ 60).clamp(0, 23) as int;
    _minute = (widget.initialMinute % 60).clamp(0, 59) as int;
    _hourText = TextEditingController(text: _hour.toString().padLeft(2, '0'));
    _minuteText = TextEditingController(
      text: _minute.toString().padLeft(2, '0'),
    );
    _hourWheel = FixedExtentScrollController(initialItem: _hour);
    _minuteWheel = FixedExtentScrollController(initialItem: _minute);
  }

  @override
  void dispose() {
    _hourText.dispose();
    _minuteText.dispose();
    _hourWheel.dispose();
    _minuteWheel.dispose();
    super.dispose();
  }

  void _setHour(int value, {bool updateText = false}) {
    final hour = value.clamp(0, 23) as int;
    setState(() => _hour = hour);
    if (updateText) {
      _hourText.value = TextEditingValue(
        text: hour.toString().padLeft(2, '0'),
        selection: TextSelection.collapsed(offset: 2),
      );
    }
  }

  void _setMinute(int value, {bool updateText = false}) {
    final minute = value.clamp(0, 59) as int;
    setState(() => _minute = minute);
    if (updateText) {
      _minuteText.value = TextEditingValue(
        text: minute.toString().padLeft(2, '0'),
        selection: TextSelection.collapsed(offset: 2),
      );
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(widget.title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _NumberInput(
                    controller: _hourText,
                    max: 23,
                    onChanged: _setHour,
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: Text(':', style: TextStyle(fontSize: 26)),
                  ),
                  _NumberInput(
                    controller: _minuteText,
                    max: 59,
                    onChanged: _setMinute,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 152,
                child: Row(
                  children: [
                    Expanded(
                      child: _Wheel(
                        controller: _hourWheel,
                        value: _hour,
                        count: 24,
                        onChanged: (value) => _setHour(value, updateText: true),
                      ),
                    ),
                    const Center(
                        child: Text(':', style: TextStyle(fontSize: 26))),
                    Expanded(
                      child: _Wheel(
                        controller: _minuteWheel,
                        value: _minute,
                        count: 60,
                        onChanged: (value) =>
                            _setMinute(value, updateText: true),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(context, _hour * 60 + _minute),
                  child: const Text('Done'),
                ),
              ),
            ],
          ),
        ),
      );
}

class _NumberInput extends StatelessWidget {
  const _NumberInput({
    required this.controller,
    required this.max,
    required this.onChanged,
  });

  final TextEditingController controller;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 66,
        child: TextField(
          controller: controller,
          textAlign: TextAlign.center,
          keyboardType: TextInputType.number,
          maxLength: 2,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(counterText: ''),
          onChanged: (text) {
            final value = int.tryParse(text);
            if (value != null) onChanged(value.clamp(0, max));
          },
          onEditingComplete: () {
            final value = (int.tryParse(controller.text) ?? 0).clamp(0, max);
            onChanged(value);
            FocusScope.of(context).unfocus();
          },
        ),
      );
}

class _Wheel extends StatelessWidget {
  const _Wheel({
    required this.controller,
    required this.value,
    required this.count,
    required this.onChanged,
  });

  final FixedExtentScrollController controller;
  final int value;
  final int count;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => ListWheelScrollView.useDelegate(
        controller: controller,
        itemExtent: 38,
        perspective: .003,
        physics: const FixedExtentScrollPhysics(),
        onSelectedItemChanged: onChanged,
        childDelegate: ListWheelChildBuilderDelegate(
          childCount: count,
          builder: (context, index) => Center(
            child: Text(
              index.toString().padLeft(2, '0'),
              style: TextStyle(
                fontSize: 20,
                color: index == value
                    ? Theme.of(context).colorScheme.primary
                    : const Color(0xFF88817A),
              ),
            ),
          ),
        ),
      );
}
