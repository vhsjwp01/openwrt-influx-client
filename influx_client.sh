#!/bin/bash
#set -x

PATH="/bin:/usr/bin:/usr/loacl/bin:/sbin:/usr/sbin:/usr/local/sbin"
TERM="vt100"
export TERM PATH

SUCCESS=0
ERROR=1

exit_code=${SUCCESS}

influxdb="telegraf"
influxdb_host="192.168.1.14"
influxdb_host_port="8086"

my_hostname=$(uci get system.@system[0].hostname)

x_wing_fighter=":=8o8=:"

# WHAT: Return multiplier to convert to bytes
f__unit_factor() {
    local units="${1}"
    multiplier="1"

    case ${units} in

        [kK][bB])
            multiplier="1024"
        ;;

        [mM][bB])
            multiplier="1024*1024"
        ;;

        [gG][bB])
            multiplier="1024*1024*1024"
        ;;

    esac

    echo "${multiplier}"
}

# WHAT: CPU Stat metrics
f__cpu_stat_metrics() {
    let return_code=${SUCCESS}

    local raw_cpu_lines=$(egrep "^cpu" /proc/stat 2> /dev/null | sed -e "s| |${x_wing_fighter}|g")
    
    for this_cpu_line in ${raw_cpu_lines} ; do 
        local raw_cpu_info=$(echo "${this_cpu_line}" | sed -e "s|${x_wing_fighter}| |g")
        local this_cpu=$(echo "${raw_cpu_info}" | awk '{print $1}')
        local cpu_instance=""

        if [ "${this_cpu}" = "cpu" ]; then
            cpu_instance="cpu-total"
        else
            cpu_instance="${this_cpu}"
        fi

        local series="cpu,cpu=${cpu_instance},host=${my_hostname}"

        local influx_payload=""
        local timestamp=$(date +%s)
        local timestamp_ns=$(echo "${timestamp}*1000000000" | bc)

    
        if [ ! -z "${raw_cpu_info}" ]; then
            local raw_usage_user=$(echo "${raw_cpu_info}" | awk '{print $2}')
            local raw_usage_nice=$(echo "${raw_cpu_info}" | awk '{print $3}')
            local raw_usage_system=$(echo "${raw_cpu_info}" | awk '{print $4}')
            local raw_usage_idle=$(echo "${raw_cpu_info}" | awk '{print $5}')
            local raw_usage_iowait=$(echo "${raw_cpu_info}" | awk '{print $6}')
            local raw_usage_irq=$(echo "${raw_cpu_info}" | awk '{print $7}')
            local raw_usage_softirq=$(echo "${raw_cpu_info}" | awk '{print $8}')
            local raw_usage_steal=$(echo "${raw_cpu_info}" | awk '{print $9}')
            local raw_usage_guest=$(echo "${raw_cpu_info}" | awk '{print $10}')
            local raw_usage_guest_nice=$(echo "${raw_cpu_info}" | awk '{print $11}')
            local total_clock_ticks=$(echo "${raw_usage_user}+${raw_usage_nice}+${raw_usage_system}+${raw_usage_idle}+${raw_usage_iowait}+${raw_usage_irq}+${raw_usage_softirq}+${raw_usage_steal}+${raw_usage_guest}+${raw_usage_guest_nice}" | bc)
            local usage_user=$(echo "scale=10;${raw_usage_user}/${total_clock_ticks}*100" | bc)
            local usage_nice=$(echo "scale=10;${raw_usage_nice}/${total_clock_ticks}*100" | bc)
            local usage_system=$(echo "scale=10;${raw_usage_system}/${total_clock_ticks}*100" | bc)
            local usage_idle=$(echo "scale=10;${raw_usage_idle}/${total_clock_ticks}*100" | bc)
            local usage_iowait=$(echo "scale=10;${raw_usage_iowait}/${total_clock_ticks}*100" | bc)
            local usage_irq=$(echo "scale=10;${raw_usage_irq}/${total_clock_ticks}*100" | bc)
            local usage_softirq=$(echo "scale=10;${raw_usage_softirq}/${total_clock_ticks}*100" | bc)
            local usage_steal=$(echo "scale=10;${raw_usage_steal}/${total_clock_ticks}*100" | bc)
            local usage_guest=$(echo "scale=10;${raw_usage_guest}/${total_clock_ticks}*100" | bc)
            local usage_guest_nice=$(echo "scale=10;${raw_usage_guest_nice}/${total_clock_ticks}*100" | bc)
    
            local influx_payload="usage_guest=${usage_guest},usage_guest_nice=${usage_guest_nice},usage_idle=${usage_idle},usage_iowait=${usage_iowait},usage_irq=${usage_irq},usage_nice=${usage_nice},usage_softirq=${usage_softirq},usage_steal=${usage_steal},usage_system=${usage_system},usage_user=${usage_user}"

            # Send computed metrics to influx
            eval "/bin/nice -19 curl -m 3 -s -i -XPOST 'http://${influxdb_host}:${influxdb_host_port}/write?db=${influxdb}' --data-binary '${series} ${influx_payload}  ${timestamp_ns}'"
            let return_code=${return_code}+${?}
        else
            let return_code=${return_code}+${ERROR}
        fi
    
    done

    return ${return_code}
}

# WHAT: CPU Load metrics 
f__cpu_load_metrics() {
    let return_code=${SUCCESS}

    local raw_uptime_line=$(uptime)
    local load_info=$(echo "${raw_uptime_line}" | awk -F'load average:' '{print $NF}' | sed -e 's|,||g')
    local load1=$(echo "${load_info}" | awk '{print $(NF-2)}')
    local load5=$(echo "${load_info}" | awk '{print $(NF-1)}')
    local load15=$(echo "${load_info}" | awk '{print $NF}')
    local n_cpus=$(egrep -c "^\bprocessor\b.*:" /proc/cpuinfo)
    local series="system,host=${my_hostname}"
    local timestamp=$(date +%s)
    local timestamp_ns=$(echo "${timestamp}*1000000000" | bc)
    
    # Figure out how to compute n_user from uptime output
    local n_users=""
    local uptime_has_user=$(echo "${raw_uptime_line}" | egrep -c "\buser\b,")

    if [ "${uptime_has_user}" = "0" ]; then
        n_users="0"
    else
        n_users=$(echo "${raw_uptime_line}" | awk -F'user' '{print $1}' | awk '{print $NF}')
    fi
    
    local uptime=$(awk '{print $1}' /proc/uptime | awk -F'.' '{print $1}')
    local uptime_format=$(echo "${raw_uptime_line}" | awk -F'load average:' '{print $1}' | sed -e 's|,||g' -e 's| *[0-9]* user.*$||g' | awk -F' up ' '{print $NF}' | sed -e 's|  | |g' -e 's|day |day, |g' -e 's|days |days, |g' -e 's| $||g')

    local influx_payload="load1=${load1},load15=${load15},load5=${load5},n_cpus=${n_cpus}i,n_users=${n_users}i,uptime=${uptime}i,uptime_format=\"${uptime_format}\""
    
    # Send computed metrics to influx
    eval "/bin/nice -19 curl -m 3 -s -i -XPOST 'http://${influxdb_host}:${influxdb_host_port}/write?db=${influxdb}' --data-binary '${series} ${influx_payload} ${timestamp_ns}'"
    let return_code=${return_code}+${?}

    return ${return_code}
}

# WHAT: Memory metrics
f__memory_metrics() {
    let return_code=${SUCCESS}

    local influx_payload=""
    local raw_mem_total_info=""
    local series="mem,host=${my_hostname}"
    local timestamp=$(date +%s)
    local timestamp_ns=$(echo "${timestamp}*1000000000" | bc)
    
    local influx_fields="available buffered cached commit_limit committed_as dirty free high_free high_total huge_page_size huge_pages_free huge_pages_total inactive low_free low_total mapped page_tables shared slab sreclaimable sunreclaim swap_cached swap_free swap_total total vmalloc_chunk vmalloc_total vmalloc_used wired write_back write_back_tmp"
    local meminfo_attribute=""

    for influx_field in ${influx_fields} ; do
        meminfo_attribute=""
    
        case ${influx_field} in
    
            active)
                meminfo_attribute="Active"
            ;;
    
            available)
                meminfo_attribute="MemAvailable"
            ;;
    
            buffered)
                meminfo_attribute="Buffers"
            ;;
    
            cached)
                meminfo_attribute="Cached"
            ;;
    
            commit_limit)
                meminfo_attribute="CommitLimit"
            ;;
    
            committed_as)
                meminfo_attribute="Committed_AS"
            ;;
    
            dirty)
                meminfo_attribute="Dirty"
            ;;
    
            free)
                meminfo_attribute="MemFree"
            ;;
    
            high_free)
                meminfo_attribute="HighFree"
            ;;
    
            high_total)
                meminfo_attribute="HighTotal"
            ;;
            
            huge_page_size)
                meminfo_attribute="Hugepagesize"
            ;;
    
            huge_pages_free)
                meminfo_attribute="HugePages_Free"
            ;;
    
            huge_pages_total)
                meminfo_attribute="HugePages_Total"
            ;;
    
            inactive)
                meminfo_attribute="Inactive"
            ;;
    
            low_free)
                meminfo_attribute="LowFree"
            ;;
    
            low_total)
                meminfo_attribute="LowTotal"
            ;;
    
            mapped)
                meminfo_attribute="Mapped"
            ;;
    
            page_tables)
                meminfo_attribute="PageTables"
            ;;
    
            shared)
                meminfo_attribute="Shmem"
            ;;
    
            slab)
                meminfo_attribute="Slab"
            ;;
    
            sreclaimable)
                meminfo_attribute="SReclaimable"
            ;;
    
            sunreclaim)
                meminfo_attribute="SUnreclaim"
            ;;
    
            swap_cached)
                meminfo_attribute="SwapCached"
            ;;
    
            swap_free)
                meminfo_attribute="SwapFree"
            ;;
    
            swap_total)
                meminfo_attribute="SwapTotal"
            ;;
    
            total)
                meminfo_attribute="MemTotal"
                raw_mem_total_info=$(echo "${raw_meminfo}" | egrep "^${meminfo_attribute}:")
            ;;
    
            vmalloc_chunk)
                meminfo_attribute="VmallocChunk"
            ;;
    
            vmalloc_total)
                meminfo_attribute="VmallocTotal"
            ;;
    
            vmalloc_used)
                meminfo_attribute="VmallocUsed"
            ;;
    
            wired)
                meminfo_attribute="Unevictable"
            ;;
    
            write_back)
                meminfo_attribute="Writeback"
            ;;
    
            write_back_tmp)
                meminfo_attribute="WritebackTmp"
            ;;
    
        esac
    
        local raw_meminfo=$(awk '{print $1 $2 ":" $3}' /proc/meminfo)

        if [ ! -z "${meminfo_attribute}" ]; then
            local raw_line=$(echo "${raw_meminfo}" | egrep "^${meminfo_attribute}:")
            local raw_value=$(echo "${raw_line}" | awk -F':' '{print $2}')
    
            if [ -z "${raw_value}" ]; then
                raw_value="0"
            fi
    
            local value_units=$(echo "${raw_line}" | awk -F':' '{print $NF}')
            local multiplier=$(f__unit_factor "${value_units}")
            local value=$(echo "${raw_value}*${multiplier}" | bc)
    
            if [ -z "${influx_payload}" ]; then
                influx_payload="${influx_field}=${value}i"
            else
                influx_payload="${influx_payload},${influx_field}=${value}i"
            fi
    
        fi
    
    done
    
    local raw_mem_units=$(echo "${raw_mem_total_info}" | awk -F':' '{print $3}')
    
    # retrieve used from 'free' command - default units come from /proc/meminfo
    local raw_mem_used_value=$(free | egrep -i "^mem:" | awk '{print $3}')
    local raw_mem_used_multiplier=$(f__unit_factor "${raw_mem_units}")
    local mem_used=$(echo "${raw_mem_used_value}*${raw_mem_used_multiplier}" | bc)
    
    if [ -z "${influx_payload}" ]; then
        influx_payload="used=${mem_used}i"
    else
        influx_payload="${influx_payload},used=${mem_used}i"
    fi
    
    # retrieve total from 'free' command - default units come from /proc/meminfo
    local raw_mem_total_value=$(free | egrep -i "^mem:" | awk '{print $2}')
    local raw_mem_total_multiplier=$(f__unit_factor "${raw_mem_units}")
    local mem_total=$(echo "${raw_mem_total_value}*${raw_mem_total_multiplier}" | bc)
    
    # compute used_percent
    local used_percent=$(echo "scale=5;${mem_used}/${mem_total}*100" | bc)
    
    if [ -z "${influx_payload}" ]; then
        influx_payload="used_percent=${used_percent}"
    else
        influx_payload="${influx_payload},used_percent=${used_percent}"
    fi
    
    # retrieve available from '/proc/meminfo'
    local raw_mem_available_value=$(egrep -i "available:" /proc/meminfo | awk '{print $(NF-1)}')
    local raw_mem_available_multiplier=$(f__unit_factor "${raw_mem_units}")
    local mem_available=$(echo "${raw_mem_available_value}*${raw_mem_available_multiplier}" | bc)
    
    # compute available_percent
    local available_percent=$(echo "scale=5;${mem_available}/${mem_total}*100" | bc)
    
    if [ -z "${influx_payload}" ]; then
        influx_payload="available_percent=${available_percent}"
    else
        influx_payload="${influx_payload},available_percent=${available_percent}"
    fi
    
    ### Send computed metrics to influx
    eval "/bin/nice -19 curl -m 3 -s -i -XPOST 'http://${influxdb_host}:${influxdb_host_port}/write?db=${influxdb}' --data-binary '${series} ${influx_payload} ${timestamp_ns}'"
    let return_code=${return_code}+${?}

    return ${return_code}
}

# WHAT: Process metrics
f__process_metrics() {
    let return_code=${SUCCESS}

    local series="processes,host=${my_hostname}"
    local timestamp=$(date +%s)
    local timestamp_ns=$(echo "${timestamp}*1000000000" | bc)

    local current_proc_status=$(/bin/nice -19 find /proc/[0-9]*/status -exec egrep -i '^\bstate\b' '{}' \; 2> /dev/null)
    local current_proc_stat=$(awk '{print $0}' /proc/stat)

    local blocked=$(echo "${current_proc_stat}" | awk '/^procs_blocked/ {print $NF}')
    local dead=$(echo "${current_proc_status}" | egrep -ic "dead")
    local idle=$(echo "${current_proc_status}" | egrep -ic "idle")
    local paging=$(echo "${current_proc_status}" | egrep -ic "paging")
    local running=$(echo "${current_proc_stat}" | awk '/^procs_running/ {print $NF}')
    local sleeping=$(echo "${current_proc_status}" | egrep -ic "sleeping")
    local stopped=$(echo "${current_proc_status}" | egrep -ic "stopped")
    local total=$(/bin/nice -19 find /proc/ -maxdepth 1 -type d 2> /dev/null | egrep "/[0-9]" | wc -l | awk '{print $1}')
    local total_threads=$(/bin/nice -19 find /proc/[0-9]*/task/[0-9]*/* -maxdepth 1 -type d 2> /dev/null | wc -l | awk '{print $1}')
    local unknown=$(echo "${current_proc_status}" | egrep -vic "dead|idle|running|sleeping|stopped|zombie")
    local zombies=$(echo "${current_proc_status}" | egrep -ic "zombie")

    influx_payload="blocked=${blocked}i,dead=${dead}i,idle=${idle}i,paging=${paging}i,running=${running}i,sleeping=${sleeping}i,stopped=${stopped}i,total=${total}i,total_threads=${total_threads}i,unknown=${unknown}i,zombies=${zombies}i"

    eval "/bin/nice -19 curl -m 3 -s -i -XPOST 'http://${influxdb_host}:${influxdb_host_port}/write?db=${influxdb}' --data-binary '${series} ${influx_payload} ${timestamp_ns}'"
    let return_code=${return_code}+${?}

    return ${return_code}
}

# WHAT: 'netstat -atun' metrics
f__netstat_metrics() {
    let return_code=${SUCCESS}

    local series="netstat,host=${my_hostname}"
    local timestamp=$(date +%s)
    local timestamp_ns=$(echo "${timestamp}*1000000000" | bc)

    local raw_netstat_info=$(netstat -atun)

    # Valid states:
    # LISTEN ESTABLISHED SYN_SENT SYN_RECV LAST_ACK CLOSE_WAIT TIME_WAIT CLOSED CLOSING FIN_WAIT1 FIN_WAIT2
    local all_connection_states="LISTEN|ESTABLISHED|SYN_SENT|SYN_RECV|LAST_ACK|CLOSE_WAIT|TIME_WAIT|CLOSED|CLOSING|FIN_WAIT1|FIN_WAIT2"

    local tcp_close=$(echo "${raw_netstat_info}" | egrep -c "\bCLOSED\b")
    local tcp_close_wait=$(echo "${raw_netstat_info}" | egrep -c "\bCLOSE_WAIT\b")
    local tcp_closing=$(echo "${raw_netstat_info}" | egrep -c "\bCLOSING\b")
    local tcp_established=$(echo "${raw_netstat_info}" | egrep -c "\bESTABLISHED\b")
    local tcp_fin_wait1=$(echo "${raw_netstat_info}" | egrep -c "\bFIN_WAIT1\b")
    local tcp_fin_wait2=$(echo "${raw_netstat_info}" | egrep -c "\bFIN_WAIT2\b")
    local tcp_last_ack=$(echo "${raw_netstat_info}" | egrep -c "\bLAST_ACK\b")
    local tcp_listen=$(echo "${raw_netstat_info}" | egrep -c "\bLISTEN\b")
    local tcp_none=$(echo "${raw_netstat_info}" | egrep -cv "${all_connection_states}")
    local tcp_syn_recv=$(echo "${raw_netstat_info}" | egrep -c "\bSYN_RECV\b")
    local tcp_syn_sent=$(echo "${raw_netstat_info}" | egrep -c "\bSYN_SENT\b")
    local tcp_time_wait=$(echo "${raw_netstat_info}" | egrep -c "\bTIME_WAIT\b")
    local udp_socket=$(echo "${raw_netstat_info}" | egrep -c "^udp")

    local influx_payload="tcp_close=${tcp_close}i,tcp_close_wait=${tcp_close_wait}i,tcp_closing=${tcp_closing}i,tcp_established=${tcp_established}i,tcp_fin_wait1=${tcp_fin_wait1}i,tcp_fin_wait2=${tcp_fin_wait2}i,tcp_last_ack=${tcp_last_ack}i,tcp_listen=${tcp_listen}i,tcp_none=${tcp_none}i,tcp_syn_recv=${tcp_syn_recv}i,tcp_syn_sent=${tcp_syn_sent}i,tcp_time_wait=${tcp_time_wait}i,udp_socket=${udp_socket}i"

    eval "/bin/nice -19 curl -m 3 -s -i -XPOST 'http://${influxdb_host}:${influxdb_host_port}/write?db=${influxdb}' --data-binary '${series} ${influx_payload} ${timestamp_ns}'"

    return ${return_code}
}

# WHAT: /proc/net/{netstat,snmp,snmp6} metrics
f__nstat_metrics() {
    let return_code=${SUCCESS}

    local timestamp=$(date +%s)
    local timestamp_ns=$(echo "${timestamp}*1000000000" | bc)

    # File mapping
    local Icmp_file="/proc/net/snmp"
    local Icmp6_file="/proc/net/snmp6"
    local Ip_file="/proc/net/snmp"
    local Ip6_file="/proc/net/snmp6"
    local Tcp_file="/proc/net/snmp"
    local Udp_file="/proc/net/snmp"
    local Udp6_file="/proc/net/snmp6"
    local IpExt_file="/proc/net/netstat"
    local TcpExt_file="/proc/net/netstat"
    
    local influx_payload=""
    
    if [ -e "${Icmp_file}" ]; then
        local nstat_Icmp_fields=$(egrep "^Icmp: [a-zA-Z]" "${Icmp_file}" | awk -F': ' '{print $NF}')
        local nstat_Icmp_values=$(egrep "^Icmp: [0-9]" "${Icmp_file}" | awk -F': ' '{print $NF}')
        local influx_Icmp_fields="IcmpInDestUnreachs IcmpInEchoReps IcmpInEchos IcmpInErrors IcmpInMsgs IcmpInTimeExcds IcmpMsgInType0 IcmpMsgInType11 IcmpMsgInType3 IcmpMsgInType8 IcmpMsgOutType0 IcmpMsgOutType3 IcmpMsgOutType8 IcmpOutDestUnreachs IcmpOutEchoReps IcmpOutEchos IcmpOutMsgs"
    fi
    
    if [ -e "${Icmp6_file}" ]; then
        local nstat_Icmp6_fields=$(egrep "^Icmp6" "${Icmp6_file}" | awk '{print $1}' | sed -e 's|^Icmp6||g')
        local nstat_Icmp6_values=$(egrep "^Icmp6" "${Icmp6_file}" | awk '{print $2}')
        local influx_Icmp6_fields="Icmp6InDestUnreachs Icmp6InGroupMembQueries Icmp6InGroupMembReductions Icmp6InGroupMembResponses Icmp6InMLDv2Reports Icmp6InMsgs Icmp6InNeighborAdvertisements Icmp6InNeighborSolicits Icmp6InRouterAdvertisements Icmp6InType1 Icmp6InType130 Icmp6InType131 Icmp6InType132 Icmp6InType134 Icmp6InType135 Icmp6InType136 Icmp6InType143 Icmp6OutDestUnreachs Icmp6OutGroupMembResponses Icmp6OutMLDv2Reports Icmp6OutMsgs Icmp6OutNeighborAdvertisements Icmp6OutNeighborSolicits Icmp6OutRouterSolicits Icmp6OutType1 Icmp6OutType131 Icmp6OutType133 Icmp6OutType135 Icmp6OutType136 Icmp6OutType143"
    fi
    
    if [ -e "${Ip_file}" ]; then
        local nstat_Ip_fields=$(egrep "^Ip: [a-zA-Z]" "${Ip_file}" | awk -F': ' '{print $NF}')
        local nstat_Ip_values=$(egrep "^Ip: [0-9]" "${Ip_file}" | awk -F': ' '{print $NF}')
        local influx_Ip_fields="IpDefaultTTL IpForwarding IpFragCreates IpFragOKs IpInAddrErrors IpInDelivers IpInReceives IpInUnknownProtos IpOutDiscards IpOutNoRoutes IpOutRequests IpReasmOKs IpReasmReqds"
    fi
    
    if [ -e "${Ip6_file}" ]; then
        local nstat_Ip6_fields=$(egrep "^Ip6" "${Ip6_file}" | awk '{print $1}' | sed -e 's|^Ip6||g')
        local nstat_Ip6_values=$(egrep "^Ip6" "${Ip6_file}" | awk '{print $2}')
        local influx_Ip6_fields="Ip6InDelivers Ip6InMcastOctets Ip6InMcastPkts Ip6InNoECTPkts Ip6InNoRoutes Ip6InOctets Ip6InReceives Ip6InTruncatedPkts Ip6OutDiscards Ip6OutMcastOctets Ip6OutMcastPkts Ip6OutNoRoutes Ip6OutOctets Ip6OutRequests"
    fi
    
    if [ -e "${Udp_file}" ]; then
        local nstat_Udp_fields=$(egrep "^Udp: [a-zA-Z]" "${Udp_file}" | awk -F': ' '{print $NF}')
        local nstat_Udp_values=$(egrep "^Udp: [0-9]" "${Udp_file}" | awk -F': ' '{print $NF}')
        local influx_Udp_fields="UdpIgnoredMulti UdpInCsumErrors UdpInDatagrams UdpInErrors UdpNoPorts UdpOutDatagrams"
    fi
    
    if [ -e "${Udp6_file}" ]; then
        local nstat_Udp6_fields=$(egrep "^Udp6" "${Udp6_file}" | awk '{print $1}' | sed -e 's|^Udp6||g')
        local nstat_Udp6_values=$(egrep "^Udp6" "${Udp6_file}" | awk '{print $2}')
        local influx_Udp6_fields="Udp6IgnoredMulti Udp6InDatagrams Udp6NoPorts Udp6OutDatagrams"
    fi
    
    if [ -e "${Tcp_file}" ]; then
        local nstat_Tcp_fields=$(egrep "^Tcp: [a-zA-Z]" "${Tcp_file}" | awk -F': ' '{print $NF}')
        local nstat_Tcp_values=$(egrep "^Tcp: [0-9]" "${Tcp_file}" | awk -F': ' '{print $NF}')
        local influx_Tcp_fields="TcpActiveOpens TcpAttemptFails TcpCurrEstab TcpEstabResets TcpInCsumErrors TcpInErrs TcpInSegs TcpMaxConn TcpOutRsts TcpOutSegs TcpPassiveOpens TcpRetransSegs TcpRtoAlgorithm TcpRtoMax TcpRtoMin"
    fi
    
    if [ -e "${TcpExt_file}" ]; then
        local nstat_TcpExt_fields=$(egrep "^TcpExt: [a-zA-Z]" "${TcpExt_file}" | awk -F': ' '{print $NF}')
        local nstat_TcpExt_values=$(egrep "^TcpExt: [0-9]" "${TcpExt_file}" | awk -F': ' '{print $NF}')
        local influx_TcpExt_fields="TcpExtDelayedACKLocked TcpExtDelayedACKLost TcpExtDelayedACKs TcpExtEmbryonicRsts TcpExtOutOfWindowIcmps TcpExtPAWSEstab TcpExtPruneCalled TcpExtTCPACKSkippedSeq TcpExtTCPACKSkippedSynRecv TcpExtTCPAbortOnClose TcpExtTCPAbortOnData TcpExtTCPAbortOnTimeout TcpExtTCPAutoCorking TcpExtTCPBacklogDrop TcpExtTCPChallengeACK TcpExtTCPDSACKIgnoredNoUndo TcpExtTCPDSACKIgnoredOld TcpExtTCPDSACKOfoRecv TcpExtTCPDSACKOfoSent TcpExtTCPDSACKOldSent TcpExtTCPDSACKRecv TcpExtTCPDSACKUndo TcpExtTCPDirectCopyFromBacklog TcpExtTCPDirectCopyFromPrequeue TcpExtTCPFastRetrans TcpExtTCPForwardRetrans TcpExtTCPFromZeroWindowAdv TcpExtTCPFullUndo TcpExtTCPHPAcks TcpExtTCPHPHits TcpExtTCPHystartDelayCwnd TcpExtTCPHystartDelayDetect TcpExtTCPHystartTrainCwnd TcpExtTCPHystartTrainDetect TcpExtTCPKeepAlive TcpExtTCPLossProbeRecovery TcpExtTCPLossProbes TcpExtTCPLossUndo TcpExtTCPLostRetransmit TcpExtTCPOFOMerge TcpExtTCPOFOQueue TcpExtTCPOrigDataSent TcpExtTCPPartialUndo TcpExtTCPPrequeued TcpExtTCPPureAcks TcpExtTCPRcvCoalesce TcpExtTCPRcvCollapsed TcpExtTCPRetransFail TcpExtTCPSACKReorder TcpExtTCPSYNChallenge TcpExtTCPSackFailures TcpExtTCPSackMerged TcpExtTCPSackRecovery TcpExtTCPSackRecoveryFail TcpExtTCPSackShiftFallback TcpExtTCPSackShifted TcpExtTCPSlowStartRetrans TcpExtTCPSpuriousRTOs TcpExtTCPSpuriousRtxHostQueues TcpExtTCPSynRetrans TcpExtTCPTSReorder TcpExtTCPTimeouts TcpExtTCPToZeroWindowAdv TcpExtTCPWantZeroWindowAdv TcpExtTCPWinProbe TcpExtTW"
    fi
   
    if [ -e "${IpExt_file}" ]; then
        local nstat_IpExt_fields=$(egrep "^IpExt: [a-zA-Z]" "${IpExt_file}" | awk -F': ' '{print $NF}')
        local nstat_IpExt_values=$(egrep "^IpExt: [0-9]" "${IpExt_file}" | awk -F': ' '{print $NF}')
        local influx_IpExt_fields="IpExtInBcastOctets IpExtInBcastPkts IpExtInCEPkts IpExtInECT0Pkts IpExtInMcastOctets IpExtInMcastPkts IpExtInNoECTPkts IpExtInNoRoutes IpExtInOctets IpExtInTruncatedPkts IpExtOutBcastOctets IpExtOutBcastPkts IpExtOutMcastOctets IpExtOutMcastPkts IpExtOutOctets"
    fi

    local canary_file=""
    local influx_payload_name=""
    local influx_nstat_key=""
    
    for field_regex in Icmp Ip Tcp Udp Icmp6 Ip6 Udp6 IpExt TcpExt ; do

        case ${field_regex} in

            Icmp|Ip|Tcp|Udp)
                influx_payload_name="influx_payload_snmp"
                canary_file="/proc/net/snmp"
            ;;

            Icmp6|Ip6|Udp6)
                influx_payload_name="influx_payload_snmp6"
                canary_file="/proc/net/snmp6"
            ;;

            IpExt|TcpExt)
                influx_payload_name="influx_payload_netstat"
                canary_file="/proc/net/netstat"
            ;;

        esac

        if [ -e "${canary_file}" ]; then
            eval "influx_fields=\"\${influx_${field_regex}_fields}\""
            eval "nstat_fields=(\${nstat_${field_regex}_fields})"
            eval "nstat_values=(\${nstat_${field_regex}_values})"
        fi
    
        if [ ! -z "${nstat_fields[0]}" ]; then
        
            for influx_field in ${influx_fields} ; do
                influx_nstat_key=$(echo "${influx_field}" | sed -e "s|${field_regex}||g")
            
                let element_counter=0
            
                for nstat_element in ${nstat_fields[@]} ; do
            
                    if [ "${influx_nstat_key}" = "${nstat_element}" ]; then
                        eval "influx_payload_test=\"\$${influx_payload_name}\""
            
                        if [ -z "${influx_payload_test}" ]; then
                            eval "${influx_payload_name}=\"${influx_field}=${nstat_values[$element_counter]}i\""
                        else
                            eval "${influx_payload_name}=\"\$${influx_payload_name},${influx_field}=${nstat_values[$element_counter]}i\""
                        fi
            
                        break
                    fi
            
                    let element_counter=${element_counter}+1
                done
            
            done

        fi
    
    done

    local influx_payload_parts="netstat snmp snmp6"

    for influx_payload_part in ${influx_payload_parts} ; do
        series="nstat,host=${my_hostname},name=${influx_payload_part}"
        eval "influx_payload=\"\${influx_payload_${influx_payload_part}}\""

        if [ ! -z "${influx_payload}" ]; then
            eval "/bin/nice -19 curl -m 3 -s -i -XPOST 'http://${influxdb_host}:${influxdb_host_port}/write?db=${influxdb}' --data-binary '${series} ${influx_payload} ${timestamp_ns}'"
        fi

    done
    
    return ${return_code}
}

# WHAT: /sys/class/net/<iface>/statistics metrics
f__net_metrics() {
    let return_code=${SUCCESS}

    local influx_payload=""
    local series=""

    local timestamp=""
    local timestamp_ns=""

    local influx_attribs="bytes_recv bytes_sent"
    local measurement_interval="3"

    # Get our interfaces, ignore lo
    sys_class_net="/sys/class/net"
    local network_interfaces=$(for iface in $(ls ${sys_class_net} 2> /dev/null) ; do echo "${iface}" ; done | egrep -v "^lo$" | sort)

    if [ ! -z "${network_interfaces}" ]; then

        for network_interface in ${network_interfaces} ; do
            influx_payload=""
            series="net,host=${my_hostname},interface=${network_interface}"
            local timestamp=$(date +%s)
            local timestamp_ns=$(echo "${timestamp}*1000000000" | bc)

            # Compute the mean bytes sent and received over a '${measurement_interval}' second interval
            for influx_attrib in ${influx_attribs} ; do

                case ${influx_attrib} in 

                    bytes_recv)
                        metrics_file="${sys_class_net}/${network_interface}/statistics/rx_packets"
                    ;;

                    bytes_sent)
                        metrics_file="${sys_class_net}/${network_interface}/statistics/tx_packets"
                    ;;

                esac

                if [ -e "${metrics_file}" ]; then
                    let countdown=${measurement_interval}
                    local mean=""
                    local value=""

                    while [ ${countdown} -gt 0 ]; do
                        value=$(awk '{print $0}' "${metrics_file}")

                        if [ -z "${mean}" ]; then
                            let mean=${value}
                        else
                            let mean=${mean}+${value}
                        fi

                        let countdown=${countdown}-1
                        sleep 1
                    done

                    mean=$(echo "${mean}/${measurement_interval}" | bc)

                    if [ -z "${influx_payload}" ]; then
                        influx_payload="${influx_attrib}=${mean}i"
                    else
                        influx_payload="${influx_payload},${influx_attrib}=${mean}i"
                    fi

                fi

            done

            if [ ! -z "${influx_payload}" ]; then
                eval "/bin/nice -19 curl -m 3 -s -i -XPOST 'http://${influxdb_host}:${influxdb_host_port}/write?db=${influxdb}' --data-binary '${series} ${influx_payload} ${timestamp_ns}'"
            fi

        done

    fi

    return ${return_code}
}

# WHAT: Disk usage metrics
f__disk_usage() {
    let return_code=${SUCCESS}

    local influx_payload=""
    local series=""
    local timestamp=""
    local timestamp_ns=""
    local raw_df_info=""
    local proc_mount=""
    local device=""
    local df_raw_value=""
    local df_value_multiplier=""
    local df_free=""
    local df_used=""

    # Raw relevant /proc/mounts info
    local raw_proc_mount=$(egrep "\bext4\b|\bjffs2\b|\bsquashfs\b|\bxfs\b" /proc/mounts | sed -e "s| |${x_wing_fighter}|g")

    for proc_mount in ${raw_proc_mount} ; do
        timestamp=$(date +%s)
        timestamp_ns=$(echo "${timestamp}*1000000000" | bc)

        proc_mount_line=$(echo "${proc_mount}" | sed -e "s|${x_wing_fighter}| |g")
        dev_device=$(echo "${proc_mount_line}" | awk '{print $1}')
        device=$(echo "${dev_device}" | awk -F'/' '{print $NF}')
        path=$(echo "${proc_mount_line}" | awk '{print $2}' | sed -e 's|^/dev/||g')
        fstype=$(echo "${proc_mount_line}" | awk '{print $3}' | sed -e 's|^/dev/||g')
        mode=$(echo "${proc_mount_line}" | awk '{print $4}' | awk -F',' '{print $1}')

        series="disk,device=${device},fstype=${fstype},host=${my_hostname},mode=${mode},path=${path}"

        raw_df_info=$(df -k ${dev_device} 2> /dev/null | tail -1 | egrep -iv "^filesystem")

        # Get free bytes from df -k '${dev_device}'
        if [ ! -z "${raw_df_info}" ]; then
            df_raw_value=$(echo "${raw_df_info}" | awk '{print $(NF-2)}')
            df_value_multiplier=$(f__unit_factor "kb")
            df_free=$(echo "${df_raw_value}*${df_value_multiplier}" | bc)

            # Get used bytes from df -k '${dev_device}'
            df_raw_value=$(echo "${raw_df_info}" | awk '{print $(NF-3)}')
            df_value_multiplier=$(f__unit_factor "kb")
            df_used=$(echo "${df_raw_value}*${df_value_multiplier}" | bc)
            
            # Get total bytes from df -k '${dev_device}'
            df_raw_value=$(echo "${raw_df_info}" | awk '{print $(NF-4)}')
            df_value_multiplier=$(f__unit_factor "kb")
            df_total=$(echo "${df_raw_value}*${df_value_multiplier}" | bc)

            # Get percent used from df -k '${dev_device}'
            df_used_percent=$(echo "scale=5;${df_used}/${df_total}*100" | bc)
        else
            df_free="0"
            df_used="0"
            df_total="0"
            df_used_percent="0.0"
        fi

        raw_inode_info=$(stat -f ${path} 2> /dev/null | egrep -i "^inodes:" | awk '{print $(NF-2)":"$(NF)}')

        if [ ! -z "${raw_inode_info}" ]; then
            inodes_total=$(echo "${raw_inode_info}" | awk -F':' '{print $1}')
            inodes_free=$(echo "${raw_inode_info}" | awk -F':' '{print $NF}')
            inodes_used=$(echo "${inodes_total}-${inodes_free}" | bc)
        else
            inodes_total="0"
            inodes_free="0"
            inodes_used="0"
        fi

        influx_payload="free=${df_free}i,total=${df_total}i,used=${df_used}i,used_percent=${df_used_percent},inodes_free=${inodes_free}i,inodes_total=${inodes_total}i,inodes_used=${inodes_used}i"

        eval "/bin/nice -19 curl -m 3 -s -i -XPOST 'http://${influxdb_host}:${influxdb_host_port}/write?db=${influxdb}' --data-binary '${series} ${influx_payload} ${timestamp_ns}'"
    done

    return ${return_code}
}

# WHAT: One main to call all the metrics functions
f__main() {
    let return_code=${SUCCESS}

    local arg="${1}"

    case ${arg} in

        cpu)
            (f__cpu_stat_metrics > /dev/null 2>&1)&
            sleep 1
            (f__cpu_load_metrics > /dev/null 2>&1)&
        ;;

        memory)
            (f__memory_metrics   > /dev/null 2>&1)&
            sleep 1
            (f__process_metrics  > /dev/null 2>&1)&
        ;;

        network)
            (f__netstat_metrics  > /dev/null 2>&1)&
            sleep 1
            (f__nstat_metrics    > /dev/null 2>&1)&
            sleep 1
            (f__net_metrics      > /dev/null 2>&1)&
        ;;

        disk)
            (f__disk_usage       > /dev/null 2>&1)&
        ;;

        *)
            (f__cpu_stat_metrics > /dev/null 2>&1)&
            sleep 1
            (f__cpu_load_metrics > /dev/null 2>&1)&
            sleep 1
            (f__memory_metrics   > /dev/null 2>&1)&
            sleep 1
            (f__process_metrics  > /dev/null 2>&1)&
            sleep 1
            (f__netstat_metrics  > /dev/null 2>&1)&
            sleep 1
            (f__nstat_metrics    > /dev/null 2>&1)&
            sleep 1
            (f__net_metrics      > /dev/null 2>&1)&
            sleep 1
            (f__disk_usage       > /dev/null 2>&1)&

            #f__cpu_stat_metrics
            #f__cpu_load_metrics
            #f__memory_metrics
            #f__process_metrics
            #f__netstat_metrics
            #f__nstat_metrics
            #f__net_metrics
            #f__disk_usage
        ;;

        esac

    return ${return_code}
}

# Main - Do a thing
f__main "${@}"

exit ${?}

