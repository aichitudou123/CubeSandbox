# Guest Perf Metrics (GAUGE)

`--enable-metric` on `tpl create-from-image` bakes a GAUGE channel into the template: a 4 KiB ivshmem device (`subsystem_id=0x0101`) plus `cube_gauge.ext4` as the first business pmem. That ext4 ships with the install under `cube-kernel-scf/`. While building the template, CubeShim asks the guest agent to mount the image and, after the container cgroup exists, `insmod cube_gauge.ko`. Sandboxes restored from that template already have the module in the snapshot.

This is **not** the Cubelet Prometheus endpoint documented in [Sandbox Resource Metrics](./resource-metrics.md). That page covers host-side CPU and memory scrape. GAUGE is a guest↔host shared-memory device frozen into the MicroVM snapshot.

## When to enable it

Enable it only when you need the GAUGE guest driver and the host backing file:

```text
/run/vc/vm/<sandbox-id>/gauge.shmem
```

Leave the flag off for ordinary templates. A VM has a single ivshmem slot; turning the flag on occupies that slot for GAUGE (`0x0101`) instead of the older demo ivshmem.

The switch must be set **while building the template**. Restore can rebind backing files; it cannot add a PCI device that was not in the snapshot.

## How it works

```text
--enable-metric
  → cube.master.perf.metric=true     (CubeMaster)
  → cube.perf.metric=true            (Cubelet, OCI spec)
  → Config.perf_metric               (CubeShim)
  → ivshmem 4 KiB, subsystem_id=0x0101, /run/vc/vm/<id>/gauge.shmem
  → cube_gauge.ext4 as /dev/pmem2
  → agent mounts /dev/pmem2 at /run/cube-gauge
  → after the user container is created, agent insmod /run/cube-gauge/cube_gauge.ko
  → snapshot includes the loaded module
```

| Step | What happens |
| --- | --- |
| Template cold boot | If the flag is on, Shim attaches `cube_gauge.ext4` as `/dev/pmem2`. The agent mounts it at `/run/cube-gauge`. `insmod` waits until the user container exists — `cube_gauge` init needs cgroup files that are missing at `create_sandbox`. |
| Template snapshot | The ivshmem device, the extra pmem, and the loaded module are part of the MicroVM snapshot. |
| Create sandbox from the template | Restore rebinds the devices. No second `insmod`. |
| Pause / runtime-snapshot resume | No second `insmod`. |

If the flag is off, Shim does not attach the extra pmem and does not request `insmod`. The sandbox still starts.

`/run/cube-gauge` is a **guest-agent** mount. It is not visible inside the user container mount namespace. The loaded module is visible from the container through `/proc/modules` because the kernel is shared.

## Usage

Build a template with the flag:

```bash
cubemastercli tpl create-from-image \
  --image     ghcr.io/tencentcloud/cubesandbox-base:latest \
  --writable-layer-size 1G \
  --expose-port 49983 \
  --probe 49983 \
  --probe-path /health \
  --enable-metric
```

Wait until the template is `READY`, then create a sandbox from it as usual. You do not pass `--enable-metric` again on sandbox create.

After one-click install, the module image is already next to the guest kernel:

```text
/usr/local/services/cubetoolbox/cube-kernel-scf/cube_gauge.ext4
```

## How to verify

On the host, after a sandbox from the template is running:

```bash
ls -la /run/vc/vm/<sandbox-id>/gauge.shmem
```

While **building** the template, CubeShim logs (`/data/log/CubeShim/cube-shim-req.log`) should include:

```text
perf metric on: ask agent to insmod /run/cube-gauge/cube_gauge.ko during template create
```

Inside the user container (template-build VM or a sandbox restored from it):

```bash
grep cube_gauge /proc/modules
```

`ls /run/cube-gauge` inside the container is the wrong check. That path exists in the agent namespace, not in the container.

## When you must rebuild the template

| Situation | Rebuild? |
| --- | --- |
| Template already created with `--enable-metric` after this change | No. The snapshot already has the module. |
| Template created without `--enable-metric` | Yes. The snapshot has no GAUGE PCI device. |
| Older template that only mounted GAUGE and expected restore to `insmod` | Yes. Restore no longer loads the module. |

## Related pages

- [Create Templates from OCI Image](./tutorials/template-from-image.md) — CLI workflow; add `--enable-metric` to the create command.
- [Sandbox Resource Metrics](./resource-metrics.md) — Cubelet Prometheus CPU and memory scrape, a different pipeline.
- [Templates Troubleshooting](./troubleshooting/templates.md)
