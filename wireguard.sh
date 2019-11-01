#!/bin/bash

wireguard_install_check(){
    if [[ $(lsmod | grep wireguard) != "" ]];then 
        echo '''

wireguard has been installed and loaded

'''
    else    
        linux_version=$(cat /etc/redhat-release)
        if [[ $linux_version =~ "Fedora" ]];then
            dnf copr enable jdoss/wireguard
            dnf install wireguard-dkms wireguard-tools
        elif [[ $linux_version =~ "CentOS" ]] || [[ $linux_version =~ "Red" ]];then
            echo '''
wireguard is not installed, do the following step to install

1 check kernel kernel-headers kernel-devel, these must be the same verison
  if not the same, try yum update, or download the rpm package of the same version as kernel to install

2 sudo curl -Lo /etc/yum.repos.d/wireguard.repo https://copr.fedorainfracloud.org/coprs/jdoss/wireguard/repo/epel-7/jdoss-wireguard-epel-7.repo
  yum install epel-release
  yum install wireguard-dkms wireguard-tools
3 if not load properly,try this
      dkms status
      dkms add wireguard/xxxxxx #the version number get from "dkms status"
      dkms build wireguard/xxxxxx
      dkms install wireguard/xxxxxxx
      modprobe wireguard
  check again
   
'''
        else
            echo '''

For CentOS7 , Fedora and Red Hat Linux only

'''
            exit
        fi

    fi 
    }


first_install(){
    if [ ! -d "/etc/wireguard" ];then
        mkdir /etc/wireguard
    fi
    cd $config_dir
    umask 077
    wg genkey | tee server_private_key | wg pubkey > server_public_key

    read -p "Enter the name of the client config: " client_name
    wg genkey | tee $client_name"_private_key" | wg pubkey > $client_name"_public_key"
    
    read -p "Enter the address/mask(default 10.5.0.1/24): " address
    if [ -z "$address" ];then
        address=10.5.0.1/24
    fi
    
    read -p "Enter the listen port(default random a number in 10000-65535):" listen_port
    if [ -z "$listen_port" ];then
        listen_port=0
        until [[ $listen_port -gt 10000 ]]
        do
            listen_port=$((RANDOM*2+1))
        done
    fi
    
    echo address:$address > prepare_info.yml
    echo listen_port:$listen_port >> prepare_info.yml
    echo client_name:$client_name >> prepare_info.yml
    echo server_private_key:$(cat server_private_key) >> prepare_info.yml
    echo server_public_key:$(cat server_public_key) >> prepare_info.yml
    echo $client_name"_private_key":$(cat $client_name"_private_key") >> prepare_info.yml
    echo $client_name"_public_key":$(cat $client_name"_public_key") >> prepare_info.yml

    #address=$(cat prepare_info.yml | awk -F: '/address/{ print $2 }')
    #listen_port=$(cat prepare_info.yml | awk -F: '/listen_port/{ print $2 }')
    #client_name=$(cat prepare_info.yml | awk -F: '/client_name/{ print $2 }')
    cat > $config_dir/wg0.conf <<EOF
[Interface]
PrivateKey = $(cat server_private_key)
Address = $address
ListenPort = $listen_port

# $client_name
[Peer]
PublicKey = $(cat $client_name"_public_key")
AllowedIPs = $(echo $address | awk -F/ '{print $1}' | awk -F. '{print $1"."$2"."$3"."($4+1)}')/32
EOF
    
    cat > $config_dir/$client_name".conf" << EOF
[Interface]
PrivateKey = $(cat $client_name"_private_key")
Address = $(echo $address | awk -F/ '{print $1}' | awk -F. '{print $1"."$2"."$3"."($4+1)}')/24
MTU = 1420

[Peer]
PublicKey = $(cat server_public_key)
Endpoint = xxxx.xxxx.xxxx:$listen_port
AllowedIPs = $(echo $address | awk -F/ '{print $1"/32"}')
PersistentKeepalive = 25
EOF
    }


set_firewalld(){
    cd $config_dir
    port_now_added=$(firewall-cmd --zone=$zone --list-ports)
    listen_port=$(cat prepare_info.yml | awk -F: '/listen_port/{ print $2 }')
    check_port_status=`firewall-cmd --list-all | grep $listen_port`
    if [ ! -z "$port_now_added" ] && [[ "$check_port_status" == "" ]];then 
        read -p "For firewalld only, set the zone(default public):" zone
        if [ -z $zone ];then
            zone=public
        fi

        firewall-cmd --zone=$zone --add-port=$listen_port/udp --permanent
        firewall-cmd --zone=$zone --permanent --add-masquerade  
        firewall-cmd --reload
    else
        echo '''
        
Port has already added to firewalld

'''
    fi
    }

add_user(){
    
    cd $config_dir
    read -p "Enter the name of new user: " new_client_name
    wg genkey | tee $new_client_name"_private_key" | wg pubkey > $new_client_name"_public_key"
    address=$(cat prepare_info.yml | awk -F: '/address/{ print $2 }')
    listen_port=$(cat prepare_info.yml | awk -F: '/listen_port/{ print $2 }')
    num=$(cat wg0.conf | grep Peer | wc -l)
    list=`cat wg0.conf | grep "AllowedIPs = " | awk '{print $3}'|awk -F/ '{print $1}'| awk -F. '{print $4}'`
    for i in $list
    do 
        if [[ "$((num+2))" == "$i" ]];then 
            num=$((num+1))
        fi
    done

    #server_private_key=$(cat server_private_key )
    #server_public_key=$(cat server_public_key)
    #$new_client_name"private_key"=$(cat $new_client_name"_private_key")
    #$new_client_name"public_key"=$(cat $new_client_name"_public_key")
    
    cat >> $config_dir/wg0.conf <<EOF
# $new_client_name
[Peer]
PublicKey = $(cat $new_client_name"_public_key")
AllowedIPs = $(echo $address | awk -F/ '{print $1}' | awk -F. '{print $1"."$2"."$3"."($4+"'$num'"+1)}')/32
EOF
    chmod 600 /etc/wireguard/wg0.conf
    echo """
    
add user $new_client_name to wg0.conf successfully.
"""

    cat > $config_dir/$new_client_name".conf" << EOF
[Interface]
PrivateKey = $(cat $new_client_name"_private_key")
Address = $(echo $address | awk -F/ '{print $1}' | awk -F. '{print $1"."$2"."$3"."($4+"'$num'"+1)}')/24
MTU = 1420

[Peer]
PublicKey = $(cat server_public_key)
Endpoint = xxxx.xxxx.xxxx:$listen_port
AllowedIPs = $(echo $address | awk -F/ '{print $1}' | awk -F. '{print $1"."$2"."$3".0"}')/24
PersistentKeepalive = 25
EOF
    echo """
create $new_client_name".conf" successfully.

"""
    }

del_user(){
    
    cd $config_dir
    read -p "Enter the name of the user: " name
    user_exists=$(cat wg0.conf | grep $name)
    if [ ! -z "$user_exists" ];then
        sed -n '/# '$name'/,+5d;p' wg0.conf | cat > tmp.conf
        mv tmp.conf wg0.conf
        chmod 600 /etc/wireguard/wg0.conf
        echo """

delete user $name from wg0.conf

"""

        for file in $name".conf" $name"_private_key" $name"_public_key"
        do
            echo """
delete $file

"""
            rm -rf $file
        done
    else
        echo '''

no such user in config file.

'''
    fi

    }

restart_wg0(){
    
    wg-quick down wg0
    wg-quick up wg0
    
    }


config_dir=/etc/wireguard/

index=0
until [[ $index -eq 7 ]]
do
    echo "===== MENU ====="
    echo "1) wireguard install check "
    echo "2) first install "
    echo "3) set firewalld "
    echo "4) add user " 
    echo "5) del user"
    echo "6) restart wg0" 
    echo "7) exit" 
    read -p "Enter a number: " index
    case $index in
        1)
        wireguard_install_check;;
        2)
        first_install;;
        3)
        set_firewalld;;
        4)
        add_user;;
        5)
        del_user;;
        6)
        restart_wg0;;
        7)
        exit;;
    esac
done
    


