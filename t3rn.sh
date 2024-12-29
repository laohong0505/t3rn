#!/bin/bash

# 定义仓库地址和目录名称
REPO_URL="git clone https://github.com/laohong0505/t3rn.git"
DIR_NAME="t3rn-bot"
PYTHON_FILE="keys_and_addresses.py"
DATA_BRIDGE_FILE="data_bridge.py"
BOT_FILE="bot.py"
VENV_DIR="t3rn-env"  # 虚拟环境目录

# 检查是否为 root 用户
if [ "$EUID" -ne 0 ]; then
    echo -e "请使用 sudo 运行此脚本"
    exit 1
fi

# 检查是否安装了 git
if ! command -v git &> /dev/null; then
    echo "Git 未安装，请先安装 Git。"
    exit 1
fi

# 检查是否安装了 python3-pip 和 python3-venv
if ! command -v pip3 &> /dev/null; then
    echo "pip 未安装，正在安装 python3-pip..."
    sudo apt update
    sudo apt install -y python3-pip
fi

if ! command -v python3 -m venv &> /dev/null; then
    echo "python3-venv 未安装，正在安装 python3-venv..."
    sudo apt update
    sudo apt install -y python3-venv
fi

# 拉取仓库
if [ -d "$DIR_NAME" ]; then
    echo "目录 $DIR_NAME 已存在，拉取最新更新..."
    cd "$DIR_NAME" || exit
    git pull origin main
else
    echo "正在克隆仓库 $REPO_URL..."
    git clone "$REPO_URL"
    cd "$DIR_NAME" || exit
fi

echo "已进入目录 $DIR_NAME"

# 创建虚拟环境并激活
if [ ! -d "$VENV_DIR" ]; then
    echo "正在创建虚拟环境..."
    python3 -m venv "$VENV_DIR"
fi
source "$VENV_DIR/bin/activate"

# 升级 pip
echo "正在升级 pip..."
pip install --upgrade pip

# 安装依赖
echo "正在安装依赖 web3 和 colorama..."
pip install web3 colorama

# 提醒用户私钥安全
echo "警告：请务必确保您的私钥安全！"
echo "私钥应当保存在安全的位置，切勿公开分享或泄漏给他人。"

echo "请输入您的私钥（多个私钥以空格分隔）："
read -r private_keys_input

echo "请输入您的标签（多个标签以空格分隔，与私钥顺序一致）："
read -r labels_input

echo "请输入每次转账的 GAS 费（单位：wei，以空格分隔，与私钥顺序一致）："
read -r gas_values_input

# 检查输入是否一致
IFS=' ' read -r -a private_keys <<< "$private_keys_input"
IFS=' ' read -r -a labels <<< "$labels_input"
IFS=' ' read -r -a gas_values <<< "$gas_values_input"

if [ "${#private_keys[@]}" -ne "${#labels[@]}" ] || [ "${#private_keys[@]}" -ne "${#gas_values[@]}" ]; then
    echo "私钥、标签和 GAS 费数量不一致，请重新运行脚本并确保它们匹配！"
    exit 1
fi

# 写入 keys_and_addresses.py 文件
echo "正在写入 $PYTHON_FILE 文件..."
cat > $PYTHON_FILE <<EOL
# 此文件由脚本生成

private_keys = [
$(printf "    '%s',\n" "${private_keys[@]}")
]

labels = [
$(printf "    '%s',\n" "${labels[@]}")
]

gas_values = [
$(printf "    '%s',\n" "${gas_values[@]}")
]
EOL

echo "$PYTHON_FILE 文件已生成。"

# 提醒用户私钥安全
echo "配置完成，正在运行 bot.py..."

# 创建或覆盖 bot.py 文件
cat > $BOT_FILE <<EOF
import time
import random
from web3 import Web3
from keys_and_addresses import private_keys, labels, gas_values

OP_RPC_URL = "https://optimism-sepolia.gateway.tenderly.co"
BASE_RPC_URL = "https://base-sepolia.gateway.tenderly.co"
TRANSFER_AMOUNT = Web3.toWei(0.1, 'ether')
MIN_BALANCE = Web3.toWei(0.1, 'ether')

chains = {
    "op": Web3(Web3.HTTPProvider(OP_RPC_URL)),
    "base": Web3(Web3.HTTPProvider(BASE_RPC_URL))
}

def check_balance(web3, address):
    return web3.eth.get_balance(address)

def transfer_funds(web3, private_key, sender, chain_name, gas_price):
    nonce = web3.eth.get_transaction_count(sender)
    tx = {
        'nonce': nonce,
        'to': sender,
        'value': TRANSFER_AMOUNT,
        'gas': 21000,
        'gasPrice': gas_price
    }
    signed_tx = web3.eth.account.sign_transaction(tx, private_key)
    tx_hash = web3.eth.send_raw_transaction(signed_tx.rawTransaction)
    print(f"{chain_name.upper()} 交易发送成功，交易哈希: {web3.toHex(tx_hash)}")

def main():
    while True:
        for i, private_key in enumerate(private_keys):
            label = labels[i]
            gas_price = int(gas_values[i])

            for chain_name, web3 in chains.items():
                sender = web3.eth.account.from_key(private_key).address
                balance = check_balance(web3, sender)
                print(f"钱包 {label} 在 {chain_name.upper()} 上的余额: {web3.fromWei(balance, 'ether')} ETH")

                if balance < MIN_BALANCE:
                    print(f"{chain_name.upper()} 上余额不足，跳过。")
                    continue

                try:
                    transfer_funds(web3, private_key, sender, chain_name, gas_price)
                except Exception as e:
                    print(f"{chain_name.upper()} 上的交易失败: {e}")

                delay = random.randint(20, 30)
                print(f"随机延迟 {delay} 秒后继续...")
                time.sleep(delay)

if __name__ == "__main__":
    main()
EOF

python3 $BOT_FILE
