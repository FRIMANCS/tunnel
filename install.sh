#!/bin/bash

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

SYS_PATH="/etc/sysctl.conf"
PROF_PATH="/etc/profile"

function LOGE() {
    echo -e "${red}[ERROR] $* ${plain}"
}

function LOGI() {
    echo -e "${green}[INFO] $* ${plain}"
}

if [[ $EUID -ne 0 ]]; then
    LOGE "خطا: شما باید با کاربر root اجرا کنید!"
    exit 1
fi

install_xui() {
    VERSION=v2.4.0
    bash <(curl -fsSL "https://raw.githubusercontent.com/mhsanaei/3x-ui/$VERSION/install.sh") $VERSION <<EOF
y
EOF

    if [[ $? -eq 0 ]]; then
        LOGI "✅ نصب با موفقیت انجام شد!"
        show_panel_info
    else
        LOGE "❌ خطا در نصب X-UI!"
        exit 1
    fi
}

show_panel_info() {
    USERNAME=$(/usr/local/x-ui/x-ui setting -show true | grep -Eo 'username: [^ ]+' | awk '{print $2}')
    PASSWORD=$(/usr/local/x-ui/x-ui setting -show true | grep -Eo 'password: [^ ]+' | awk '{print $2}')
    PORT=$(/usr/local/x-ui/x-ui setting -show true | grep -Eo 'port: [0-9]+' | awk '{print $2}')
    SERVER_IP=$(curl -s https://api.ipify.org)

    echo -e "${green}✅ اطلاعات ورود به پنل:${plain}"
    echo -e "🌐 آدرس پنل: ${yellow}http://${SERVER_IP}:${PORT}${plain}"
    echo -e "👤 نام کاربری: ${green}${USERNAME}${plain}"
    echo -e "🔑 رمز عبور: ${green}${PASSWORD}${plain}"
    echo -e "🚀 لطفاً این اطلاعات را ذخیره کنید!"
}

sysctl_optimizations() {
    cp $SYS_PATH /etc/sysctl.conf.bak
    cat <<EOF >> $SYS_PATH
fs.file-max = 67108864
net.core.default_qdisc = fq_codel
net.core.netdev_max_backlog = 32768
net.core.optmem_max = 262144
net.core.somaxconn = 65536
net.core.rmem_max = 33554432
net.core.wmem_max = 33554432
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_fin_timeout = 25
net.ipv4.tcp_keepalive_time = 1200
vm.swappiness = 10
vm.vfs_cache_pressure = 250
EOF

    sysctl -p > /dev/null 2>&1
    LOGI "✅ تنظیمات sysctl اعمال شد."
}

limits_optimizations() {
    echo "ulimit -n 1048576" >> $PROF_PATH
    LOGI "✅ محدودیت‌های سیستم اعمال شد."
}

optimize_network_system() {
    sysctl_optimizations
    limits_optimizations
}

a_reboot() {
    echo -ne "${yellow}سرور در حال ریستارت است...${plain}"
    reboot
}

block_abuse_ips() {
    IP_RANGES=(
        "10.0.0.0/8"
        "100.64.0.0/10"
        "169.254.0.0/16"
        "172.16.0.0/12"
        "192.0.0.0/24"
        "192.0.2.0/24"
        "192.88.99.0/24"
        "192.168.0.0/16"
        "198.18.0.0/15"
        "198.51.100.0/24"
        "203.0.113.0/24"
        "240.0.0.0/24"
        "224.0.0.0/4"
        "233.252.0.0/24"
        "102.0.0.0/8"
        "185.235.86.0/24"
        "185.235.87.0/24"
        "114.208.187.0/24"
        "216.218.185.0/24"
        "206.191.152.0/24"
        "45.14.174.0/24"
        "195.137.167.0/24"
        "103.58.50.1/24"
        "25.0.0.0/19"
        "25.29.155.0/24"
        "103.29.38.0/24"
        "103.49.99.0/24"
    )

    if ! command -v iptables &> /dev/null; then
        LOGE "iptables نصب نشده است. نصب می‌شود."
        apt-get update
        apt-get install -y iptables
    fi

    for IP in "${IP_RANGES[@]}"; do
        if ! iptables -L INPUT -n | grep -q "$IP"; then
            iptables -A INPUT -s "$IP" -j DROP
            iptables -A OUTPUT -d "$IP" -j DROP
 
        else
            LOGI "رنج آیپی ابیوز آپدیت شد."
        fi
    done

    iptables-save > /etc/iptables/rules.v4
    LOGI "✅ رنج‌های IP آزاردهنده (Abuse) با موفقیت مسدود شدند."
}

add_rc_local() {
    read -p "آیپی سرور مقصد برای برقراری rc.local وارد کنید: " server_ip
   read -p "آدرس IPv6 لوکال خود را وارد کنید (eg : 2a14:f010::2): " ipv6_address

    ipv4_regex="^([0-9]{1,3}\.){3}[0-9]{1,3}$"


    if [[ ! $server_ip =~ $ipv4_regex ]]; then
        LOGE "آدرس IPv4 وارد شده معتبر نیست! لطفاً یک آدرس IPv4 صحیح وارد کنید."
        exit 1
    fi
    if [[ -z "$server_ip" || -z "$ipv6_address" ]]; then
        LOGE "آدرس IP یا IPv6 وارد نشده است. عملیات متوقف می‌شود."
        exit 1
    fi

    if [[ -f /etc/rc.local ]]; then
        backup_file="/etc/rc.local.$(date +%Y%m%d%H%M%S).bak"
        cp /etc/rc.local "$backup_file"
        LOGI "✅ یک بکاپ از فایل rc.local با نام $backup_file گرفته شد."
    fi

    echo "#! /bin/bash" > /etc/rc.local
    echo "sudo ip tunnel add tun mode sit remote $server_ip local $(curl -s https://api.ipify.org) ttl 126" >> /etc/rc.local
    echo "sudo ip link set dev tun up mtu 1500" >> /etc/rc.local
    echo "sudo ip addr add $ipv6_address/64 dev tun" >> /etc/rc.local
    echo "sudo ip link set tun mtu 1500" >> /etc/rc.local
    echo "sudo ip link set tun up" >> /etc/rc.local

    chmod +x /etc/rc.local
    LOGI "✅ فایل /etc/rc.local ساخته شد و مجوزهای لازم اعمال شد."
}
replace_xui_db_from_github() {
    GITHUB_URL="https://github.com/FRIMANCS/tunne/raw/main/file/x-ui.db"   # لینک مستقیم به فایل x-ui.db در گیت‌هاب
    DESTINATION_FILE="/etc/x-ui/x-ui.db"  # مسیر مقصد برای فایل

    # دانلود فایل از گیت‌هاب
    echo -e "${yellow}در حال دانلود فایل x-ui.db از گیت‌هاب...${plain}"
    curl -fsSL "$GITHUB_URL" -o "$DESTINATION_FILE"

    # بررسی اینکه آیا دانلود موفقیت‌آمیز بوده است
    if [[ $? -eq 0 ]]; then
        echo -e "${green}✅ فایل x-ui.db با موفقیت از گیت‌هاب دانلود و جایگزین شد!${plain}"
    else
        echo -e "${red}خطا: دانلود فایل از گیت‌هاب با مشکل مواجه شد!${plain}"
        exit 1
    fi
}


install_xui
optimize_network_system
block_abuse_ips
add_rc_local
replace_xui_db_from_github
a_reboot
