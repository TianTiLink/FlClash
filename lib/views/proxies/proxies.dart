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
import 'package:fl_clash/xboard/xboard_api.dart';
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
  bool _testingDelay = false;

  // 刷新订阅:从面板重拉最新节点并重新应用(复用账户页同款逻辑)。
  Future<void> _refreshSubscription() async {
    if (_refreshingSub) return;
    setState(() => _refreshingSub = true);
    final messenger = ScaffoldMessenger.of(context);
    final previousSubscription = ref.read(xboardAuthProvider).subscribeUrl;
    try {
      final url = await ref
          .read(xboardAuthProvider.notifier)
          .refreshSubscribe();
      if (url == null) throw '未登录或获取节点失败';
      await importXboardSubscription(url);
      messenger.showSnackBar(const SnackBar(content: Text('节点已刷新')));
    } on XboardNoSubscriptionException {
      final removed = await clearTianTiSubscriptionProfiles(
        subscribeUrl: previousSubscription,
      );
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            removed > 0
                ? '当前账号没有有效套餐，已清除旧节点。请购买套餐后再刷新。'
                : '当前账号没有有效套餐，请购买套餐后再刷新节点。',
          ),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('网络连接失败，当前节点已保留。请稍后重试：$e')),
      );
    } finally {
      if (mounted) setState(() => _refreshingSub = false);
    }
  }

  Future<void> _testCurrentGroupDelay() async {
    if (_testingDelay) return;
    setState(() => _testingDelay = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final count =
          await _proxiesTabKey.currentState?.delayTestCurrentGroup() ?? 0;
      messenger.showSnackBar(
        SnackBar(
          content: Text(count > 0 ? '延迟检测完成，共 $count 个节点' : '当前分组没有可检测的节点'),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('延迟检测失败：$e')));
    } finally {
      if (mounted) setState(() => _testingDelay = false);
    }
  }

  List<Widget> _buildActions(BuildContext context, {required bool noPlan}) {
    final appLocalizations = context.appLocalizations;
    return [
      // 刷新订阅:从面板重拉最新节点。
      IconButton(
        tooltip: '刷新节点',
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
      if (_isTab && !noPlan)
        IconButton(
          tooltip: appLocalizations.delayTest,
          onPressed: _testingDelay ? null : _testCurrentGroupDelay,
          icon: _testingDelay
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.network_ping),
        ),
      if (_isTab && !noPlan)
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
    final auth = ref.watch(xboardAuthProvider);
    final noPlan = auth.loggedIn && auth.subscribeUrl == null;
    return CommonScaffold(
      key: _scaffoldKey,
      isLoading: isLoading,
      resizeToAvoidBottomInset: false,
      floatingActionButton: null,
      actions: _buildActions(context, noPlan: noPlan),
      title: context.appLocalizations.proxies,
      searchState: AppBarSearchState(onSearch: _onSearch),
      body: Column(
        children: [
          if (noPlan)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, size: 20),
                  SizedBox(width: 10),
                  Expanded(child: Text('当前账号暂无有效套餐，购买套餐后刷新即可获取节点。')),
                ],
              ),
            ),
          Expanded(
            child: noPlan
                ? const _NoPlanNodePlaceholder()
                : switch (proxiesType) {
                    ProxiesType.tab => ProxiesTabView(key: _proxiesTabKey),
                    ProxiesType.list => const ProxiesListView(),
                  },
          ),
          ProxiesConnectBar(enabled: !noPlan),
        ],
      ),
    );
  }
}

class _NoPlanNodePlaceholder extends StatelessWidget {
  const _NoPlanNodePlaceholder();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.topCenter,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(16, 18, 16, 16),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: 0.38,
          ),
          border: Border.all(color: theme.dividerColor.withValues(alpha: 0.55)),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(Icons.lock_outline_rounded, color: theme.hintColor),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '暂无可用节点',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    '当前账号没有有效套餐',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.hintColor,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    '此卡片仅用于提示，不能连接，也不会执行延迟检测。购买套餐后点击右上角刷新节点。',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.hintColor,
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '不可连接',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.hintColor,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
