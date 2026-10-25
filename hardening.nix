{ ... }:

{
  # no kexec or /dev/mem writes into the running kernel. also blocks
  # hibernation, which boot.nix turns off anyway.
  security.protectKernelImage = true;

  boot.kernel.sysctl = {
    # kernel pointers and the kernel log are for root only
    "kernel.kptr_restrict" = 2;
    "kernel.dmesg_restrict" = 1;
    # BPF programs need root; harden the JIT that runs them
    "kernel.unprivileged_bpf_disabled" = 1;
    "net.core.bpf_jit_harden" = 2;
    # a process may only ptrace its own children (gdb attach needs sudo)
    "kernel.yama.ptrace_scope" = 1;
    # no core dumps from setuid programs
    "fs.suid_dumpable" = 0;
    # stricter version of the systemd defaults for files in sticky dirs
    "fs.protected_fifos" = 2;
    "fs.protected_regular" = 2;
    # users can't load tty line disciplines, a common exploit path
    "dev.tty.ldisc_autoload" = 0;
    # a desktop isn't a router: ignore redirects and source routing
    "net.ipv4.conf.all.accept_redirects" = 0;
    "net.ipv4.conf.default.accept_redirects" = 0;
    "net.ipv4.conf.all.secure_redirects" = 0;
    "net.ipv4.conf.default.secure_redirects" = 0;
    "net.ipv6.conf.all.accept_redirects" = 0;
    "net.ipv6.conf.default.accept_redirects" = 0;
    "net.ipv4.conf.all.send_redirects" = 0;
    "net.ipv4.conf.default.send_redirects" = 0;
    "net.ipv4.conf.all.accept_source_route" = 0;
    "net.ipv6.conf.all.accept_source_route" = 0;
  };

  # rarely used network protocols with a history of kernel bugs. blacklisting
  # stops socket() from autoloading them; modprobe by hand still works.
  boot.blacklistedKernelModules = [
    "dccp"
    "sctp"
    "rds"
    "tipc"
  ];
}
