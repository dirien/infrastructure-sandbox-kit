# syntax=docker/dockerfile:1
# The overlay this mixin adds to the claude workload: the runbooks, staged
# outside the home directory (the install hook seeds them into ~/runbooks).
# The toolchain itself installs at create time from scripts/, so it follows
# the workload's OS and architecture instead of being baked in here.
FROM scratch
COPY --chown=0:0 files/home/runbooks /opt/infrastructure-sandbox-kit/runbooks
