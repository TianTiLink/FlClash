Future<void> applyLiveProxySwitch({
  required Future<void> Function() changeProxy,
  required bool closeExistingConnections,
  required Future<void> Function() closeConnections,
  required Future<void> Function() resetConnections,
}) async {
  await changeProxy();
  if (closeExistingConnections) {
    await closeConnections();
  } else {
    await resetConnections();
  }
}
