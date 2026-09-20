### 编译

使用NDK编译getifaddrs_bridge_server.c:

`aarch64-linux-android-clang getifaddrs_bridge_server.c -o getifaddrs_bridge_server`

在小小电脑上编译getifaddrs_bridge_client_lib.c:

`gcc getifaddrs_bridge_client_lib.c -o getifaddrs_bridge_client_lib.so -shared -fPIC -ldl`

### 使用

在安卓端:

`getifaddrs_bridge_server /path/to/container/tmp/.getifaddrs-bridge`

在proot容器：

`LD_PRELOAD=/path/to/getifaddrs_bridge_client_lib.so <your_program>`

### 健壮性约定（2026-09-20 修改后）

- 双方协议带帧头：`magic('TIF1') + 大端长度`，收发均按长度循环读写，短读/短写/截断一律判失败。
- 服务端是**单实例**的（`flock` 非阻塞锁，锁文件默认 `/tmp/.getifaddrs-bridge.lock`，
  可用环境变量 `TINY_BRIDGE_LOCK` 覆盖）。重复启动会直接退出，不会再残留孤儿进程。
- 服务端屏蔽 `SIGPIPE`，并设置 `PR_SET_PDEATHSIG`，父进程退出后自动收尸。
- socket 权限收紧为 `0600`；每条连接有 2 秒收发超时。
- 地址字段改为按地址族原样透传（AF_INET / AF_INET6 / AF_PACKET 完整长度），
  不再截断成 16 字节。
- 客户端在所有失败路径上**回退到 libc 的真实 `getifaddrs`**（`dlsym(RTLD_NEXT)`），
  不会再 `exit(1)` 杀掉调用它的程序；连接超时 3 秒。
- `ifa_data` 仍不透传（原行为），容器内 `ip -s link` 之类的统计信息依然为空。
