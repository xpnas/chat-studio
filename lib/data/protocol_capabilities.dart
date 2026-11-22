import 'models.dart';

enum ProtocolCapability {
  agents,
  sessionTasks,
  messageSelection,
  person,
  timeline,
}

enum CapabilityState { unknown, supported, unsupported, unavailable }

enum ProtocolFailure {
  unsupported,
  notFound,
  unauthenticated,
  forbidden,
  temporary,
}

ProtocolFailure classifyProtocolFailure(
  Object error, {
  bool confirmedMissingRoute = false,
}) {
  if (error is ApiException) {
    if (error.status == 401) return ProtocolFailure.unauthenticated;
    if (error.status == 403) return ProtocolFailure.forbidden;
    if (error.status == 404) {
      return confirmedMissingRoute
          ? ProtocolFailure.unsupported
          : ProtocolFailure.notFound;
    }
    if (error.status == 501) return ProtocolFailure.unsupported;
  }
  return ProtocolFailure.temporary;
}

/// One instance belongs to a StudioApi identity. No write requests probe support.
class ProtocolCapabilities {
  int _generation = 0;
  final _states = <ProtocolCapability, CapabilityState>{};
  final _requests = <ProtocolCapability, int>{};

  CapabilityState operator [](ProtocolCapability capability) =>
      _states[capability] ?? CapabilityState.unknown;

  void invalidate() {
    _generation++;
    _states.clear();
    _requests.clear();
  }

  Future<T> read<T>(
    ProtocolCapability capability,
    Future<T> Function() fetch, {
    bool Function(Object error)? isMissingRoute,
  }) async {
    final generation = _generation;
    final request = (_requests[capability] ?? 0) + 1;
    _requests[capability] = request;
    bool current() =>
        generation == _generation && _requests[capability] == request;
    try {
      final result = await fetch();
      if (!current()) throw const StaleProtocolResponse();
      _states[capability] = CapabilityState.supported;
      return result;
    } catch (error) {
      if (!current()) throw const StaleProtocolResponse();
      final failure = classifyProtocolFailure(
        error,
        confirmedMissingRoute: isMissingRoute?.call(error) ?? false,
      );
      _states[capability] = switch (failure) {
        ProtocolFailure.unsupported => CapabilityState.unsupported,
        ProtocolFailure.notFound => this[capability],
        _ => CapabilityState.unavailable,
      };
      rethrow;
    }
  }
}

class StaleProtocolResponse implements Exception {
  const StaleProtocolResponse();
  @override
  String toString() => '已丢弃：连接身份或请求已变化';
}
