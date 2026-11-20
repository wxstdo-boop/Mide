// Widget tests for the AI tab: header branding, the composer, the thinking
// caret, the error card and the topics sheet. The chat session is faked so
// nothing here touches the network or secure storage.
//
// Note: several animations in this screen loop forever (the shimmer title,
// the thinking caret, the send button's gloss), so every test pumps fixed
// durations instead of pumpAndSettle.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mide/features/ai/ai_chat_ui.dart';
import 'package:mide/features/ai/ai_model.dart';
import 'package:mide/features/ai/ai_providers.dart';

class FakeAiSession extends AiSessionNotifier {
  FakeAiSession(this.initial);

  final AiSessionState initial;

  int sends = 0;
  int cancels = 0;
  int clears = 0;
  String? lastSent;

  @override
  AiSessionState build(PersonaArg arg) {
    systemPrompt = arg.systemPrompt;
    // Deliberately skips the real chat restore: that reads secure storage.
    return initial;
  }

  @override
  void send(String question) {
    sends++;
    lastSent = question;
    final text = question.trim();
    if (text.isEmpty || state.busy) return;
    state = state.copyWith(
      messages: [
        ...state.messages,
        AiMessage(AiRole.user, text),
        const AiMessage(AiRole.assistant, '', streaming: true),
      ],
      busy: true,
      streaming: true,
      clearError: true,
    );
  }

  @override
  void cancel() {
    cancels++;
    state = state.copyWith(busy: false, streaming: false);
  }

  @override
  Future<void> clear() async {
    clears++;
    state = const AiSessionState();
  }
}

/// Gives the test a phone-shaped surface. The default 800x600 window is
/// shorter than any real device and makes the topics sheet overflow.
void usePhoneSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
}

/// Pumps the AI tab with [initial] state and lets the entrance animations run.
Future<FakeAiSession> pumpAiTab(
  WidgetTester tester, {
  AiSessionState initial = const AiSessionState(),
}) async {
  usePhoneSurface(tester);
  final fake = FakeAiSession(initial);
  await tester.pumpWidget(
    ProviderScope(
      // The family is overridden rather than the concrete `aiSessionProvider`,
      // because only the family exposes `overrideWith`.
      overrides: [personaSessionProvider.overrideWith(() => fake)],
      child: const MaterialApp(home: AiTab()),
    ),
  );
  await tester.pump(const Duration(milliseconds: 100));
  return fake;
}

void main() {
  group('header branding', () {
    testWidgets('shows the persona name, the AI badge and the disclaimer', (
      tester,
    ) async {
      await pumpAiTab(tester);

      expect(find.text('Ada Cry (Ада Край)'), findsOneWidget);
      expect(find.text('AI'), findsOneWidget);
      expect(find.text('AI Can Make Mistakes.'), findsOneWidget);
      // The MIDE wordmark is gone from this screen entirely.
      expect(find.text('MIDE'), findsNothing);
    });

    testWidgets('no provider pills in the header any more', (tester) async {
      await pumpAiTab(
        tester,
        initial: const AiSessionState(providerLabel: 'Horde'),
      );

      expect(find.text('Horde'), findsNothing);
      expect(find.textContaining('Pollinations'), findsNothing);
      expect(find.byIcon(Icons.key_rounded), findsNothing);
    });

    testWidgets('never shows the retired persona name', (tester) async {
      await pumpAiTab(tester);

      expect(find.text('Ада'), findsNothing);
      expect(find.text('АДУСЯ'), findsNothing);
      expect(find.textContaining('Ады'), findsNothing);
    });
  });

  group('composer', () {
    testWidgets('sending passes the typed text and clears the field', (
      tester,
    ) async {
      final fake = await pumpAiTab(tester);

      await tester.enterText(find.byType(TextField), 'привет');
      await tester.pump();
      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pump();

      expect(fake.sends, 1);
      expect(fake.lastSent, 'привет');
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
    });

    testWidgets('whitespace-only input is not sent', (tester) async {
      final fake = await pumpAiTab(tester);

      await tester.enterText(find.byType(TextField), '   ');
      await tester.pump();
      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pump();

      // Rejected in the tab itself, before it ever reaches the session.
      expect(fake.sends, 0);
      expect(fake.state.messages, isEmpty);
    });

    testWidgets('a busy session swaps send for stop, and stop cancels', (
      tester,
    ) async {
      final fake = await pumpAiTab(
        tester,
        initial: const AiSessionState(
          busy: true,
          streaming: true,
          messages: [
            AiMessage(AiRole.user, 'вопрос'),
            AiMessage(AiRole.assistant, '', streaming: true),
          ],
        ),
      );

      expect(find.byIcon(Icons.stop_rounded), findsOneWidget);
      expect(find.byIcon(Icons.send_rounded), findsNothing);

      await tester.tap(find.byIcon(Icons.stop_rounded));
      await tester.pump();
      expect(fake.cancels, 1);
    });
  });

  group('messages', () {
    testWidgets('a finished answer is rendered as text', (tester) async {
      await pumpAiTab(
        tester,
        initial: const AiSessionState(
          messages: [
            AiMessage(AiRole.user, 'вопрос'),
            AiMessage(AiRole.assistant, 'ответ'),
          ],
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('вопрос'), findsOneWidget);
      expect(find.text('ответ'), findsOneWidget);
    });

    testWidgets('an empty streaming answer shows the thinking caret', (
      tester,
    ) async {
      await pumpAiTab(
        tester,
        initial: const AiSessionState(
          busy: true,
          streaming: true,
          messages: [
            AiMessage(AiRole.user, 'вопрос'),
            AiMessage(AiRole.assistant, '', streaming: true),
          ],
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));

      // The caret is a bare underscore, not a bubble.
      expect(find.text('_'), findsOneWidget);
    });

    testWidgets('an error surfaces as a card with a retry action', (
      tester,
    ) async {
      final fake = await pumpAiTab(
        tester,
        initial: const AiSessionState(
          messages: [AiMessage(AiRole.user, 'вопрос')],
          error: aiBusyPhrase,
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text(aiBusyPhrase), findsOneWidget);

      await tester.tap(find.byIcon(Icons.refresh_rounded));
      await tester.pump();

      expect(fake.sends, 1);
      expect(
        fake.lastSent,
        'вопрос',
        reason: 'retry re-sends the last question',
      );
    });

    testWidgets('the clear button is disabled on an empty chat', (
      tester,
    ) async {
      final fake = await pumpAiTab(tester);

      await tester.tap(find.byIcon(Icons.cleaning_services_rounded));
      await tester.pump();

      expect(fake.clears, 0, reason: 'nothing to clear yet');
    });

    testWidgets('the clear button wipes a conversation', (tester) async {
      final fake = await pumpAiTab(
        tester,
        initial: const AiSessionState(
          messages: [AiMessage(AiRole.user, 'вопрос')],
        ),
      );

      await tester.tap(find.byIcon(Icons.cleaning_services_rounded));
      await tester.pump();

      expect(fake.clears, 1);
    });
  });

  group('topics sheet', () {
    testWidgets('opens, and picking a topic fills the composer', (
      tester,
    ) async {
      final fake = await pumpAiTab(tester);

      await tester.tap(find.byIcon(Icons.more_horiz_rounded));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Выбрать тему'), findsOneWidget);
      expect(find.text('Прогнозы'), findsOneWidget);

      await tester.tap(find.text('Прогнозы'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, contains('прогноз'));
      // Filling the composer must not send on its own.
      expect(fake.sends, 0);
    });

    testWidgets('the sheet never mentions the retired persona', (tester) async {
      await pumpAiTab(tester);

      await tester.tap(find.byIcon(Icons.more_horiz_rounded));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.textContaining('Ады'), findsNothing);
    });
  });
}
