import 'package:flutter/material.dart';
import '../../../core/models/video.dart';

class CreateShortBottomSheet extends StatefulWidget {
  final Video video;

  const CreateShortBottomSheet({super.key, required this.video});

  @override
  State<CreateShortBottomSheet> createState() => _CreateShortBottomSheetState();
}

class _CreateShortBottomSheetState extends State<CreateShortBottomSheet> {
  final _titleController = TextEditingController();
  double _startSeconds = 0;
  double _endSeconds = 60;

  @override
  void initState() {
    super.initState();
    _titleController.text = 'Clip: ${widget.video.title}';
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Create Christian Short / Clip',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _titleController,
            decoration: const InputDecoration(
              labelText: 'Short Title',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          Text('Segment: ${_startSeconds.toInt()}s to ${_endSeconds.toInt()}s'),
          RangeSlider(
            values: RangeValues(_startSeconds, _endSeconds),
            min: 0,
            max: 180,
            divisions: 18,
            labels: RangeLabels('${_startSeconds.toInt()}s', '${_endSeconds.toInt()}s'),
            onChanged: (values) {
              setState(() {
                _startSeconds = values.start;
                _endSeconds = values.end;
              });
            },
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Short clip created successfully!')),
                );
              },
              icon: const Icon(Icons.cut),
              label: const Text('Save & Publish Clip'),
            ),
          ),
        ],
      ),
    );
  }
}
