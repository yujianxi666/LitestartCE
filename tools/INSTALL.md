# 安装说明

`dist/` 里的两个包内容完全一致，只有两处差异：Firefox 版多了一个 `browser_specific_settings.gecko` 配置，扩展名不同。

| 文件 | 适用浏览器 |
| --- | --- |
| `LitestartCE-v1.7.2-chrome.zip` | Chrome / Edge / 以及其他 Chromium 内核浏览器 |
| `LitestartCE-v1.7.2-firefox.xpi` | Firefox |

## 重新打包

改了代码之后重新生成这两个包：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\build-packages.ps1
```

校验已生成的包（结构、路径分隔符、必需文件、有没有混进开发文件）：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\verify-packages.ps1
```

打包脚本只收运行期文件，`docs/`、`.github/`、`tools/`、README 都不会进包。

## Chrome / Edge 安装

商店未上架，只能以「已解压的扩展程序」方式加载：

1. **先把 zip 解压到一个文件夹**（不要删掉，浏览器是直接读这个文件夹的）
2. 打开 `chrome://extensions` 或 `edge://extensions`，打开右上角**开发人员模式**
3. 点「**加载已解压的扩展程序**」，选择第 1 步解压出来的文件夹（里面直接就是 `manifest.json`）
4. 打开新标签页即可看到 LitestartCE

> 直接把 `.zip` 拖进扩展页面在 Chrome/Edge 上**不生效**（拖拽安装只接受商店签名过的 `.crx`），必须走「加载已解压」。

## Firefox 安装

`.xpi` 本质就是改了扩展名的 zip。

**方式一：临时加载（无需签名，重启后失效）**

1. 打开 `about:debugging#/runtime/this-firefox`
2. 点「**临时载入附加组件**」
3. 选择 `LitestartCE-v1.7.2-firefox.xpi`（选文件本身，不用解压）

**方式二：永久安装（需要签名）**

Firefox 正式版默认只允许安装 Mozilla 签名的扩展，未签名的 `.xpi` 双击会提示"此附加组件无法安装"。要永久安装，需要先把包提交到 [addons.mozilla.org](https://addons.mozilla.org/developers/) 走一遍签名（可选择"仅自己分发 / unlisted"，不一定公开上架），拿到签名后的 `.xpi` 再安装。

## 已知限制

- **Firefox 包未在真实 Firefox 上验证过**（打包机器上没装 Firefox）。manifest 用的是 MV3 + `chrome_url_overrides.newtab`，MDN 标注该键自 manifest v2 起在 Firefox 可用，`strict_min_version` 设为 `109.0`（Firefox 109 起正式启用 MV3）。若在 Firefox 上加载报错，请把报错信息发我。
- Firefox 端 `chrome.*` 命名空间可用；本扩展没有后台脚本，只有新标签页页面，因此不涉及 MV3 后台服务脚本的差异。
- 更新检查、图标抓取等会请求网络；离线时相关功能静默失败，不影响新标签页本身。
