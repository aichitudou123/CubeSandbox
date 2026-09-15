# 客户机性能指标（GAUGE）

在 `tpl create-from-image` 上加 `--enable-metric`，会把 GAUGE 通道打进模板：一块 4 KiB 的 ivshmem（`subsystem_id=0x0101`），以及作为第一块业务 pmem 的 `cube_gauge.ext4`。这份 ext4 随安装包放在 `cube-kernel-scf/` 下。做模板时 CubeShim 让 guest agent mount 这份镜像，等容器 cgroup 起来后再 `insmod cube_gauge.ko`。从该模板 restore 的沙箱里模块已经在快照中。

这和 [沙箱资源指标](./resource-metrics.md) 不是同一条链路。那篇是 Cubelet 在宿主机上的 Prometheus CPU / 内存抓取。GAUGE 是打进 MicroVM 快照的 guest↔host 共享内存设备。

## 什么时候开

只有需要 GAUGE 客户机驱动和宿主机 backing 文件时才开：

```text
/run/vc/vm/<sandbox-id>/gauge.shmem
```

普通模板不要加这个开关。一台 VM 只有一个 ivshmem 槽；打开后该槽给 GAUGE（`0x0101`），不再给原来的 demo ivshmem。

开关必须在**做模板**时打开。restore 只能重绑 backing 文件，不能给快照里没有的 PCI 设备补槽。

## 做了什么

```text
--enable-metric
  → cube.master.perf.metric=true     （CubeMaster）
  → cube.perf.metric=true            （Cubelet，写入 OCI spec）
  → Config.perf_metric               （CubeShim）
  → ivshmem 4 KiB，subsystem_id=0x0101，/run/vc/vm/<id>/gauge.shmem
  → 把 cube_gauge.ext4 挂成 /dev/pmem2
  → agent 把 /dev/pmem2 挂到 /run/cube-gauge
  → 用户容器创建之后，agent insmod /run/cube-gauge/cube_gauge.ko
  → 快照包含已加载的模块
```

| 步骤 | 行为 |
| --- | --- |
| 做模板冷启 | 有开关时，Shim 把 `cube_gauge.ext4` 挂成 `/dev/pmem2`，agent 再 mount 到 `/run/cube-gauge`。`insmod` 等到用户容器起来再做：`create_sandbox` 时 cgroup 文件还没有，`cube_gauge` init 会失败。 |
| 模板快照 | ivshmem、这块 pmem、以及已加载的模块打进 MicroVM 快照。 |
| 从模板创建沙箱 | restore 重绑设备。不再二次 insmod。 |
| Pause / runtime-snapshot 恢复 | 不再二次 insmod。 |

没开开关：不挂这块 pmem、不请求 insmod，沙箱照常启动。

`/run/cube-gauge` 在 **guest agent** 命名空间，用户容器里看不到。模块装上后，容器里可以通过 `/proc/modules` 看到，因为内核是共享的。

## 用法

做模板时加上开关：

```bash
cubemastercli tpl create-from-image \
  --image     ghcr.io/tencentcloud/cubesandbox-base:latest \
  --writable-layer-size 1G \
  --expose-port 49983 \
  --probe 49983 \
  --probe-path /health \
  --enable-metric
```

等到模板 `READY`，再按平常方式从模板起沙箱。创建沙箱时不用再传 `--enable-metric`。

一键安装完成后，模块镜像已经和 guest 内核放在一起：

```text
/usr/local/services/cubetoolbox/cube-kernel-scf/cube_gauge.ext4
```

## 怎么确认

从该模板起的沙箱起来后，在宿主机：

```bash
ls -la /run/vc/vm/<sandbox-id>/gauge.shmem
```

**做模板**时 CubeShim 日志（`/data/log/CubeShim/cube-shim-req.log`）里应有：

```text
perf metric on: ask agent to insmod /run/cube-gauge/cube_gauge.ko during template create
```

在用户容器里（做模板那次 VM，或从该模板 restore 的沙箱）：

```bash
grep cube_gauge /proc/modules
```

容器里 `ls /run/cube-gauge` 不是正确检查方式。那个路径在 agent 命名空间，不在容器里。

## 什么时候必须重做模板

| 情况 | 要重做吗 |
| --- | --- |
| 做模板时已经带 `--enable-metric`（本改动之后打的） | 不用。快照里已有模块。 |
| 做模板时没加 `--enable-metric` | 要。快照里没有 GAUGE PCI 设备。 |
| 旧模板只 mount 了 GAUGE、指望 restore 再 insmod | 要。restore 不再装模块。 |

## 相关文档

- [从 OCI 镜像制作模板](./tutorials/template-from-image.md) — CLI 流程；在创建命令里加 `--enable-metric`。
- [沙箱资源指标](./resource-metrics.md) — Cubelet 的 Prometheus CPU / 内存抓取，另一条链路。
- [模板问题](./troubleshooting/templates.md)
