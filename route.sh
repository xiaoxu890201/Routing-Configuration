argv=$1
ipArr=()

GetInterfaceIp() {
    ifconfig $1|sed -n 2p|awk  '{ print $2 }'|tr -d 'addr:' |tr -d '地址'
}
GetInterfaceMask() {
    ifconfig $1|sed -n 2p|awk  '{ print $4 }'|tr -d 'Mask:' |tr -d '掩码'
}
GetInterfaceGw() {
    local ifacetmp=$1
    route -n > tmp
    while read line
    do
        echo  $line | grep "$ifacetmp" | awk '{ print $4 }' | grep -q "G"
        if [ "$?" -eq 0 ];then
            echo $line | grep "$ifacetmp" | awk '{ print $2 }'
        fi
    done < tmp
    rm -rf tmp
}

CheckIp() {
    local ip=$1
    echo "$ip" | sed -n '/\(\(\(1\?[0-9]\?[0-9]\)\|\(2\([0-4][0-9]\|5[0-5]\)\)\)\.\)\{3\}\(\(1\?[0-9]\?[0-9]\)\|\(2\([0-4][0-9]\|5[0-5]\)\)\)$/p'
}

CheckModify() {
    local dev=$1
    local ip=$2
    local mask=$3
    local gw=$4
    
    for ((i=0; i< ${#ipArr[@]};i++))
    do
        local loiface=`echo ${ipArr[$i]} | awk '{ print $1 }'`
        if [ "$loiface" = $dev ];then
            local loip=`echo ${ipArr[$i]} | awk '{ print $2}'`
            if [ "$loip" = $ip ];then
                #Not Modify
                #echo "[NOTHING       ] $dev:$ip  Not need Modify ..."
                return
            else
                #Modify eth
                echo "[MODIFY ROUTING] $dev:$loip to $ip..."
                ipArr[$i]="$dev $ip"
                ConfigMptcpRoute $dev $ip $mask $gw
                return
            fi
        fi
    done
    #NEW eth0
    echo "[NEW ROUTING   ] $dev:$ip"
    ipArr[${#ipArr[@]}]="$iface $ip"
    ConfigMptcpRoute $dev $ip $mask $gw
    return
}

CheckDown() {
    local dev=$1
    for ((i=0; i< ${#ipArr[@]};i++))
    do
        local loiface=`echo ${ipArr[$i]} | awk '{ print $1 }'`
        if [ "$loiface" = $dev ];then
            local loip=`echo ${ipArr[$i]} | awk '{ print $2}'`
            if [ ! -z "$loip" ];then
                echo "[DELETE ROUTING] $dev:$loip ..."
                Delete $dev
                ipArr[$i]="$dev"
                echo ${ipArr[@]}
            fi
        fi
    done

}


ConfigMptcpRoute() {
    local dev=$1
    local ip=$2
    local mask=$3
    local gw=$4
    local TableId=$(cat /sys/class/net/$dev/ifindex)
    
    ip rule del table $TableId 2>&1>/dev/null
    ip route flush table $TableId
    
    ip rule add from $ip table $TableId
    ip route add $ip dev $dev table $TableId
    ip route add default via $gw dev $dev table $TableId
}

Delete() {
    local dev=$1
    local TableId=$(cat /sys/class/net/$dev/ifindex)
    ip rule del table $TableId
    ip route flush table $TableId
}

 

if [ "$argv" = "start" ];then
    unset ipArr
    for ifpath in /sys/class/net/*; do
        iface=${ifpath##*/}
        if [[ "$iface" = 'lo' || "$ifpath/operstate" = 'down' ]];then
            continue
        fi

        ip=$(GetInterfaceIp $iface)
    
        ret=$(CheckIp $ip)
        if [ -z "$ret" ];then
            continue
        fi

        mask=$(GetInterfaceMask $iface)
        gw=$(GetInterfaceGw $iface)
        if [[ "$gw" = "0.0.0.0"  || -z "$gw" ]];then
            continue
        fi
        ConfigMptcpRoute $iface $ip $mask $gw
        echo "[NEW ROUTING   ] $dev:$ip"
        ipArr[${#ipArr[@]}]="$iface $ip"
    done
    while true
    do
        for ifpath in /sys/class/net/*; do
            iface=${ifpath##*/}
            if [ "$iface" = 'lo' ];then
                continue
            fi
            
            status=$(cat $ifpath/operstate)
            if [ "$status" = 'down' ];then
                CheckDown $iface
            fi
            
            ip=$(GetInterfaceIp $iface)

            ret=$(CheckIp $ip)
            if [ -z "$ret" ];then
                continue
            fi

            mask=$(GetInterfaceMask $iface)
            gw=$(GetInterfaceGw $iface)
            if [[ "$gw" = "0.0.0.0"  || -z "$gw" ]];then
                continue
            fi
            CheckModify $iface $ip $mask $gw
        done
        sleep 2
    done
elif [ "$argv" = "stop" ];then
    for ifpath in /sys/class/net/*; do
        iface=${ifpath##*/}
        if [ "$iface" = 'lo' ];then
            continue
        fi
        Delete $iface
    done
else
    echo "Command \"$1\" is unknown, Usage : sh start.sh < start | stop >"
fi
