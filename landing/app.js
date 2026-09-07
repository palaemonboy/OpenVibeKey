/*
 * Open VibeKey 落地页交互脚本
 * 纯前端假交互：中英文切换 + 安装命令复制 + 主界面/菜单栏面板演示
 * （快捷键行高亮、灯效分段控件、麦克风开关与音量、系统麦克风切换与锁定、
 * 菜单栏图标展开/收起悬浮面板）
 * 不依赖任何第三方库，不发起任何网络请求
 */
(function () {
  "use strict";

  /* ------------------------------------------------------------------
   * 1. 文案字典（中 / 英 两套，key 对应 HTML 里的 data-i18n）
   * ------------------------------------------------------------------ */
  var I18N = {
    zh: {
      "meta.title": "Open VibeKey — VibeKey 硬件配置工具",

      "hero.kicker": "VibeKey 硬件配置工具 · 原生 macOS 版",
      "hero.title": "把 VibeKey 的每一个键位，交给固件自己记住。",
      "hero.sub": "原生菜单栏应用，把快捷键、媒体键与灯效直接写进 VibeKey 固件——离线也照常生效，不需要后台软件常驻。",
      "hero.download": "通过 Homebrew 安装",
      "hero.brew.label": "在终端中运行：",
      "hero.brew.copyLabel": "复制",
      "hero.brew.copied": "已复制",
      "hero.brew.copyAria": "复制安装命令",

      "demo.title": "看看它长什么样",
      "demo.sub": "下面是 Open VibeKey 主界面与菜单栏面板的可交互还原——纯前端模拟，感受一下真实的操作方式。",
      "demo.menubarTriggerAria": "打开 / 关闭菜单栏面板",
      "demo.lockAria": "切换麦克风锁定",
      "demo.connected": "已连接",
      "demo.profile.default": "默认",
      "demo.profile.studio": "工作室",
      "demo.profile.travel": "旅行",
      "demo.inputDevices": "输入设备",
      "demo.refreshAria": "刷新设备列表",
      "demo.device.au05.meta": "USB · 48 kHz",
      "demo.device.builtin.meta": "内置 · 48 kHz",
      "demo.launchLogin": "开机时启动",
      "demo.openSettings": "打开设置…",
      "demo.quit": "退出",
      "demo.hint": "↑ 试试：点快捷键行的修饰键切换 ⌘ / ⌥ / ⇧ / ⌃、点「清除」清空绑定、切换灯效模式、点系统麦克风的锁形图标、点右上角旋钮图标收起/展开菜单栏面板",

      "mainwin.appearanceAria": "外观",
      "mainwin.model": "型号",
      "mainwin.serial": "SN",
      "mainwin.firmware": "固件",
      "mainwin.aboutAria": "关于",
      "mainwin.restartAria": "重启设备",
      "mainwin.photoAlt": "VibeKey（AU05）设备照片",
      "mainwin.shortcuts.title": "快捷键",
      "mainwin.shortcuts.subtitle": "· 每键一个 · 离线生效",
      "mainwin.demoHint": "示例数据，试着切换修饰键或清除",
      "mainwin.button1": "按钮 1",
      "mainwin.button2": "按钮 2",
      "mainwin.button3": "按钮 3",
      "mainwin.dial.title": "旋钮",
      "mainwin.dial.left": "左转",
      "mainwin.dial.right": "右转",
      "mainwin.dial.press": "按下",
      "mainwin.clear": "清除",
      "mainwin.notSet": "未设置",
      "mainwin.key.mute": "静音/解除静音",
      "mainwin.key.muteShort": "静音/解除…",
      "mainwin.key.space": "空格",
      "mainwin.key.volumeUp": "音量+",
      "mainwin.key.volumeDown": "音量-",
      "mainwin.key.playPause": "播放/暂停",
      "mainwin.key.nextTrack": "下一曲",
      "mainwin.key.prevTrack": "上一曲",
      "mainwin.keyPopoverAria": "主键",
      "mainwin.keyGroup.letters": "字母",
      "mainwin.keyGroup.numbers": "数字",
      "mainwin.keyGroup.function": "功能键",
      "mainwin.keyGroup.arrows": "方向键",
      "mainwin.keyGroup.editing": "编辑键",
      "mainwin.keyGroup.symbols": "符号",
      "mainwin.keyGroup.media": "媒体键",
      "mainwin.keyGroup.openApp": "打开 App",
      "mainwin.key.appWeChat": "微信",
      "mainwin.key.appWeChatFull": "打开 App：微信",
      "mainwin.key.appSafari": "Safari",
      "mainwin.key.appSafariFull": "打开 App：Safari",
      "mainwin.key.appNotes": "备忘录",
      "mainwin.key.appNotesFull": "打开 App：备忘录",
      "mainwin.key.appTerminal": "终端",
      "mainwin.key.appTerminalFull": "打开 App：终端",
      "mainwin.light.title": "灯效",
      "mainwin.light.subtitle": "全局",
      "mainwin.light.modeAria": "灯效模式",
      "mainwin.mode.off": "全灭",
      "mainwin.mode.full": "全亮",
      "mainwin.mode.work": "工作",
      "mainwin.light.brightnessLabel": "亮度",
      "mainwin.light.brightnessAria": "灯效亮度",
      "mainwin.bright.off": "灭",
      "mainwin.bright.low": "低",
      "mainwin.bright.high": "高",
      "mainwin.light.perLed.title": "工作模式各灯",
      "mainwin.light.perLed.btn1Aria": "按钮 1 灯效",
      "mainwin.light.perLed.btn2Aria": "按钮 2 灯效",
      "mainwin.light.perLed.btn3Aria": "按钮 3 灯效",
      "mainwin.light.perLed.dialAria": "旋钮灯效",
      "mainwin.led.solid": "常亮",
      "mainwin.led.breathe": "呼吸",
      "mainwin.mic.title": "麦克风",
      "mainwin.mic.enable": "开关",
      "mainwin.mic.enableAria": "麦克风开关",
      "mainwin.mic.denoise": "降噪",
      "mainwin.mic.denoiseAria": "降噪",
      "mainwin.denoise.off": "关",
      "mainwin.denoise.low": "低",
      "mainwin.denoise.mid": "中",
      "mainwin.denoise.high": "高",
      "mainwin.mic.gain": "收音音量",
      "mainwin.sysmic.title": "系统麦克风",

      "features.title": "功能一览",
      "features.f1.title": "顶栏常驻",
      "features.f1.desc": "纯菜单栏应用，不占 Dock 和 ⌘Tab，点图标即可弹出迷你面板。",
      "features.f2.title": "离线快捷键",
      "features.f2.desc": "3 个圆键与旋钮的左转 / 右转 / 按下都能配快捷键，写进设备固件，离线也生效。",
      "features.f3.title": "媒体键",
      "features.f3.desc": "静音、音量加减、播放暂停、上一曲下一曲，走设备固定功能通道，macOS 原生响应。",
      "features.f4.title": "麦克风管理",
      "features.f4.desc": "查看并切换系统默认输入设备；把默认输入锁定到 VibeKey，被别的 App 抢走会自动切回来。",
      "features.f5.title": "灯效",
      "features.f5.desc": "指示灯模式与三档亮度，可选全灭 / 全亮 / 工作模式，各灯可单独设常亮或呼吸。",
      "features.f6.title": "电源管理",
      "features.f6.desc": "待机时长、休眠时长可调，一键重启设备。",
      "features.f7.title": "多套配置",
      "features.f7.desc": "配置存档，可新增多套随时切换，出差、工作室、居家各留一套。",
      "features.f8.title": "开机自启",
      "features.f8.desc": "登录 macOS 即自动启动，配置一次，之后无需再操心。",
      "features.f10.title": "一键跳 App",
      "features.f10.desc": "按键直接切到指定 App，没运行就启动它。App 常驻时生效，可随时改绑或解绑。",
      "features.f9.title": "完全自主驱动",
      "features.f9.desc": "HID I/O 走 IOKit，运行时零依赖，不链接、不分发厂商代码。",

      "steps.title": "三步开始",
      "steps.s1.title": "下载并安装",
      "steps.s1.desc": "下载 App 或用 Homebrew 安装。",
      "steps.s2.title": "插上 VibeKey",
      "steps.s2.desc": "通过 2.4G 接收器连接设备,请确保不要同时开启官方 App 和本工具，否则会有冲突。",
      "steps.s3.title": "在面板里配置",
      "steps.s3.desc": "给按键、旋钮配快捷键，设置灯效与麦克风锁定，一次配好，离线也生效。",

      "privacy.title": "完全本地运行，不联网",
      "privacy.body": "Open VibeKey 全程离线运行：不联网、不收集任何数据、不上传任何使用信息，所有配置只保存在你的 Mac 本地。",
      "privacy.body2": "驱动完全自主实现：HID 通信基于 IOKit；运行时不含任何 JS / Node / 浏览器，也不链接、不分发厂商代码。",
      "nav.github": "在 GitHub 上查看 OpenVibeKey",

      "footer.disclaimer": "Open VibeKey 是社区独立开发的开源工具，与 Ulanzi / Kehwin 官方无关。",
      "footer.github": "GitHub",
      "footer.license": "开源许可",
      "footer.feedback": "反馈"
    },

    en: {
      "meta.title": "Open VibeKey — Native macOS Configurator for VibeKey",

      "hero.kicker": "VibeKey Hardware Configurator · Native for macOS",
      "hero.title": "Let VibeKey's firmware remember every button for you.",
      "hero.sub": "A native menu bar app that writes your shortcuts, media keys and lighting straight into VibeKey's firmware — they keep working offline, with nothing running in the background.",
      "hero.download": "Install with Homebrew",
      "hero.brew.label": "Run in Terminal:",
      "hero.brew.copyLabel": "Copy",
      "hero.brew.copied": "Copied",
      "hero.brew.copyAria": "Copy install command",

      "demo.title": "See it in action",
      "demo.sub": "An interactive recreation of Open VibeKey's main window and menu bar panel below — a front-end-only simulation, try it out.",
      "demo.menubarTriggerAria": "Open / close the menu bar panel",
      "demo.lockAria": "Toggle microphone lock",
      "demo.connected": "Connected",
      "demo.profile.default": "Default",
      "demo.profile.studio": "Studio",
      "demo.profile.travel": "Travel",
      "demo.inputDevices": "Input Devices",
      "demo.refreshAria": "Refresh device list",
      "demo.device.au05.meta": "USB · 48 kHz",
      "demo.device.builtin.meta": "Built-in · 48 kHz",
      "demo.launchLogin": "Launch at Login",
      "demo.openSettings": "Open Settings…",
      "demo.quit": "Quit",
      "demo.hint": "↑ Try it: toggle a shortcut row's ⌘ / ⌥ / ⇧ / ⌃ modifiers, click Clear to reset a binding, switch lighting modes, click the lock icon under System Microphone, or click the dial icon top-right to collapse / expand the menu bar panel",

      "mainwin.appearanceAria": "Appearance",
      "mainwin.model": "Model",
      "mainwin.serial": "SN",
      "mainwin.firmware": "Firmware",
      "mainwin.aboutAria": "About",
      "mainwin.restartAria": "Restart device",
      "mainwin.photoAlt": "VibeKey (AU05) device photo",
      "mainwin.shortcuts.title": "Shortcuts",
      "mainwin.shortcuts.subtitle": "· One per key · Works offline",
      "mainwin.demoHint": "Sample data — try toggling modifiers or clearing",
      "mainwin.button1": "Button 1",
      "mainwin.button2": "Button 2",
      "mainwin.button3": "Button 3",
      "mainwin.dial.title": "Dial",
      "mainwin.dial.left": "Turn Left",
      "mainwin.dial.right": "Turn Right",
      "mainwin.dial.press": "Press",
      "mainwin.clear": "Clear",
      "mainwin.notSet": "Not set",
      "mainwin.key.mute": "Mute / Unmute",
      "mainwin.key.muteShort": "Mute / Unmute",
      "mainwin.key.space": "Space",
      "mainwin.key.volumeUp": "Volume Up",
      "mainwin.key.volumeDown": "Volume Down",
      "mainwin.key.playPause": "Play / Pause",
      "mainwin.key.nextTrack": "Next Track",
      "mainwin.key.prevTrack": "Previous Track",
      "mainwin.keyPopoverAria": "Main Key",
      "mainwin.keyGroup.letters": "Letters",
      "mainwin.keyGroup.numbers": "Numbers",
      "mainwin.keyGroup.function": "Function Keys",
      "mainwin.keyGroup.arrows": "Arrow Keys",
      "mainwin.keyGroup.editing": "Editing Keys",
      "mainwin.keyGroup.symbols": "Symbols",
      "mainwin.keyGroup.media": "Media Keys",
      "mainwin.keyGroup.openApp": "Open App",
      "mainwin.key.appWeChat": "WeChat",
      "mainwin.key.appWeChatFull": "Open App: WeChat",
      "mainwin.key.appSafari": "Safari",
      "mainwin.key.appSafariFull": "Open App: Safari",
      "mainwin.key.appNotes": "Notes",
      "mainwin.key.appNotesFull": "Open App: Notes",
      "mainwin.key.appTerminal": "Terminal",
      "mainwin.key.appTerminalFull": "Open App: Terminal",
      "mainwin.light.title": "Lighting",
      "mainwin.light.subtitle": "Global",
      "mainwin.light.modeAria": "Lighting mode",
      "mainwin.mode.off": "Off",
      "mainwin.mode.full": "Full",
      "mainwin.mode.work": "Work",
      "mainwin.light.brightnessLabel": "Brightness",
      "mainwin.light.brightnessAria": "Lighting brightness",
      "mainwin.bright.off": "Off",
      "mainwin.bright.low": "Low",
      "mainwin.bright.high": "High",
      "mainwin.light.perLed.title": "Work Mode Lights",
      "mainwin.light.perLed.btn1Aria": "Button 1 lighting",
      "mainwin.light.perLed.btn2Aria": "Button 2 lighting",
      "mainwin.light.perLed.btn3Aria": "Button 3 lighting",
      "mainwin.light.perLed.dialAria": "Dial lighting",
      "mainwin.led.solid": "Solid",
      "mainwin.led.breathe": "Breathing",
      "mainwin.mic.title": "Microphone",
      "mainwin.mic.enable": "Enabled",
      "mainwin.mic.enableAria": "Microphone on/off",
      "mainwin.mic.denoise": "Noise Reduction",
      "mainwin.mic.denoiseAria": "Noise reduction",
      "mainwin.denoise.off": "Off",
      "mainwin.denoise.low": "Low",
      "mainwin.denoise.mid": "Mid",
      "mainwin.denoise.high": "High",
      "mainwin.mic.gain": "Input Volume",
      "mainwin.sysmic.title": "System Microphone",

      "features.title": "Features",
      "features.f1.title": "Lives in the Menu Bar",
      "features.f1.desc": "A pure menu bar app — no Dock icon, no ⌘Tab entry. Click the icon to pop open the mini panel.",
      "features.f2.title": "Offline Shortcuts",
      "features.f2.desc": "Assign shortcuts to the 3 buttons and the dial's turn-left / turn-right / press. They're written into the device firmware and keep working offline.",
      "features.f3.title": "Media Keys",
      "features.f3.desc": "Mute, volume up/down, play/pause, previous/next track — routed through the device's fixed function channel, handled natively by macOS.",
      "features.f4.title": "Microphone Management",
      "features.f4.desc": "See and switch the system's default input device. Lock the default input to VibeKey — if another app steals it, it switches back automatically.",
      "features.f5.title": "Lighting Effects",
      "features.f5.desc": "Indicator light modes and three brightness levels — off, full, or work mode, with each light set to solid or breathing individually.",
      "features.f6.title": "Power Management",
      "features.f6.desc": "Adjustable standby and sleep durations, plus one-click device reboot.",
      "features.f7.title": "Multiple Profiles",
      "features.f7.desc": "Save configurations as profiles and add as many as you need — one for travel, one for the studio, one for home.",
      "features.f8.title": "Launch at Login",
      "features.f8.desc": "Starts automatically when you log into macOS — set it once and forget about it.",
      "features.f10.title": "Jump to Any App",
      "features.f10.desc": "A key switches straight to the app you pick, launching it if it isn't running. Works while the app is resident; rebind or unbind any time.",
      "features.f9.title": "Fully Self-Driven",
      "features.f9.desc": "HID I/O runs through IOKit. Zero runtime dependencies — nothing from the vendor is linked or redistributed.",

      "steps.title": "Get Started in 3 Steps",
      "steps.s1.title": "Download & Install",
      "steps.s1.desc": "Download the app, or install it with Homebrew.",
      "steps.s2.title": "Plug in VibeKey",
      "steps.s2.desc": "Connect via the 2.4G receiver. Please make sure not to run the official app and Open VibeKey at the same time, as they will conflict.",
      "steps.s3.title": "Configure in the Panel",
      "steps.s3.desc": "Assign shortcuts to buttons and the dial, set up lighting and microphone lock — configure once, works offline forever.",

      "privacy.title": "Runs Entirely Locally, No Network",
      "privacy.body": "Open VibeKey runs entirely offline: no network access, no data collection, no telemetry. All your configuration stays on your Mac.",
      "privacy.body2": "The driver is fully self-implemented: HID communication runs through IOKit. At runtime it contains no JS / Node / browser, and links or redistributes nothing from the vendor.",
      "nav.github": "View OpenVibeKey on GitHub",

      "footer.disclaimer": "Open VibeKey is an independent, community-built open-source tool — not affiliated with Ulanzi or Kehwin.",
      "footer.github": "GitHub",
      "footer.license": "License",
      "footer.feedback": "Feedback"
    }
  };

  var currentLang = "zh";

  /* ------------------------------------------------------------------
   * 2. 语言切换
   * ------------------------------------------------------------------ */
  function applyLanguage(lang) {
    var dict = I18N[lang] || I18N.zh;
    currentLang = lang;

    document.documentElement.lang = lang === "en" ? "en" : "zh-CN";
    if (dict["meta.title"]) {
      document.title = dict["meta.title"];
    }

    // 普通文本节点
    var nodes = document.querySelectorAll("[data-i18n]");
    for (var i = 0; i < nodes.length; i++) {
      var key = nodes[i].getAttribute("data-i18n");
      if (dict[key] !== undefined) {
        nodes[i].textContent = dict[key];
      }
    }

    // aria-label 属性
    var ariaNodes = document.querySelectorAll("[data-i18n-aria]");
    for (var j = 0; j < ariaNodes.length; j++) {
      var ariaKey = ariaNodes[j].getAttribute("data-i18n-aria");
      if (dict[ariaKey] !== undefined) {
        ariaNodes[j].setAttribute("aria-label", dict[ariaKey]);
      }
    }

    // 图片 alt 文案（比如设备照片）
    var altNodes = document.querySelectorAll("[data-i18n-alt]");
    for (var m = 0; m < altNodes.length; m++) {
      var altKey = altNodes[m].getAttribute("data-i18n-alt");
      if (dict[altKey] !== undefined) {
        altNodes[m].setAttribute("alt", dict[altKey]);
      }
    }

    // 语言切换按钮的高亮态
    var langBtns = document.querySelectorAll(".lang-btn");
    for (var k = 0; k < langBtns.length; k++) {
      var isActive = langBtns[k].getAttribute("data-lang") === lang;
      langBtns[k].classList.toggle("is-active", isActive);
      langBtns[k].setAttribute("aria-pressed", isActive ? "true" : "false");
    }

    // 配置切换当前显示的文案（迷你面板下拉 + 主界面顶栏镜像）也要跟着换语言
    updateProfileLabels();

    // 快捷键行的"静音/解除静音"文案、假菜单栏的星期文案，也要跟着换语言
    renderAllShortcutRows();
    updateMenubarClock();
  }

  function initLangSwitch() {
    var langBtns = document.querySelectorAll(".lang-btn");
    for (var i = 0; i < langBtns.length; i++) {
      langBtns[i].addEventListener("click", function () {
        var lang = this.getAttribute("data-lang");
        if (lang !== currentLang) {
          applyLanguage(lang);
        }
      });
    }
  }

  /* ------------------------------------------------------------------
   * 3. 安装命令复制
   * ------------------------------------------------------------------ */
  function initCopyButton() {
    var copyBtn = document.getElementById("copy-btn");
    var cmdEl = document.getElementById("brew-cmd");
    var feedback = document.getElementById("copy-feedback");
    var label = document.getElementById("copy-btn-label");
    var iconCopy = copyBtn.querySelector(".icon-copy");
    var iconCheck = copyBtn.querySelector(".icon-check");
    var feedbackTimer = null;

    function showCopied() {
      var dict = I18N[currentLang] || I18N.zh;
      copyBtn.classList.add("is-copied");
      // 用 toggleAttribute 而不是 .hidden = ，因为这两个是 <svg>：部分浏览器的
      // SVGElement 并不反射 hidden 这个 IDL 属性到内容属性上（div/button 等
      // HTMLElement 才行），直接赋值 .hidden 不会真的加上 hidden="" 属性，
      // CSS 的 svg[hidden] 选择器就永远命中不了，图标会一直叠在一起。
      iconCopy.toggleAttribute("hidden", true);
      iconCheck.toggleAttribute("hidden", false);
      feedback.classList.add("is-shown");
      // 按钮上的文字标签也跟着切成"已复制"，与语言切换一样通过重写 data-i18n
      // 保证切换语言时能正确重新翻译（参考 renderShortcutRow 里"未设置"的写法）。
      label.setAttribute("data-i18n", "hero.brew.copied");
      label.textContent = dict["hero.brew.copied"];

      clearTimeout(feedbackTimer);
      feedbackTimer = setTimeout(function () {
        var currentDict = I18N[currentLang] || I18N.zh;
        copyBtn.classList.remove("is-copied");
        iconCopy.toggleAttribute("hidden", false);
        iconCheck.toggleAttribute("hidden", true);
        feedback.classList.remove("is-shown");
        label.setAttribute("data-i18n", "hero.brew.copyLabel");
        label.textContent = currentDict["hero.brew.copyLabel"];
      }, 1600);
    }

    function fallbackCopy(text) {
      var textarea = document.createElement("textarea");
      textarea.value = text;
      textarea.setAttribute("readonly", "");
      textarea.style.position = "fixed";
      textarea.style.top = "-1000px";
      textarea.style.opacity = "0";
      document.body.appendChild(textarea);
      textarea.select();
      textarea.setSelectionRange(0, textarea.value.length);
      try {
        document.execCommand("copy");
      } catch (err) {
        /* 复制失败时静默处理，不打断用户 */
      }
      document.body.removeChild(textarea);
    }

    copyBtn.addEventListener("click", function () {
      var text = cmdEl.textContent.trim();

      if (navigator.clipboard && navigator.clipboard.writeText) {
        navigator.clipboard.writeText(text).then(showCopied, function () {
          // 部分浏览器在 file:// 下会拒绝 Clipboard API，回退到 execCommand
          fallbackCopy(text);
          showCopied();
        });
      } else {
        fallbackCopy(text);
        showCopied();
      }
    });
  }

  /* ------------------------------------------------------------------
   * 4. 模拟菜单栏面板：设备切换 / 麦克风锁定 / 配置切换 / 其余假交互
   * ------------------------------------------------------------------ */
  var panelState = {
    currentDevice: 0, // 当前默认输入设备的下标
    lockedDevice: null, // 被锁定的设备下标，null 表示未锁定
    profileKey: "demo.profile.default"
  };

  function renderPanel() {
    var rows = document.querySelectorAll(".device-row");
    rows.forEach(function (row) {
      var idx = Number(row.getAttribute("data-device"));
      var isCurrent = idx === panelState.currentDevice;
      var isLocked = idx === panelState.lockedDevice;

      row.classList.toggle("is-current", isCurrent);
      row.classList.toggle("is-locked", isLocked);

      var lockBtn = row.querySelector(".lock-btn");
      setLockIconState(lockBtn, isLocked);
    });
  }

  function setLockIconState(lockBtn, locked) {
    if (!lockBtn) return;
    var openIcon = lockBtn.querySelector(".lock-open");
    var closedIcon = lockBtn.querySelector(".lock-closed");
    // 同上：<svg> 上直接赋值 .hidden 在部分浏览器里不反射到 hidden="" 属性，
    // 改用 toggleAttribute 确保属性真的加上/去掉，配合 style.css 的
    // svg[hidden]{display:none} 才能真正切出单一图标。
    openIcon.toggleAttribute("hidden", locked);
    closedIcon.toggleAttribute("hidden", !locked);
  }

  function initDeviceRows() {
    var rows = document.querySelectorAll(".device-row");

    rows.forEach(function (row) {
      var idx = Number(row.getAttribute("data-device"));

      function selectDevice() {
        panelState.currentDevice = idx;
        renderPanel();
      }

      row.addEventListener("click", selectDevice);
      row.addEventListener("keydown", function (e) {
        if (e.key === "Enter" || e.key === " ") {
          e.preventDefault();
          selectDevice();
        }
      });

      var lockBtn = row.querySelector(".lock-btn");
      lockBtn.addEventListener("click", function (e) {
        e.stopPropagation(); // 不触发行的选中逻辑之外的重复渲染
        if (panelState.lockedDevice === idx) {
          panelState.lockedDevice = null;
        } else {
          panelState.lockedDevice = idx;
          panelState.currentDevice = idx; // 锁定即视为切到该设备
        }
        renderPanel();
      });
    });
  }

  function initRefreshButton() {
    // 页面里现在有多处"刷新设备列表"按钮（迷你面板 / 未来可能的更多实例），逐个绑定
    var refreshBtns = document.querySelectorAll(".refresh-btn");
    refreshBtns.forEach(function (refreshBtn) {
      refreshBtn.addEventListener("click", function () {
        refreshBtn.classList.remove("is-spinning");
        // 强制回流以便重新触发动画
        void refreshBtn.offsetWidth;
        refreshBtn.classList.add("is-spinning");
      });
    });
  }

  // 配置名在页面上有两处镜像：迷你面板的下拉按钮 + 主界面顶栏的只读标签，
  // 二者共享同一个 profileKey，统一用 .profile-value 类选中一起更新
  function updateProfileLabels() {
    var dict = I18N[currentLang] || I18N.zh;
    var labels = document.querySelectorAll(".profile-value");
    labels.forEach(function (label) {
      if (dict[panelState.profileKey] !== undefined) {
        label.textContent = dict[panelState.profileKey];
        label.setAttribute("data-i18n", panelState.profileKey);
      }
    });
  }

  function initProfilePicker() {
    var btn = document.getElementById("profile-btn");
    var menu = document.getElementById("profile-menu");
    var options = menu.querySelectorAll(".profile-option");

    function closeMenu() {
      menu.hidden = true;
    }

    btn.addEventListener("click", function (e) {
      e.stopPropagation();
      menu.hidden = !menu.hidden;
    });

    options.forEach(function (opt) {
      opt.addEventListener("click", function () {
        panelState.profileKey = opt.getAttribute("data-i18n");
        updateProfileLabels();
        closeMenu();
      });
    });

    document.addEventListener("click", function (e) {
      if (!menu.hidden && !menu.contains(e.target) && e.target !== btn) {
        closeMenu();
      }
    });

    document.addEventListener("keydown", function (e) {
      if (e.key === "Escape") {
        closeMenu();
      }
    });
  }

  /* ------------------------------------------------------------------
   * 5. 主界面模拟：快捷键行（修饰键 + 主键弹出框 + 清除）/ 灯效分段控件 / 麦克风开关与音量
   * ------------------------------------------------------------------ */

  // 每行的初始示例数据：修饰键 + 主键 token。主键 token 对应 MAIN_KEY_LABELS
  // 里的一条（照抄真实 App VibeKitApp.swift 的 MAIN_KEYS 清单），渲染时按 token
  // 查表得到当前语言下的文案——这样下拉里选的 token 和这里的初始值是同一套数据。
  var SHORTCUT_ROWS = {
    dialLeft: { mods: ["cmd"], keyToken: "Left" },
    dialRight: { mods: ["cmd"], keyToken: "Right" },
    dialPress: { mods: [], keyToken: "App:WeChat" },
    btn1: { mods: ["cmd"], keyToken: "." },
    btn2: { mods: [], keyToken: "Enter" },
    btn3: { mods: [], keyToken: "Esc" }
  };

  // 主键弹出下拉的完整选项表：字母 / 数字 / 功能键 / 方向键 / 编辑键 / 符号 / 媒体键，
  // 顺序和取值照抄 native/VibeKit/Sources/VibeKitApp/VibeKitApp.swift 的 MAIN_KEYS。
  // label 是中英文一致的字面量（符号、字母、数字等）；i18n / shortI18n 指向字典 key，
  // 用于需要跟着语言切换文案的项（空格、静音、媒体键）。这份表和 index.html 里
  // #key-popover-list 的 74 个选项按同一份数据生成，token 一一对应。
  var MAIN_KEY_LABELS = {
    "A": { label: "A" },
    "B": { label: "B" },
    "C": { label: "C" },
    "D": { label: "D" },
    "E": { label: "E" },
    "F": { label: "F" },
    "G": { label: "G" },
    "H": { label: "H" },
    "I": { label: "I" },
    "J": { label: "J" },
    "K": { label: "K" },
    "L": { label: "L" },
    "M": { label: "M" },
    "N": { label: "N" },
    "O": { label: "O" },
    "P": { label: "P" },
    "Q": { label: "Q" },
    "R": { label: "R" },
    "S": { label: "S" },
    "T": { label: "T" },
    "U": { label: "U" },
    "V": { label: "V" },
    "W": { label: "W" },
    "X": { label: "X" },
    "Y": { label: "Y" },
    "Z": { label: "Z" },
    "1": { label: "1" },
    "2": { label: "2" },
    "3": { label: "3" },
    "4": { label: "4" },
    "5": { label: "5" },
    "6": { label: "6" },
    "7": { label: "7" },
    "8": { label: "8" },
    "9": { label: "9" },
    "0": { label: "0" },
    "F1": { label: "F1" },
    "F2": { label: "F2" },
    "F3": { label: "F3" },
    "F4": { label: "F4" },
    "F5": { label: "F5" },
    "F6": { label: "F6" },
    "F7": { label: "F7" },
    "F8": { label: "F8" },
    "F9": { label: "F9" },
    "F10": { label: "F10" },
    "F11": { label: "F11" },
    "F12": { label: "F12" },
    "Left": { label: "←" },
    "Right": { label: "→" },
    "Up": { label: "↑" },
    "Down": { label: "↓" },
    "Space": { i18n: "mainwin.key.space" },
    "Enter": { label: "⏎" },
    "Esc": { label: "Esc" },
    "Tab": { label: "⇥" },
    "Delete": { label: "⌦" },
    "Backspace": { label: "⌫" },
    "-": { label: "-" },
    "=": { label: "=" },
    "[": { label: "[" },
    "]": { label: "]" },
    ";": { label: ";" },
    "'": { label: "'" },
    ",": { label: "," },
    ".": { label: "." },
    "/": { label: "/" },
    "`": { label: "`" },
    "Mute": { i18n: "mainwin.key.mute", shortI18n: "mainwin.key.muteShort" },
    // 「打开 App」不是设备键：设备里烧的是一个罕见哨兵组合键，App 常驻时截获它再激活目标。
    // 这里只做演示用的展示映射，full 带「打开 App：」前缀，short 只放 App 名。
    "App:WeChat": { i18n: "mainwin.key.appWeChatFull", shortI18n: "mainwin.key.appWeChat" },
    "App:Safari": { i18n: "mainwin.key.appSafariFull", shortI18n: "mainwin.key.appSafari" },
    "App:Notes": { i18n: "mainwin.key.appNotesFull", shortI18n: "mainwin.key.appNotes" },
    "App:Terminal": { i18n: "mainwin.key.appTerminalFull", shortI18n: "mainwin.key.appTerminal" },
    "VolumeUp": { i18n: "mainwin.key.volumeUp" },
    "VolumeDown": { i18n: "mainwin.key.volumeDown" },
    "PlayPause": { i18n: "mainwin.key.playPause" },
    "NextTrack": { i18n: "mainwin.key.nextTrack" },
    "PrevTrack": { i18n: "mainwin.key.prevTrack" }
  };

  // 主键 token -> 当前语言下的 {full, short} 文案。full 用于行顶部的「⌘+←」展示，
  // short 用于弹出框主键面里的紧凑文案；两者大多相同，只有「静音/解除静音」这种
  // 长文案才会用 shortI18n 单独给出缩写版（跟原来的写死数据行为一致）。
  function resolveKeyLabels(token, dict) {
    var entry = MAIN_KEY_LABELS[token];
    if (!entry) return { full: token, short: token };
    var full = entry.i18n ? dict[entry.i18n] : entry.label;
    var short = entry.shortI18n ? dict[entry.shortI18n] : full;
    return { full: full, short: short };
  }

  // 修饰键在多键组合里的固定拼接顺序，跟 macOS 菜单里的 ⌃⌥⇧⌘ 惯例一致
  var MODIFIER_ORDER = ["ctrl", "opt", "shift", "cmd"];
  var MODIFIER_SYMBOLS = { cmd: "⌘", opt: "⌥", shift: "⇧", ctrl: "⌃" };

  var shortcutState = {}; // 运行时状态（可变），初始值来自 SHORTCUT_ROWS 的深拷贝

  function renderShortcutRow(rowEl, state) {
    var dict = I18N[currentLang] || I18N.zh;

    var modBtns = rowEl.querySelectorAll(".modifier-key");
    modBtns.forEach(function (btn) {
      var isActive = state.mods.indexOf(btn.getAttribute("data-mod")) !== -1;
      btn.classList.toggle("is-active", isActive);
      btn.setAttribute("aria-pressed", isActive ? "true" : "false");
    });

    rowEl.classList.toggle("is-cleared", state.cleared);

    var valueEl = rowEl.querySelector('[data-role="key-value"]');
    var displayEl = rowEl.querySelector('[data-role="display"]');

    if (state.cleared) {
      valueEl.textContent = "—";
      valueEl.classList.add("is-empty");
      displayEl.textContent = dict["mainwin.notSet"];
      displayEl.classList.add("is-empty");
      return;
    }

    valueEl.classList.remove("is-empty");
    displayEl.classList.remove("is-empty");

    var labels = resolveKeyLabels(state.keyToken, dict);
    valueEl.textContent = labels.short;

    var activeSymbols = MODIFIER_ORDER.filter(function (m) {
      return state.mods.indexOf(m) !== -1;
    }).map(function (m) {
      return MODIFIER_SYMBOLS[m];
    });
    var prefix = activeSymbols.length ? activeSymbols.join("") + "+" : "";
    displayEl.textContent = prefix + labels.full;
  }

  function renderAllShortcutRows() {
    document.querySelectorAll(".shortcut-row").forEach(function (rowEl) {
      var id = rowEl.getAttribute("data-shortcut");
      if (shortcutState[id]) {
        renderShortcutRow(rowEl, shortcutState[id]);
      }
    });
    // 语言切换时，若下拉正巧还开着，里面的勾选态文案也得跟着刷新
    if (activeKeyPopoverRow) {
      updateKeyPopoverSelection(activeKeyPopoverRow);
    }
  }

  // 点修饰键方块切换选中/未选中（右上角快捷键展示实时更新）；点「清除」清空整行
  // （修饰键全部取消、主键置空、右上角变成"未设置"）。清空后修饰键方块暂时不可点——
  // 现实产品里重新绑定要走真实的按键捕获流程，不是靠点这几个方块拼出来的。
  // 点主键弹出框可以重新打开下拉选主键：选中后自动解除"未设置"状态。
  function initShortcutRows() {
    var rows = document.querySelectorAll(".shortcut-row");

    rows.forEach(function (rowEl) {
      var id = rowEl.getAttribute("data-shortcut");
      var base = SHORTCUT_ROWS[id];
      if (!base) return;

      shortcutState[id] = {
        mods: base.mods.slice(),
        keyToken: base.keyToken,
        cleared: false
      };

      rowEl.querySelectorAll(".modifier-key").forEach(function (btn) {
        btn.addEventListener("click", function () {
          var state = shortcutState[id];
          if (state.cleared) return;
          var mod = btn.getAttribute("data-mod");
          var idx = state.mods.indexOf(mod);
          if (idx === -1) {
            state.mods.push(mod);
          } else {
            state.mods.splice(idx, 1);
          }
          renderShortcutRow(rowEl, state);
        });
      });

      var clearBtn = rowEl.querySelector(".clear-btn");
      if (clearBtn) {
        clearBtn.addEventListener("click", function () {
          var state = shortcutState[id];
          state.cleared = true;
          state.mods = [];
          renderShortcutRow(rowEl, state);
        });
      }

      var keySelectBtn = rowEl.querySelector(".key-select");
      if (keySelectBtn) {
        keySelectBtn.addEventListener("click", function () {
          toggleKeyPopover(id, keySelectBtn);
        });
        keySelectBtn.addEventListener("keydown", function (e) {
          if (e.key === "ArrowDown" || e.key === "ArrowUp") {
            e.preventDefault();
            if (!keyPopoverEl.hidden && activeKeyPopoverRow === id) return;
            openKeyPopover(id, keySelectBtn);
          }
        });
      }

      renderShortcutRow(rowEl, shortcutState[id]);
    });
  }

  /* ------------------------------------------------------------------
   * 5b. 主键弹出下拉：自定义浮层（非原生 <select>），仿 macOS 弹出菜单。
   * 全站只有一份 #key-popover DOM，谁点开就把它定位/填充到谁头上——
   * 这样天然保证"同一时刻只有一个下拉展开"。
   * ------------------------------------------------------------------ */
  var keyPopoverEl = null;
  var keyPopoverListEl = null;
  var activeKeyPopoverRow = null; // 当前展开的行 id，未展开时为 null
  var activeKeyPopoverTrigger = null; // 当前展开行对应的 .key-select 按钮

  function getKeyPopoverOptions() {
    return Array.prototype.slice.call(
      keyPopoverListEl.querySelectorAll(".key-popover-option")
    );
  }

  // 把「回车/勾选标记该显示在哪一项」同步成 shortcutState[rowId] 当前的主键 token，
  // 并把可聚焦项（roving tabindex）设到选中项上，方便下次打开直接停在当前值上。
  function updateKeyPopoverSelection(rowId) {
    var state = shortcutState[rowId];
    var currentToken = state && !state.cleared ? state.keyToken : null;
    var options = getKeyPopoverOptions();
    var matched = null;
    options.forEach(function (opt) {
      var isSelected = opt.getAttribute("data-token") === currentToken;
      opt.setAttribute("aria-selected", isSelected ? "true" : "false");
      opt.setAttribute("tabindex", "-1");
      if (isSelected) matched = opt;
    });
    var focusTarget = matched || options[0];
    if (focusTarget) focusTarget.setAttribute("tabindex", "0");
    return focusTarget;
  }

  // 定位浮层：position:fixed，按触发按钮的位置摆在下方；空间不够就翻到上方，
  // 左右都做视口内的收边处理，避免在窄屏或行尾触发时溢出屏幕。
  function positionKeyPopover(triggerEl) {
    var rect = triggerEl.getBoundingClientRect();
    var margin = 8;
    var vw = document.documentElement.clientWidth;
    var vh = document.documentElement.clientHeight;
    var width = Math.max(rect.width, 220);

    keyPopoverEl.style.visibility = "hidden";
    keyPopoverEl.hidden = false;
    keyPopoverEl.style.width = width + "px";
    keyPopoverEl.style.maxHeight = "320px";
    var naturalHeight = keyPopoverEl.offsetHeight;

    var spaceBelow = vh - rect.bottom - margin;
    var spaceAbove = rect.top - margin;
    var openAbove = spaceBelow < 160 && spaceAbove > spaceBelow;
    var maxHeight = Math.max(120, Math.min(320, openAbove ? spaceAbove : spaceBelow));
    keyPopoverEl.style.maxHeight = maxHeight + "px";

    var top = openAbove
      ? rect.top - Math.min(naturalHeight, maxHeight) - 6
      : rect.bottom + 6;
    var left = rect.left;
    if (left + width > vw - margin) left = vw - margin - width;
    if (left < margin) left = margin;
    if (top < margin) top = margin;

    keyPopoverEl.style.top = top + "px";
    keyPopoverEl.style.left = left + "px";
    keyPopoverEl.style.visibility = "";
  }

  function closeKeyPopover(refocusTrigger) {
    if (!activeKeyPopoverRow) return;
    var trigger = activeKeyPopoverTrigger;
    keyPopoverEl.hidden = true;
    if (trigger) {
      trigger.setAttribute("aria-expanded", "false");
      trigger.classList.remove("is-open");
      if (refocusTrigger) trigger.focus();
    }
    activeKeyPopoverRow = null;
    activeKeyPopoverTrigger = null;
  }

  function openKeyPopover(rowId, triggerEl) {
    if (activeKeyPopoverRow && activeKeyPopoverRow !== rowId) {
      closeKeyPopover(false);
    }
    activeKeyPopoverRow = rowId;
    activeKeyPopoverTrigger = triggerEl;
    var focusTarget = updateKeyPopoverSelection(rowId);
    positionKeyPopover(triggerEl);
    triggerEl.setAttribute("aria-expanded", "true");
    triggerEl.classList.add("is-open");
    if (focusTarget) focusTarget.focus();
  }

  function toggleKeyPopover(rowId, triggerEl) {
    if (activeKeyPopoverRow === rowId && !keyPopoverEl.hidden) {
      closeKeyPopover(true);
    } else {
      openKeyPopover(rowId, triggerEl);
    }
  }

  function selectMainKey(token) {
    if (!activeKeyPopoverRow) return;
    var rowId = activeKeyPopoverRow;
    var state = shortcutState[rowId];
    state.keyToken = token;
    state.cleared = false;
    var rowEl = document.querySelector('.shortcut-row[data-shortcut="' + rowId + '"]');
    if (rowEl) renderShortcutRow(rowEl, state);
    closeKeyPopover(true);
  }

  function moveKeyPopoverFocus(options, fromIndex, delta) {
    if (!options.length) return;
    var nextIndex = fromIndex + delta;
    if (nextIndex < 0) nextIndex = options.length - 1;
    if (nextIndex >= options.length) nextIndex = 0;
    options.forEach(function (opt, i) {
      opt.setAttribute("tabindex", i === nextIndex ? "0" : "-1");
    });
    options[nextIndex].focus();
  }

  function initKeyPopover() {
    keyPopoverEl = document.getElementById("key-popover");
    keyPopoverListEl = document.getElementById("key-popover-list");
    if (!keyPopoverEl || !keyPopoverListEl) return;

    getKeyPopoverOptions().forEach(function (opt) {
      opt.addEventListener("click", function () {
        selectMainKey(opt.getAttribute("data-token"));
      });
    });

    keyPopoverListEl.addEventListener("keydown", function (e) {
      var options = getKeyPopoverOptions();
      var currentIndex = options.indexOf(document.activeElement);

      if (e.key === "ArrowDown") {
        e.preventDefault();
        moveKeyPopoverFocus(options, currentIndex, 1);
      } else if (e.key === "ArrowUp") {
        e.preventDefault();
        moveKeyPopoverFocus(options, currentIndex, -1);
      } else if (e.key === "Home") {
        e.preventDefault();
        moveKeyPopoverFocus(options, 0, 0);
      } else if (e.key === "End") {
        e.preventDefault();
        moveKeyPopoverFocus(options, options.length - 1, 0);
      } else if (e.key === "Enter" || e.key === " ") {
        e.preventDefault();
        if (currentIndex >= 0) options[currentIndex].click();
      } else if (e.key === "Escape") {
        e.preventDefault();
        closeKeyPopover(true);
      } else if (e.key === "Tab") {
        // 不拦截 Tab 本身的默认走位，只是让浮层跟着关闭，避免残留在别的元素背后
        closeKeyPopover(false);
      }
    });

    // 点浮层和触发按钮以外的任何地方 → 关闭
    document.addEventListener("click", function (e) {
      if (!activeKeyPopoverRow) return;
      var trigger = activeKeyPopoverTrigger;
      if (keyPopoverEl.contains(e.target) || (trigger && trigger.contains(e.target))) return;
      closeKeyPopover(false);
    });

    // 全局 Esc 兜底（列表内部已经处理了一次，这里再兜一层防止焦点跑到别处）
    document.addEventListener("keydown", function (e) {
      if (e.key === "Escape" && activeKeyPopoverRow) {
        closeKeyPopover(true);
      }
    });

    // 窗口尺寸变化 / 页面滚动时，浮层的固定坐标会失效，直接收起更安全
    window.addEventListener("resize", function () {
      if (activeKeyPopoverRow) closeKeyPopover(false);
    });
    window.addEventListener(
      "scroll",
      function (e) {
        // 用键盘上下键滚动选项列表本身也会派发一次 scroll 事件（target 是
        // #key-popover-list），不能算"页面滚动"，不然一移动选中项弹层就被关掉了。
        if (!activeKeyPopoverRow || e.target === keyPopoverListEl) return;
        closeKeyPopover(false);
      },
      true
    );
  }

  // 灯效模式 / 亮度 / 工作模式各灯：分段控件，组内单选。
  // 与真实 App 的联动一致：亮度仅"全亮"模式可调，工作模式各灯仅"工作"模式可调，
  // 其余情况整段置灰（对应 vm.ledMode != 1 / vm.ledMode != 2）。
  function initLightingControls() {
    function bindSegmented(group) {
      var buttons = group.querySelectorAll(".segmented-btn");
      buttons.forEach(function (btn) {
        btn.addEventListener("click", function () {
          if (group.classList.contains("is-disabled")) return;
          buttons.forEach(function (b) {
            b.classList.toggle("is-active", b === btn);
          });
          if (group.id === "light-mode-group") {
            var mode = btn.getAttribute("data-mode");

            var brightnessGroup = document.getElementById("light-brightness-group");
            var brightnessEnabled = mode === "full"; // 仅「全亮」可调亮度
            brightnessGroup.classList.toggle("is-disabled", !brightnessEnabled);
            brightnessGroup.setAttribute("aria-disabled", brightnessEnabled ? "false" : "true");

            var perLedGroup = document.getElementById("led-perkey-group");
            if (perLedGroup) {
              var perLedEnabled = mode === "work"; // 仅「工作」模式可单独调各灯
              perLedGroup.classList.toggle("is-disabled", !perLedEnabled);
              perLedGroup.setAttribute("aria-disabled", perLedEnabled ? "false" : "true");
            }
          }
        });
      });
    }

    document.querySelectorAll(".segmented").forEach(bindSegmented);
  }

  // 麦克风开关 / 降噪：小型 switch 组件
  function initMicSwitches() {
    document.querySelectorAll(".switch[data-switch]").forEach(function (sw) {
      sw.addEventListener("click", function () {
        var isOn = !sw.classList.contains("is-on");
        sw.classList.toggle("is-on", isOn);
        sw.setAttribute("aria-checked", isOn ? "true" : "false");
      });
    });
  }

  // 收音音量滑块：拖动时实时更新旁边的数值
  function initMicSlider() {
    var slider = document.getElementById("mic-gain-slider");
    var value = document.getElementById("mic-gain-value");
    if (!slider || !value) return;
    slider.addEventListener("input", function () {
      value.textContent = slider.value;
    });
  }

  // 右上角菜单栏图标：点击展开 / 收起悬浮的迷你面板
  function initMenubarPopover() {
    var trigger = document.getElementById("menubar-trigger");
    var popover = document.getElementById("menu-popover");
    if (!trigger || !popover) return;

    // 显式初始化为展开状态，不依赖属性的隐式默认值——
    // 进页面第一眼应该同时看到主界面和菜单栏面板；点旋钮图标可收起/再展开。
    popover.hidden = false;
    trigger.setAttribute("aria-expanded", "true");

    trigger.addEventListener("click", function () {
      var willShow = popover.hidden;
      popover.hidden = !willShow;
      trigger.setAttribute("aria-expanded", willShow ? "true" : "false");
    });
  }

  // 假菜单栏的日期时间：显示真实时间，格式跟随语言（中文"周四 9:41"，英文"Thu 9:41"），
  // 每分钟刷新一次；切语言时星期文案也要跟着换，所以 applyLanguage 里也会调用它。
  function formatMenubarClock(date) {
    var locale = currentLang === "en" ? "en-US" : "zh-CN";
    var weekday = new Intl.DateTimeFormat(locale, { weekday: "short" }).format(date);
    var hours = date.getHours() % 12;
    if (hours === 0) hours = 12;
    var minutes = String(date.getMinutes()).padStart(2, "0");
    return weekday + " " + hours + ":" + minutes;
  }

  function updateMenubarClock() {
    var els = document.querySelectorAll(".mb-time");
    if (!els.length) return;
    var text = formatMenubarClock(new Date());
    els.forEach(function (el) {
      el.textContent = text;
    });
  }

  function initMenubarClock() {
    updateMenubarClock();
    setInterval(updateMenubarClock, 60000);
  }

  /* ------------------------------------------------------------------
   * 初始化
   * ------------------------------------------------------------------ */
  document.addEventListener("DOMContentLoaded", function () {
    initLangSwitch();
    initCopyButton();
    initDeviceRows();
    initRefreshButton();
    initProfilePicker();
    initKeyPopover();
    initShortcutRows();
    initLightingControls();
    initMicSwitches();
    initMicSlider();
    initMenubarPopover();
    initMenubarClock();

    applyLanguage("zh");
    renderPanel();
  });
})();
