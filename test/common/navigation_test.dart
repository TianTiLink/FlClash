import 'package:fl_clash/common/constant.dart';
import 'package:fl_clash/common/navigation.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('keeps the proxies entry visible without a local profile', () {
    final item = navigation.getItems().singleWhere(
      (item) => item.label == PageLabel.proxies,
    );

    expect(item.modes, contains(NavigationItemMode.mobile));
    expect(item.modes, contains(NavigationItemMode.desktop));
  });

  test('rebrands the app without moving existing WebDAV backups', () {
    expect(appName, 'TianT.co');
    expect(appStorageNamespace, 'TianTiLink');
  });
}
