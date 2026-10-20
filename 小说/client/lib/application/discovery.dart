import 'dart:async';

import '../domain/access.dart';
import 'access.dart';

final class DiscoveryCancellation {
  bool cancelled = false;
}

final class DiscoveryHit {
  const DiscoveryHit(this.id, this.title, this.rating);
  final String id, title;
  final ContentRating rating;
}

typedef DiscoveryFetch = Future<List<DiscoveryHit>> Function(
  DiscoverySource source,
  String query,
  bool normalOnly,
  DiscoveryCancellation cancellation,
);

/// Real admission/cancellation boundary. Production currently has zero sources;
/// tests drive the same coordinator with owned endpoints, not public websites.
final class DiscoveryCoordinator {
  DiscoveryCoordinator(this.access, this.sources, this.fetch) {
    _subscription = access.changes.listen((_) {
      cancel();
    });
  }
  final AccessController access;
  final List<DiscoverySource> sources;
  final DiscoveryFetch fetch;
  late final StreamSubscription<AccessState> _subscription;
  int _generation = 0;
  final _tokens = <DiscoveryCancellation>[];
  List<DiscoveryHit> results = [];
  void cancel() {
    _generation++;
    for (final token in _tokens) {
      token.cancelled = true;
    }
    _tokens.clear();
    results = results
        .where(
          (h) => !h.rating.protected && h.rating.level == RatingLevel.general,
        )
        .toList();
  }

  Future<List<DiscoveryHit>> search(String query) async {
    cancel();
    results = [];
    final generation = _generation;
    final state = access.state;
    final eligible = sources.where((s) => mayDiscover(s, state)).toList();
    await Future.wait(
      eligible.map((source) async {
        final token = DiscoveryCancellation();
        _tokens.add(token);
        try {
          final hits = await fetch(source, query, !state.adultDiscovery, token);
          if (token.cancelled || generation != _generation) return;
          for (final hit in hits) {
            if (!mayRead(hit.rating, access.state)) continue;
            if (hit.rating.protected && !access.state.adultDiscovery) continue;
            if (source.mode == SourceMode.normal && hit.rating.protected) {
              continue;
            }
            results.add(hit);
          }
        } catch (_) {
          /* One source cannot prevent ordinary results. */
        } finally {
          _tokens.remove(token);
        }
      }),
    );
    return generation == _generation ? List.unmodifiable(results) : const [];
  }

  Future<void> dispose() async {
    cancel();
    await _subscription.cancel();
  }
}
