import 'package:dr/assessment_attachments.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('attachment metadata round-trips without retaining source paths', () {
    const attachment = AssessmentAttachment(
      name: 'stoff.md',
      path: '/private/app/assessment_attachments/1_stoff.md',
    );

    final decoded = decodeAssessmentAttachments(
      encodeAssessmentAttachments([attachment]),
    );

    expect(decoded, hasLength(1));
    expect(decoded.single.name, 'stoff.md');
    expect(decoded.single.path, attachment.path);
  });

  test('malformed persisted attachment metadata is ignored', () {
    expect(decodeAssessmentAttachments('{not json}'), isEmpty);
  });
}
