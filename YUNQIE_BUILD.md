# YunQieLink 客户端构建与发布

本源码已经接入新的独立面板：

- 主站：`https://yunqielink.com`
- API 主入口：`https://yunqie12s34hhf8.xyz`
- API 备用入口：`https://yunqiejhi4o41a881s.xyz`
- 节点上报入口：`https://api.yunqielink.net`
- 官网入口：`https://yunqie.xyz`、`https://yunqielink.xyz`、`https://yunqieweb.xyz`
- Android applicationId：`com.yunqielink.app`
- macOS bundle id：`com.yunqielink.app`
- 当前客户端版本：`0.8.96`

旧项目的 Firebase/Crashlytics 已移除，构建时不需要 `SERVICE_JSON`。云茄新 Logo 已替换登录页、Android、Windows、macOS、Linux 与 PWA 图标资源。

## GitHub Actions 构建

1. 新建公开 GitHub 仓库（GPL-3.0 要求发布完整修改源码）。
2. 上传本目录全部文件；`core/Clash.Meta` 已补齐，不再是 ZIP 中的空目录。
3. GitHub 仓库地址已配置为 `newlastold/YunQieLink-client`，客户端版本检查和 README Releases 链接均使用该地址。
4. 在 Actions 页面运行：
   - `build-android`：生成 APK；
   - `build-windows`：生成 Windows 安装包/便携包；
   - `build-macos`：生成 macOS 压缩包。
5. 正式发布前，在仓库 Secrets 中配置签名参数；不配置时 Android 会产出 debug 签名的 `.dev` 侧载包。

## 上传到面板

最终公开文件名与面板配置保持一致：

- `YunQieLink-android.apk`
- `YunQieLink-windows.exe`
- `YunQieLink-macos.zip`

上传到服务器 `/opt/yunqie-panel/apk/` 后，对应下载地址为：

- `https://yunqielink.com/dl/YunQieLink-android.apk`
- `https://yunqielink.com/dl/YunQieLink-windows.exe`
- `https://yunqielink.com/dl/YunQieLink-macos.zip`

## 本地验证

仓库 CI 的主要验证命令：

```bash
flutter pub get
flutter analyze --no-fatal-infos
flutter test --reporter expanded
```

完整平台打包使用：

```bash
dart setup.dart android --env stable -v
dart setup.dart windows --env stable -v
dart setup.dart macos --env stable -v
```
