import 'package:phosphor_icons/phosphor_icons.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

enum AppPage {
  library('library', '我的书架', PhosphorIconsLight.books),
  recent('recent', '最近阅读', PhosphorIconsLight.clock),
  search('search', '在线搜书', PhosphorIconsLight.magnifyingGlass),
  sources('sources', '来源', PhosphorIconsLight.plugsConnected),
  settings('settings', '设置', PhosphorIconsLight.gear),
  notes('notes', '笔记与书签', PhosphorIconsLight.note),
  tasks('tasks', '任务中心', PhosphorIconsLight.downloadSimple),
  statistics('statistics', '阅读统计', PhosphorIconsLight.chartBar),
  reader('reader', '阅读', PhosphorIconsLight.bookOpen),
  states('states', '界面状态检查', PhosphorIconsLight.slidersHorizontal),
  unknown('unknown', '找不到页面', PhosphorIconsLight.warningCircle);

  const AppPage(this.path, this.label, this.icon);
  final String path;
  final String label;
  final IconData icon;
}

@immutable
final class AppLocation {
  const AppLocation(this.page, {this.bookId});
  factory AppLocation.parse(Uri uri) {
    final segments = uri.pathSegments;
    if (segments.isEmpty) return const AppLocation(AppPage.library);
    if (segments.length == 2 &&
        segments.first == 'reader' &&
        segments[1].isNotEmpty) {
      return AppLocation(AppPage.reader, bookId: segments[1]);
    }
    if (segments.length == 1) {
      for (final page in AppPage.values) {
        if (page != AppPage.reader &&
            page != AppPage.unknown &&
            page.path == segments.first) {
          return AppLocation(page);
        }
      }
    }
    return const AppLocation(AppPage.unknown);
  }
  final AppPage page;
  final String? bookId;
  String get path => page == AppPage.reader
      ? '/reader/${Uri.encodeComponent(bookId ?? '')}'
      : '/${page.path}';
}

final class AppNavigation extends ChangeNotifier {
  AppNavigation([AppLocation initial = const AppLocation(AppPage.library)])
    : _location = initial;
  AppLocation _location;
  final _history = <AppLocation>[];
  AppLocation get location => _location;
  bool get canGoBack => _history.isNotEmpty;
  void go(AppLocation target) {
    if (target.path == _location.path) return;
    if (_history.length == 100) _history.removeAt(0);
    _history.add(_location);
    _location = target;
    notifyListeners();
  }

  void replace(AppLocation target) {
    _location = target;
    _history.clear();
    notifyListeners();
  }

  bool back() {
    if (_history.isEmpty) return false;
    _location = _history.removeLast();
    notifyListeners();
    return true;
  }
}

final class LocationParser extends RouteInformationParser<AppLocation> {
  const LocationParser();
  @override
  Future<AppLocation> parseRouteInformation(
    RouteInformation routeInformation,
  ) => SynchronousFuture(AppLocation.parse(routeInformation.uri));
  @override
  RouteInformation restoreRouteInformation(AppLocation configuration) =>
      RouteInformation(uri: Uri.parse(configuration.path));
}

final class ShellRouter extends RouterDelegate<AppLocation>
    with ChangeNotifier, PopNavigatorRouterDelegateMixin<AppLocation> {
  ShellRouter({required this.navigation, required this.builder}) {
    navigation.addListener(notifyListeners);
  }
  final AppNavigation navigation;
  final Widget Function(AppLocation) builder;
  @override
  final navigatorKey = GlobalKey<NavigatorState>();
  @override
  AppLocation get currentConfiguration => navigation.location;
  @override
  Future<void> setNewRoutePath(AppLocation configuration) async =>
      navigation.replace(configuration);
  @override
  Future<bool> popRoute() async => navigation.back();
  @override
  Widget build(BuildContext context) => Navigator(
    key: navigatorKey,
    pages: [
      MaterialPage<void>(
        key: const ValueKey('shell'),
        child: builder(navigation.location),
      ),
    ],
    onDidRemovePage: (_) {},
  );
  @override
  void dispose() {
    navigation.removeListener(notifyListeners);
    super.dispose();
  }
}
