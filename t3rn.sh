#!/bin/bash

# 检查是否为 root 用户
if [ "$EUID" -ne 0 ]; then 
    echo -e "\e[31m请使用 sudo 运行此脚本\e[0m"
    exit 1
fi

# 仓库配置
DIR_NAME="t3rn-bot"
PYTHON_FILE="keys_and_addresses.py"
DATA_BRIDGE_FILE="data_bridge.py"
BOT_FILE="bot.py"
VENV_DIR="t3rn-env"  # 虚拟环境目录

# 检查并安装必要依赖
echo "检查系统依赖..."
sudo apt update
sudo apt install -y git python3 python3-pip python3-venv

# 创建目录结构
if [ ! -d "$DIR_NAME" ]; then
    echo "创建脚本目录 $DIR_NAME..."
    mkdir "$DIR_NAME"
fi

cd "$DIR_NAME" || exit

# 创建虚拟环境
if [ ! -d "$VENV_DIR" ]; then
    echo "创建虚拟环境..."
    python3 -m venv "$VENV_DIR"
fi

echo "激活虚拟环境..."
source "$VENV_DIR/bin/activate"

# 安装 Python 依赖
echo "安装依赖..."
pip install --upgrade pip
pip install web3 colorama

# 用户配置私钥和标签
echo "请输入您的私钥（多个私钥以空格分隔）："
read -r private_keys_input

echo "请输入您的标签（多个标签以空格分隔，与私钥顺序一致）："
read -r labels_input

# 检查输入是否一致
IFS=' ' read -r -a private_keys <<< "$private_keys_input"
IFS=' ' read -r -a labels <<< "$labels_input"

if [ "${#private_keys[@]}" -ne "${#labels[@]}" ]; then
    echo "私钥和标签数量不一致，请重新运行脚本并确保它们匹配！"
    exit 1
fi

# 写入 keys_and_addresses.py 文件
echo "写入 $PYTHON_FILE..."
cat > $PYTHON_FILE <<EOL
# 此文件由脚本生成

private_keys = [
$(printf "    '%s',\n" "${private_keys[@]}")
]

labels = [
$(printf "    '%s',\n" "${labels[@]}")
]
EOL

# 用户配置桥接参数
echo "请输入 Base 到 OP 的桥接合约地址："
read -r base_op_value

echo "请输入 OP 到 Base 的桥接合约地址："
read -r op_base_value

# 写入 data_bridge.py 文件
echo "写入 $DATA_BRIDGE_FILE..."
cat > $DATA_BRIDGE_FILE <<EOL
# 此文件由脚本生成

data_bridge = {
    # Base 到 OP 的桥接数据
    "Base - OP": "$base_op_value",

    # OP 到 Base 的桥接数据
    "OP - Base": "$op_base_value",
}
EOL

# 创建 bot.py 主程序
echo "生成 $BOT_FILE..."
cat > $BOT_FILE <<'EOL'
import time
import random
from web3 import Web3
from colorama import Fore, Style
from keys_and_addresses import private_keys, labels
from data_bridge import data_bridge

# 配置链的 RPC 地址
RPC_ENDPOINTS = {
    "Base": "https://base-sepolia.gateway.tenderly.co",
    "OP": "https://optimism-sepolia.gateway.tenderly.co"
}

# 手动设置 gas 费用
GAS_PRICE = int(input("请输入每链的 gas 费用（以 Gwei 为单位）：")) * (10 ** 9)

# 转账金额 (0.1 ETH)
TRANSFER_AMOUNT = Web3.toWei(0.1, "ether")

# 初始化 Web3 对象
web3 = {chain: Web3(Web3.HTTPProvider(url)) for chain, url in RPC_ENDPOINTS.items()}

# 检查连接状态
for chain, conn in web3.items():
    if not conn.is_connected():
        print(Fore.RED + f"无法连接到 {chain} 链的 RPC，请检查配置。" + Style.RESET_ALL)
        exit(1)

def transfer_eth(chain_from, chain_to, private_key, label):
    account = web3[chain_from].eth.account.privateKeyToAccount(private_key)
    balance = web3[chain_from].eth.get_balance(account.address)

    print(Fore.CYAN + f"{label} 当前在 {chain_from} 链的余额为 {Web3.fromWei(balance, 'ether')} ETH" + Style.RESET_ALL)

    if balance < TRANSFER_AMOUNT:
        print(Fore.YELLOW + f"{label} 在 {chain_from} 链的余额不足，跳过操作。" + Style.RESET_ALL)
        return False

    # 构建交易
    nonce = web3[chain_from].eth.get_transaction_count(account.address)
    tx = {
        "nonce": nonce,
        "to": account.address,  # 自己转账到自己
        "value": TRANSFER_AMOUNT,
        "gas": 21000,
        "gasPrice": GAS_PRICE,
        "chainId": web3[chain_from].eth.chain_id
    }

    # 签名交易
    signed_tx = web3[chain_from].eth.account.sign_transaction(tx, private_key)
    tx_hash = web3[chain_from].eth.send_raw_transaction(signed_tx.rawTransaction)

    print(Fore.GREEN + f"{label} 从 {chain_from} 转账到 {chain_to} 的交易已发送。" + Style.RESET_ALL)
    print(F"交易哈希: {tx_hash.hex()}")

    return True

while True:
    for i, private_key in enumerate(private_keys):
        label = labels[i]
        transfer_eth("Base", "OP", private_key, label)
        time.sleep(random.randint(20, 30))
        transfer_eth("OP", "Base", private_key, label)
        time.sleep(random.randint(20, 30))
EOL

echo "脚本生成完成，开始运行 bot.py..."
python3 $BOT_FILE
