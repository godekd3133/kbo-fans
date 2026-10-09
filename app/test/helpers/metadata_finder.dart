import 'package:flutter_test/flutter_test.dart';
import 'package:kbo_fans/core/widgets/app_metadata_text.dart';

/// Locate content whose fields now render separately, retaining exact data
/// identity checks without requiring punctuation in the visible UI.
Finder metadataText(String data) {
  if (metadataItems(data).length < 2) return find.text(data);
  return find.byWidgetPredicate(
    (widget) => widget is AppMetadataText && widget.data == data,
    description: 'metadata with exact content $data',
  );
}
