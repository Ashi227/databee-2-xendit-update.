import 'package:databee/app/app_config.dart';
import 'package:databee/app/databee_app.dart';
import 'package:databee/models/product.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('Supabase is configured for the default app launch', () {
    expect(AppConfig.isConfigured, isTrue);
  });

  test('formats PHP prices with grouped thousands', () {
    expect(formatPhp(59999), '₱59,999.00');
    expect(formatPhp(12.5), '₱12.50');
  });

  testWidgets('demo mode opens a browsable DataBee catalog', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const DataBeeApp(backendConfigured: false));
    await tester.pumpAndSettle();

    expect(find.text('DataBee'), findsOneWidget);
    expect(find.text('Components'), findsOneWidget);
    expect(find.text('GeForce RTX 4080 SUPER 16GB'), findsOneWidget);
    expect(find.text('DEMO'), findsOneWidget);
  });
}
