#!/bin/sh
#
# $FreeBSD$

# PROVIDE: portacl
# REQUIRE: FILESYSTEMS
# BEFORE: SERVERS
# KEYWORD: nojail

. /etc/rc.subr

name="portacl"
desc="Network port access control policy"
rcvar="portacl_enable"
extra_commands="reload printrules"
start_precmd="portacl_check_sysctl_conf"
start_cmd="portacl_start"
restart_cmd="portacl_start"
reload_cmd="portacl_start"
stop_cmd="portacl_stop"
printrules_cmd="portacl_printrules"
required_modules="mac_portacl"

: "${portacl_enable:="NO"}"
: "${portacl_port_high:="1023"}"
: "${portacl_suser_exempt:="YES"}"
: "${portacl_autoport_exempt:="YES"}"
: "${portacl_users:=""}"
: "${portacl_groups:=""}"
: "${portacl_additional_rules:=""}"

# If the value is numeric, echo it, else return failure
echo_integer()
{
	case "${1}" in
	''|*[!0-9]*)
		return 1
		;;
	*)
		echo "${1}"
		return 0
		;;
	esac
}

# echo the value of the variable if it is a positive integer
# or print a warning and echo the value of the second argument
integer_or_default()
{
	local value

	eval "value=\$${1}"
	echo_integer "${value}" && return 0
	warn "\$${1} is not set properly, using default ${2} - see rc.conf(5)"
	echo "${2}"
}

# Split the argument on commas
split_comma()
{
	local rule
	local IFS=','
	for rule in $1
	do
		echo "${rule}"
	done
}

# Lookup port in /etc/services if it is not numeric
resolve_port()
{
	local lookup
	local port="$1"
	local proto="$2"

	echo_integer "${port}" && return

	case "${port}" in
	''|*[!a-z0-9_-]*)
		warn "invalid service name: ${port}"
		return 1
		;;
	*)
		;;
	esac

	lookup=$(awk -F'[/[:space:]]+' "
		/^${port}[\t ]+([0-9]+)\/${proto}/ {
			print \$2
			exit 0 
		}" /etc/services)

	if [ -z "${lookup}" ]; then
		warn "unknown service ${port}"
		return 1
	fi

	echo "${lookup}"
}

lookup_id() {
	local lookup
	local kind="$1"
	local ident="$2"
	local flag="-u"

	[ "${kind}" = "group" ] && flag="-g"

	echo_integer "${ident}" && return

	lookup=$(${ID} "${flag}" "${ident}" 2>/dev/null)

	if [ -z "${lookup}" ]; then
		warn "unknown ${kind} ${ident}"
		return
	fi

	echo "${lookup}"
}

list_rules_for()
{
	local id ident ident_list port port_list proto
	local kind="$1"
	local key="uid"

	[ "${kind}" = "group" ] && key="gid"

	eval ident_list="\${${name}_${kind}s}"
	for ident in ${ident_list}
	do
		for proto in tcp udp
		do
			eval port_list="\${${name}_${kind}_${ident}_${proto}}"
			id=$(lookup_id "${kind}" "${ident}")
			[ -z "${id}" ] && continue
			for port in ${port_list}
			do
				port=$(resolve_port "${port}" "${proto}")
				[ -z "${port}" ] && continue
				echo "${key}:${id}:${proto}:${port}"
			done
		done
	done
}

# list all rules, one per line
list_rules()
{
	list_rules_for user
	list_rules_for group
	[ -n "${portacl_additional_rules}" ] && split_comma "${portacl_additional_rules}"
}

# generate a complete, validated ruleset ready for mac_portacl
generate_rules()
{
	list_rules | sort -ut : | tr '\n' , | validate_rules
}

# Filter out invalid rules and warn on stderr
validate_rules()
{
	awk '
		BEGIN { RS=","; FS=":"; sep = "" }
		{
			if (NF == 4 &&
			    ($1 ~ /^(uid|gid)$/) &&
			    ($2 ~ /^[0-9]+$/ && $2 >= 0 && $2 <= 65535) &&
			    ($3 ~ /^(tcp|udp)$/) &&
			    ($4 ~ /^[0-9]+$/ && $4 >= 0 && $4 <= 65535)) 
			{
				printf("%s%s", sep, $0)
				sep=","
			} else {
				printf("WARNING: Invalid portacl rule: %s\n", $0) > "/dev/stderr"
			}
		}
	'
}

portacl_printrules()
{
	generate_rules
	echo
}

portacl_check_sysctl_conf()
{
	local f overrides oid

	for f in /etc/sysctl.conf /etc/sysctl.conf.local
	do
		[ -r "${f}" ] || continue

		overrides="$(awk -F= '
			BEGIN { ORS=" " } 
			$1 ~ /^(security\.mac\.portacl\.|net\.inet\.ip\.portrange\.reserved)/ {
				print $1
			}
		' "${f}")"

		for oid in $overrides
		do
			warn "overriding ${oid} in ${f}"
		done
	done
}

portacl_start()
{
	local rules="$(generate_rules)"
	local port_high="$(integer_or_default portacl_port_high 1023)"
	local suser_exempt=1
	local autoport_exempt=1

	checkyesno portacl_suser_exempt || suser_exempt=0
	checkyesno portacl_autoport_exempt || autoport_exempt=0

	${SYSCTL} security.mac.portacl.rules="${rules}" >/dev/null &&
	${SYSCTL} security.mac.portacl.suser_exempt="${suser_exempt}" >/dev/null &&
	${SYSCTL} security.mac.portacl.autoport_exempt="${autoport_exempt}" >/dev/null &&
	${SYSCTL} security.mac.portacl.port_high="${port_high}" >/dev/null &&
	${SYSCTL} security.mac.portacl.enabled=1 >/dev/null &&
	${SYSCTL} net.inet.ip.portrange.reservedlow=0 >/dev/null &&
	${SYSCTL} net.inet.ip.portrange.reservedhigh=0 >/dev/null
}

portacl_stop()
{
	${SYSCTL} net.inet.ip.portrange.reservedlow=0 >/dev/null &&
	${SYSCTL} net.inet.ip.portrange.reservedhigh=1023 >/dev/null &&
	${SYSCTL} security.mac.portacl.enabled=0 >/dev/null
}

load_rc_config $name
run_rc_command "$1"
