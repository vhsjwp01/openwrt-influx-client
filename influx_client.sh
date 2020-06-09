#!/bin/ash
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
        local is_cpu_total=$(echo "${this_cpu}" | sed -e 's|cpu||g')
        local influx_payload=""
        local timestamp=$(date +%s)
        local timestamp_ns=$(echo "${timestamp}*1000000000" | bc)
        local series=""
    
        if [ -z "${is_cpu_total}" ]; then
            series="cpu,cpu=cpu-total,host=${my_hostname}"
        else
            series="cpu,cpu=${this_cpu},host=${my_hostname}"
        fi
    
    
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
            eval "curl -m 3 -s -i -XPOST 'http://${influxdb_host}:${influxdb_host_port}/write?db=${influxdb}' --data-binary '${series} ${influx_payload}  ${timestamp_ns}'"
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
    local n_users=""
    local series="system,host=${my_hostname}"
    local timestamp=$(date +%s)
    local timestamp_ns=$(echo "${timestamp}*1000000000" | bc)
    
    # Figure out how to compute n_user from uptime output
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
    eval "curl -m 3 -s -i -XPOST 'http://${influxdb_host}:${influxdb_host_port}/write?db=${influxdb}' --data-binary '${series} ${influx_payload} ${timestamp_ns}'"
    let return_code=${return_code}+${?}

    return ${return_code}
}

# WHAT: Memory metrics
f__memory_metrics() {
    let return_code=${SUCCESS}

    local influx_fields="available buffered cached commit_limit committed_as dirty free high_free high_total huge_page_size huge_pages_free huge_pages_total inactive low_free low_total mapped page_tables shared slab sreclaimable sunreclaim swap_cached swap_free swap_total total vmalloc_chunk vmalloc_total vmalloc_used wired write_back write_back_tmp"
    local influx_payload=""
    local meminfo_attribute=""
    local raw_mem_total_info=""
    local raw_meminfo=$(awk '{print $1 $2 ":" $3}' /proc/meminfo)
    local series="mem,host=${my_hostname}"
    
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
    eval "curl -m 3 -s -i -XPOST 'http://${influxdb_host}:${influxdb_host_port}/write?db=${influxdb}' --data-binary '${series} ${influx_payload} ${timestamp_ns}'"
    let return_code=${return_code}+${?}

    return ${return_code}
}

f__process_metrics() {
    let return_code=${SUCCESS}

    local series="processes,host=${my_hostname}"

    local current_proc_status=$(/bin/nice -19 find /proc/[0-9]*/status -exec egrep -i '^\bstate\b' '{}' \;)
    local current_proc_stat=$(awk '{print $0}' /proc/stat)

    local blocked=$(echo "${current_proc_stat}" | awk '/^procs_blocked/ {print $NF}')
    local dead=$(echo "${current_proc_status}" | egrep -ic "dead")
    local idle=$(echo "${current_proc_status}" | egrep -ic "idle")
    local paging=$(echo "${current_proc_status}" | egrep -ic "paging")
    local running=$(echo "${current_proc_stat}" | awk '/^procs_running/ {print $NF}')
    local sleeping=$(echo "${current_proc_status}" | egrep -ic "sleeping")
    local stopped=$(echo "${current_proc_status}" | egrep -ic "stopped")
    local total=$(/bin/nice -19 find /proc/ -maxdepth 1 -type d | egrep "/[0-9]" | wc -l | awk '{print $1}')
    local total_threads=$(/bin/nice -19 find /proc/[0-9]*/task/[0-9]*/* -maxdepth 1 -type d | wc -l | awk '{print $1}')
    local unknown=$(echo "${current_proc_status}" | egrep -vic "dead|idle|running|sleeping|stopped|zombie")
    local zombies=$(echo "${current_proc_status}" | egrep -ic "zombie")

    influx_payload="blocked=${blocked}i,dead=${dead}i,idle=${idle}i,paging=${paging}i,running=${running}i,sleeping=${sleeping}i,stopped=${stopped}i,total=${total}i,total_threads=${total_threads}i,unknown=${unknown}i,zombies=${zombies}i"

    eval "curl -m 3 -s -i -XPOST 'http://${influxdb_host}:${influxdb_host_port}/write?db=${influxdb}' --data-binary '${series} ${influx_payload} ${timestamp_ns}'"
    let return_code=${return_code}+${?}

    return ${return_code}
}

# WHAT: One main to call all the metrics functions
f__main() {
    let return_code=${SUCCESS}

    f__cpu_stat_metrics
    let return_code=${return_code}+${?}

    f__cpu_load_metrics
    let return_code=${return_code}+${?}

    f__memory_metrics
    let return_code=${return_code}+${?}

    f__process_metrics
    let return_code=${return_code}+${?}

    return ${return_code}
}

# Main - Do a thing
f__main "${@}"
exit ${?}

