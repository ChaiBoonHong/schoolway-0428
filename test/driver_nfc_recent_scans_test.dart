import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schoolway/core/theme/schoolway_theme.dart';
import 'package:schoolway/features/driver/tabs/driver_nfc_tab.dart';
import 'package:schoolway/l10n/app_localizations.dart';

Widget _host({
  required Widget child,
  Brightness brightness = Brightness.light,
  bool disableAnimations = false,
  double textScale = 1.0,
}) {
  return MaterialApp(
    theme: brightness == Brightness.dark
        ? SchoolWayTheme.dark
        : SchoolWayTheme.light,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Builder(
      builder: (context) {
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(
            disableAnimations: disableAnimations,
            textScaler: TextScaler.linear(textScale),
          ),
          child: Scaffold(body: child),
        );
      },
    ),
  );
}

void main() {
  group('DriverNFCTab inactive state', () {
    testWidgets('shows inactive placeholder when activeSession is null', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          child: const DriverNFCTab(activeSession: null, nfcTabActive: true),
        ),
      );

      expect(find.byIcon(Icons.nfc_outlined), findsOneWidget);
      expect(find.text('NFC Scanning Disabled'), findsOneWidget);
      expect(
        find.textContaining('Start a route session from the Trip tab'),
        findsOneWidget,
      );
    });

    for (final size in <Size>[
      const Size(390, 844),
      const Size(800, 1024),
      const Size(1280, 800),
    ]) {
      for (final brightness in Brightness.values) {
        testWidgets(
          'inactive view renders at ${size.width.toInt()}x${size.height.toInt()} in ${brightness.name}',
          (tester) async {
            tester.view.physicalSize = size;
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);

            await tester.pumpWidget(
              _host(
                brightness: brightness,
                child: const DriverNFCTab(
                  activeSession: null,
                  nfcTabActive: true,
                ),
              ),
            );

            expect(tester.takeException(), isNull);
            expect(find.byIcon(Icons.nfc_outlined), findsOneWidget);
          },
        );
      }
    }
  });

  group('Recent Scans Bottom Sheet interaction and semantics', () {
    testWidgets(
      'bottom sheet starts collapsed, shows drag handle, and toggles on header tap',
      (tester) async {
        final semanticsHandle = tester.ensureSemantics();
        try {
          final controller = DraggableScrollableController();
          var expanded = false;

          await tester.pumpWidget(
            _host(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final textScale = MediaQuery.textScalerOf(context).scale(1);
                  final headerHeight = (76 * textScale).clamp(76.0, 108.0);
                  final minSize = (headerHeight / constraints.maxHeight).clamp(
                    0.12,
                    0.45,
                  );
                  final maxSize = minSize < 0.58 ? 0.58 : minSize;

                  return StatefulBuilder(
                    builder: (context, setState) {
                      return Stack(
                        children: [
                          const Positioned.fill(
                            child: Center(child: Text('NFC Target Area')),
                          ),
                          NotificationListener<DraggableScrollableNotification>(
                            onNotification: (notification) {
                              final isExp =
                                  notification.extent >
                                  (notification.minExtent +
                                          notification.maxExtent) /
                                      2;
                              if (isExp != expanded) {
                                setState(() => expanded = isExp);
                              }
                              return false;
                            },
                            child: DraggableScrollableSheet(
                              controller: controller,
                              initialChildSize: minSize,
                              minChildSize: minSize,
                              maxChildSize: maxSize,
                              snap: true,
                              snapSizes: [minSize, maxSize],
                              builder: (context, scrollController) {
                                final strings = AppLocalizations.of(context);
                                return Container(
                                  decoration: BoxDecoration(
                                    color: SchoolWayTheme.surface,
                                    borderRadius: const BorderRadius.vertical(
                                      top: Radius.circular(20),
                                    ),
                                  ),
                                  child: CustomScrollView(
                                    controller: scrollController,
                                    slivers: [
                                      SliverToBoxAdapter(
                                        child: Semantics(
                                          container: true,
                                          button: true,
                                          expanded: expanded,
                                          label: expanded
                                              ? strings.collapseRecentScans
                                              : strings.expandRecentScans,
                                          excludeSemantics: true,
                                          child: InkWell(
                                            key: const ValueKey(
                                              'recent-scans-toggle',
                                            ),
                                            onTap: () {
                                              final target = expanded
                                                  ? minSize
                                                  : maxSize;
                                              controller.jumpTo(target);
                                            },
                                            child: SizedBox(
                                              height: headerHeight,
                                              child: Column(
                                                children: [
                                                  const SizedBox(height: 8),
                                                  Container(
                                                    width: 44,
                                                    height: 4,
                                                    decoration: BoxDecoration(
                                                      color: SchoolWayTheme
                                                          .blueGrey,
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            2,
                                                          ),
                                                    ),
                                                  ),
                                                  Expanded(
                                                    child: Row(
                                                      children: [
                                                        const Icon(
                                                          Icons.history,
                                                        ),
                                                        Text(
                                                          strings.recentScans,
                                                        ),
                                                        Text(
                                                          strings
                                                              .recentScansTotal(
                                                                0,
                                                              ),
                                                        ),
                                                        Icon(
                                                          expanded
                                                              ? Icons
                                                                    .keyboard_arrow_down
                                                              : Icons
                                                                    .keyboard_arrow_up,
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      SliverFillRemaining(
                                        child: Center(
                                          child: Text(
                                            strings.noScansYetTapAnNfcCard,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      );
                    },
                  );
                },
              ),
            ),
          );

          // Header visible and collapsed
          expect(find.text('Recent Scans'), findsOneWidget);
          expect(find.text('0 total'), findsOneWidget);
          expect(find.byIcon(Icons.keyboard_arrow_up), findsOneWidget);
          expect(find.bySemanticsLabel('Expand recent scans'), findsOneWidget);

          // Tap toggle to expand
          await tester.tap(find.byKey(const ValueKey('recent-scans-toggle')));
          await tester.pumpAndSettle();

          expect(find.byIcon(Icons.keyboard_arrow_down), findsOneWidget);
          expect(
            find.bySemanticsLabel('Collapse recent scans'),
            findsOneWidget,
          );

          // Tap toggle to collapse
          await tester.tap(find.byKey(const ValueKey('recent-scans-toggle')));
          await tester.pumpAndSettle();

          expect(find.byIcon(Icons.keyboard_arrow_up), findsOneWidget);
          expect(find.bySemanticsLabel('Expand recent scans'), findsOneWidget);
        } finally {
          semanticsHandle.dispose();
        }
      },
    );

    testWidgets('respects reduced motion when expanding', (tester) async {
      final controller = DraggableScrollableController();
      var jumpCalled = false;

      await tester.pumpWidget(
        _host(
          disableAnimations: true,
          child: DraggableScrollableSheet(
            controller: controller,
            initialChildSize: 0.2,
            minChildSize: 0.2,
            maxChildSize: 0.6,
            builder: (context, scrollController) {
              return ListView(
                controller: scrollController,
                children: [
                  InkWell(
                    onTap: () {
                      if (MediaQuery.disableAnimationsOf(context)) {
                        jumpCalled = true;
                        controller.jumpTo(0.6);
                      }
                    },
                    child: const Text('Toggle Sheet'),
                  ),
                ],
              );
            },
          ),
        ),
      );

      await tester.tap(find.text('Toggle Sheet'));
      await tester.pump();
      expect(jumpCalled, isTrue);
    });
  });
}
