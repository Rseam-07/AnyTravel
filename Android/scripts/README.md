# Android 12 / Xperia 闪退采集

连接一台已打开 USB 调试的设备，安装待测 APK 后运行：

```bash
./scripts/capture-xperia-crash.sh
```

脚本会清空旧日志、冷启动 `cn.anytravel.app`，只采集 Android Runtime、MapLibre、OpenGL、Surface 与 Activity 管理器相关日志。复现问题后回到终端按回车，结果会写入本地 `Android/diagnostics/`，该目录已被 Git 忽略。它还会保存 Android 版本、机型、ABI、应用版本、退出原因和内存快照，但不会读取账户、密钥或其他应用的数据。

若 `adb` 不在 `PATH`，可显式指定：

```bash
ANYTRAVEL_ADB=/path/to/platform-tools/adb ./scripts/capture-xperia-crash.sh
```
