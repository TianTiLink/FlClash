import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/common.dart';
import 'package:fl_clash/models/state.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/views/proxies/list.dart';
import 'package:fl_clash/views/proxies/providers.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_clash/xboard/proxies_connect_bar.dart';
import 'package:fl_clash/xboard/xboard_auth.dart';
import 'package:fl_clash/xboard/xboard_sync.dart';

import 'setting.dart';
import 'tab.dart';

class ProxiesView extends ConsumerStatefulWidget {
  const ProxiesView({super.key});

  @override
  ConsumerState<ProxiesView> createState() => _ProxiesViewState();
}

class _ProxiesViewState extends ConsumerState<ProxiesView> {
  final GlobalKey<CommonScaffoldState> _scaffoldKey = GlobalKey();
  final GlobalKey<ProxiesTabViewState> _proxiesTabKey = GlobalKey();
  bool _hasProviders = false;
  bool _isTab = false;
  bool _refreshingSub = false;

  // 刷新订阅:从面板重拉最新节点并重新应用(复用账户页同款逻辑)。
  Future<void> _refreshSubscription() async {
    if (_refreshingSub) return;
    setState(() => _refreshingSub = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final url =
          await ref.read(xboardAuthProvider.notifier).refreshSubscribe();
      if (url == null) throw '未登录或获取订阅地址失败';
      await importXboardSubscription(url);
      messenger.showSnackBar(const SnackBar(content: Text('订阅已刷新')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('刷新失败:$e')));
    } finally {
      if (mounted) setState(() => _refreshingSub = false);
    }
  }

  List<Widget> _buildActions(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    return [
      // 刷新订阅:从面板重拉最新节点。
      IconButton(
        tooltip: '刷新订阅',
        onPressed: _refreshingSub ? null : _refreshSubscription,
        icon: _refreshingSub
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.sync),
      ),
      // 延迟测试:从悬浮按钮改到顶栏标题右侧。
      if (_isTab)
        IconButton(
          tooltip: appLocalizations.delayTest,
          onPressed: () async {
            await _proxiesTabKey.currentState?.delayTestCurrentGroup();
          },
          icon: const Icon(Icons.network_ping),
        ),
      if (_isTab)
        IconButton(
          onPressed: () {
            _proxiesTabKey.currentState?.scrollToGroupSelected();
          },
          icon: const Icon(Icons.adjust, weight: 1),
        ),
      CommonPopupBox(
        targetBuilder: (open) {
          return IconButton(
            onPressed: () {
              final isMobile = ref.read(isMobileViewProvider);
              open(offset: Offset(0, isMobile ? 0 : 20));
            },
            icon: const Icon(Icons.more_vert),
          );
        },
        popup: CommonPopupMenu(
          items: [
            PopupMenuItemData(
              icon: Icons.tune,
              label: appLocalizations.settings,
              onPressed: () {
                showSheet(
                  context: context,
                  props: const SheetProps(isScrollControlled: true),
                  builder: (_) {
                    return AdaptiveSheetScaffold(
                      body: const ProxiesSetting(),
                      title: appLocalizations.settings,
                    );
                  },
                );
              },
            ),
            if (_hasProviders)
              PopupMenuItemData(
                icon: Icons.poll_outlined,
                label: appLocalizations.providers,
                onPressed: () {
                  showExtend(
                    context,
                    builder: (_) {
                      return const ProvidersView();
                    },
                  );
                },
              ),
          ],
        ),
      ),
    ];
  }

  void _onSearch(String value) {
    ref.read(queryProvider(QueryTag.proxies).notifier).value = value;
  }

  @override
  void initState() {
    super.initState();
    ref.listenManual(providersProvider.select((state) => state.isNotEmpty), (
      prev,
      next,
    ) {
      if (prev != next) {
        setState(() {
          _hasProviders = next;
        });
      }
    }, fireImmediately: true);
    ref.listenManual(
      proxiesStyleSettingProvider.select(
        (state) => state.type == ProxiesType.tab,
      ),
      (prev, next) {
        if (prev != next) {
          setState(() {
            _isTab = next;
          });
        }
      },
      fireImmediately: true,
    );
    ref.listenManual(
      currentPageLabelProvider.select((state) => state == PageLabel.proxies),
      (prev, next) {
        if (prev != next && next == false) {
          _scaffoldKey.currentState?.handleExitSearching();
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final proxiesType = ref.watch(
      proxiesStyleSettingProvider.select((state) => state.type),
    );
    final isLoading = ref.watch(loadingProvider(LoadingTag.proxies));
    return CommonScaffold(
      key: _scaffoldKey,
      isLoading: isLoading,
      resizeToAvoidBottomInset: false,
      floatingActionButton: null,
      actions: _buildActions(context),
      title: context.appLocalizations.proxies,
      searchState: AppBarSearchState(onSearch: _onSearch),
      body: Column(
        children: [
          Expanded(
            child: switch (proxiesType) {
              ProxiesType.tab => ProxiesTabView(key: _proxiesTabKey),
              ProxiesType.list => const ProxiesListView(),
            },
          ),
          const ProxiesConnectBar(),
        ],
      ),
    );
  }
}
