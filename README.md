# `portacl`

A FreeBSD rc(8) script for mac_portacl(4)

## Description

mac_portacl(4) is a kernel module which provides an access control policy
to permit given users and groups to bind to otherwise privileged ports only
accessible to the superuser.

Typical configuration looks like this:

`/boot/loader.conf`:

```sh
mac_portacl_load="YES"
```

`/etc/sysctl.conf`:

```sh
# Disable standard root-only access check
net.inet.ip.portrange.reservedhigh=0

# Permit uid 80 to bind ports http and https
security.mac.portacl.rules="uid:80:tcp:80,uid:80:tcp:443"
```

This script replaces it with a more convenient interface:

`/etc/rc.conf`:

```sh
portacl_enable="YES"
portacl_users="www"
portacl_user_www_tcp="http https"
```

Access controls for groups, numeric user IDs and ports work as you would
expect, and additional verbatim rules can also be specified.

## Usage

If you can't work that out for yourself and deal with any fallout if it does
anything bad, don't.

## Status

It works on my machine.

