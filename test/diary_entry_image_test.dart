import 'package:flutter_test/flutter_test.dart';
import 'package:health_pro/domain/entities/food.dart';

/// docs/21 §6 / D-83: the server sends a diary entry's photo as a path relative to itself; the app
/// resolves it once, where the base URL lives, and leaves an absolute URL or a missing photo alone.
void main() {
  test('should resolve an entry photo path against the API base URL', () {
    final day = DiaryDay.fromJson(const {
      'diary_date': '2026-09-19',
      'entries': [
        {
          'id': '1',
          'slot': 'breakfast',
          'name': 'Aloo gobhi',
          'quantity_g': 150,
          'kcal': 161,
          'image_url': '/food-images/aloo-gobhi.jpg',
          'image_attribution': 'A. Cook / CC BY-SA 4.0',
        },
        {'id': '2', 'slot': 'lunch', 'name': 'Aunty ka halwa', 'quantity_g': 100, 'kcal': 392},
      ],
    }, imageBase: 'http://api.test/api/v1/');

    expect(day.entries[0].imageUrl, 'http://api.test/api/v1/food-images/aloo-gobhi.jpg');
    expect(day.entries[0].imageAttribution, 'A. Cook / CC BY-SA 4.0');
    expect(day.entries[1].imageUrl, isNull);
  });

  test('should leave an absolute URL, or a path with no base, as it is', () {
    expect(resolveImageUrl('https://cdn.test/a.jpg', 'http://api.test'), 'https://cdn.test/a.jpg');
    expect(resolveImageUrl('/food-images/a.jpg', null), '/food-images/a.jpg');
    expect(resolveImageUrl(null, 'http://api.test'), isNull);
  });
}
