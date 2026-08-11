# 磷光色板与夜间模式

本文记录桌面的磷光色板架构（绿/琥珀两套单色控制台配色，可即时切换），以及 hyprsunset 夜间模式相关的几条踩坑结论。

> **已废弃**：曾经把夜间模式重新定义为「绿→琥珀色彩变换」（1100 K + gamma 280% + `max-gamma = 300`），试图用一个 CTM 把绿色磷光变换成琥珀磷光。该方案已被放弃，`home/desktop/hyprsunset.nix` 现在是标准 hyprsunset 行为：gamma 保持默认 1.0，**色温是唯一要调的旋钮**。本文只保留仍然成立的部分。

---

## 1. 最终配置一览

| 项目 | 值 | 位置 |
| --- | --- | --- |
| 活动色板 | `green`（鲜亮版，前景 `#4BAE55`，饱和度 0.57） | `home/palettes.nix` |
| 备用色板 | `amber`（前景 `#D99B32`） | `home/palettes.nix` |
| 白天 | 06:00 / 6500 K / gamma 1.0 | `home/desktop/hyprsunset.nix` |
| 夜间 | 16:00 / 3500 K / gamma 1.0（色温仍在实机微调） | `home/desktop/hyprsunset.nix` |
| 屏幕着色器 | 深色模式使用 `panel.glsl`；可从 Rofi 临时关闭 | `home/desktop/theming.nix`、`home/programs/launchers.nix` |
| Super+N | 开关：开启时 3500 K / gamma 1.0；第二次按下切换到 identity CTM（无滤镜画面） | `dotfiles/hypr/hyprland.lua` |

命令：

```sh
phosphor                # 在绿色/琥珀色板之间即时切换
phosphor amber          # 或 phosphor green / phosphor status
hyprsunset-warmth 3200  # 手动覆盖当前色温（2000-6500，100 K 步进）
hyprsunset-night        # 开关；第二次按下用 identity CTM 恢复无滤镜画面
```

`hyprsunset-night` 不会停止服务；下一次 06:00 / 16:00 的定时切换仍会正常应用对应 profile。

---

## 2. 架构：色板阶梯

`home/palettes.nix` 是唯一色彩来源。一个 profile 是**十级递增亮度的阶梯**，每个终端槽位按**级名**而不是按十六进制赋值：

```
background < deepSurface < raisedBlack < subtleBorder < mutedText
          < secondaryText < accent < foreground < bright < hot
```

这样换磷光只需提供十个颜色，就能继承此前调好的全部强调层级，包括几个刻意的「不规则」安排：

- `raisedBlack` —— ANSI 黑，抬离背景，好让用 ANSI 黑绘制的选中行仍然可见
- `secondaryText` —— ANSI 白，**压到**前景之下，让 SGR-37 的次要文本读起来确实是次要的
- `hot` —— ANSI 亮绿，**抬到**前景之上，让高亮选中项能区分出来
- `bright` —— ANSI 亮蓝，位于前景与 hot 之间，让模糊匹配片段读作强调而非刺眼

因为这些选择是**位置性**的，换 profile 会自动带过去，不需要重新调教依赖它们的程序。

### 覆盖范围

- **已参数化（改 `activeName` 一行 + rebuild 即可全部跟随）**：foot、fzf、newt、btop、mako、rofi、tmux、theming.nix（Hyprland 边框/背景/壁纸）
- **静态替换（一次性改了 792 处十六进制）**：Yazi flavor + tmtheme、nvim 配色、hypr 配置、herdr、pi 主题、GTK/xfwm 主题、statusline 注释
- **通过 ANSI 槽位自动跟随**：shell、Starship、Claude Code、man page、tmux 内容

### 即时切换（`phosphor`）

`home/desktop/phosphor-switch.nix`。这是**真正的色板互换**，与夜间模式无关：两侧都是 `home/palettes.nix` 里的真实 profile，未经任何滤镜。Foot 把两套完整主题放在一个配置里，靠 SIGUSR1/SIGUSR2 切换，所有已开窗口立即重绘，不需要重载、重启或 rebuild。够不到的是任何硬编码十六进制（而非引用 ANSI 槽位）的程序：fzf、btop、Yazi flavor、mako、rofi、Hyprland 边框、GTK 主题都是按构建时的 profile 生成的，只有 rebuild 能改。

---

## 3. 关键技术发现（仍然成立）

### 3.1 CTM 不出现在截图里

hyprsunset 的 CTM 在**扫描输出（scanout）**阶段应用，不在合成缓冲区里。实测：2000 K 开启前后两张截图**逐像素完全相同**（0 个像素不同）。

**后果**：夜间模式无法用截图验证。替代验证路径是读服务自己打印的那行日志：

```
┣ Calculated the CTM to be [mat3x3: ...]
```

### 3.2 色温被整数量化到百位

`matrixForKelvin` 里是 `temp /= 100`，**整数除法**。所以 3500 K 和 3599 K 产生完全相同的矩阵，而 3480 K 会**静默地**当成 3400 K 处理。

**规则：色温永远写 100 的整数倍。** `hyprsunset-warmth` 也据此只接受 100 K 步进的值。

### 3.3 CTM 是按输出设置的，没有 per-window 作用域

`sendSetCtmForOutput`：hyprland-ctm-control-v1 只能按 output 设置。单显示器下屏幕上所有内容必然共享同一个矩阵——**夜间模式无法只作用于一个窗口或工作区**。

### 3.4 1900 K 以下蓝色被强制归零

hyprsunset 的黑体曲线在 1900 K 以下把蓝色通道打到精确的零。常规夜灯档位（2700–3500 K）仍会通过一部分蓝光。

---

## 4. 遗留事项

- `home/desktop/palette-compare.nix`，以及 `home/palettes.nix` 里的 `nightGain` / `amberViaNight` / `greenAsNight`，都是为已废弃的绿→琥珀变换服务的：它们按当时的夜间增益（2.8 / 0.85 / 0）对色板做预失真或预测。变换取消后这些值已与实际配置脱节，`palette-compare` 的对比不再有意义。代码尚未删除。
- `newt.nix` 用了 `amber`/`brightamber` 这两个颜色名，但它们**不是 newt 的合法颜色名**（早于磷光改动就存在）。改成合法名会改变 nmtui 外观，故未动。
- `vt220-amber` / `assets/themes/VT220-Amber` 等标识符现在装的是绿色值。当时刻意只改颜色不改名字。
- `docs/amber-terminal-theme-plan.md` 仍记录着琥珀色板 token。
- **inode 曾经耗尽**：一次 rebuild 报 "No space left on device"，但根分区还有 187 GB。真正原因是 inode 用满（30.1 M 的 100%）。`nix-collect-garbage`（保守模式，只删无引用路径，保留所有 generation）释放了 102 GB，inode 降到 30%。需要留意复发。

---

## 5. 截图

`~/Pictures/phosphor-theme/`。`1`、`2`、`3`、`7`、`8` 属于已废弃的绿→琥珀变换，仅作历史存档；其余是普通色板截图。

| 文件 | 内容 |
| --- | --- |
| `1-night-comparison.png` | （废弃方案）ACTUAL vs TARGET 并排 |
| `2-night-comparison-raw-capture.png` | （废弃方案）同上，合成器原始帧 |
| `3-yazi-green-vs-night.png` | （废弃方案）Yazi 绿色 / 变换后 |
| `4-yazi-green.png` | Yazi 绿色 |
| `5-yazi-preview-green.png` | Yazi 语法高亮预览窗格 |
| `6-green-ansi-ladder.png` | 完整 ANSI 阶梯 + 严重度渐变 |
| `7-palette-strips.png` | （废弃方案）三行色板：绿 / 绿+CTM / 琥珀 |
| `8-revised-green-night-comparison.png` | （废弃方案）灰绿版 ACTUAL vs TARGET |
| `9-revised-green-yazi.png` | 灰绿版 Yazi（白天） |

注意 `1`、`3`、`8` **不是原始截图**，是把日志里的矩阵在软件里应用到未变换帧上重建出来的（见 3.1）。
