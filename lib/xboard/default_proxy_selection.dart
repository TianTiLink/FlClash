import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';

/// Fills only missing/invalid selector choices with the first concrete node.
/// Existing user choices are never reordered or overwritten.
Map<String, String> withDefaultProxySelections({
  required List<Group> groups,
  required Map<String, String> selectedMap,
}) {
  final next = Map<String, String>.from(selectedMap);
  final groupNames = groups.map((group) => group.name).toSet();
  const specialNames = {'DIRECT', 'REJECT', 'GLOBAL'};

  for (final group in groups) {
    if (group.type != GroupType.Selector || group.all.isEmpty) continue;
    final current = next[group.name];
    if (current != null && group.all.any((proxy) => proxy.name == current)) {
      continue;
    }
    final candidates = group.all.where(
      (proxy) =>
          !specialNames.contains(proxy.name.toUpperCase()) &&
          !groupNames.contains(proxy.name),
    );
    if (candidates.isNotEmpty) next[group.name] = candidates.first.name;
  }
  return next;
}
