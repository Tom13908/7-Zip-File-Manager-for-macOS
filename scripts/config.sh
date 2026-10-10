# 构建参数的唯一出处。
#
# MIN_OS 必须同时满足三处，缺一处就会出问题：
#   * 两个架构切片的 LC_BUILD_VERSION minos
#   * 引擎 7zz 的 minos
#   * Info.plist 的 LSMinimumSystemVersion
# 声明得比切片低：LaunchServices 放行，dyld 随后拒绝加载，用户看到的是崩溃；
# 声明得比切片高：本来能跑的机器被挡在门外。
#
# 为什么是 13.0：x86_64 切片在当前工具链下无法链接到 13.0 以下 ——
# CommandLineTools 的 libswiftCompatibility56.a / ...Concurrency.a 只有 arm64 切片，
# 而编译器对低于 13.0 的目标会强制加载它们（见 scripts/build-app.sh 的说明）。
MIN_OS=13.0
export MIN_OS
