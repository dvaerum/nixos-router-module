# Run by pxe-boot-prepare-refresh.service when the ISO folder changed.
# PXE_BOOT_PREPARE and PXE_BOOT_CONFIG come from config-tftp.nix.

if systemctl is-active --quiet pxe-boot-prepare.service; then
  # Only what changed is touched: a client installing from an unchanged ISO
  # keeps its mount.
  exec "$PXE_BOOT_PREPARE" --config "$PXE_BOOT_CONFIG" refresh
fi

# Not running (failed earlier, or still starting): nothing is mounted that a
# refresh could preserve, so run the full preparation through its unit.
exec systemctl start pxe-boot-prepare.service
