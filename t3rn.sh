#!/bin/bash

# 脚本保存路径
SCRIPT_PATH="$HOME/t3rn.sh"

# 检查是否为root用户
if [ "$EUID" -ne 0 ]; then 
    echo -e "\033[31m请使用 sudo 运行此脚本\033[0m"
    exit 1
fi

# 定义必要的文件和目录
PYTHON_FILE="keys_and_addresses.py"
BOT_FILE="bot.py"
VENV_DIR="t3rn-env"  # 虚拟环境目录

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

# 创建虚拟环境并激活
echo "正在创建虚拟环境..."
python3 -m venv "$VENV_DIR"
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

# 让用户输入私钥和标签
echo "请输入您的私钥（多个私钥以空格分隔）："
read -r private_keys_input

echo "请输入您的标签（多个标签以空格分隔，与私钥顺序一致）："
read -r labels_input

echo "请输入每个钱包在 Base 链的 Gas 费（单位: wei，以空格分隔）："
read -r base_gas_values_input

echo "请输入每个钱包在 OP 链的 Gas 费（单位: wei，以空格分隔）："
read -r op_gas_values_input

# 检查输入是否一致
IFS=' ' read -r -a private_keys <<< "$private_keys_input"
IFS=' ' read -r -a labels <<< "$labels_input"
IFS=' ' read -r -a base_gas_values <<< "$base_gas_values_input"
IFS=' ' read -r -a op_gas_values <<< "$op_gas_values_input"

if [ "${#private_keys[@]}" -ne "${#labels[@]}" ] || \
   [ "${#private_keys[@]}" -ne "${#base_gas_values[@]}" ] || \
   [ "${#private_keys[@]}" -ne "${#op_gas_values[@]}" ]; then
    echo "私钥、标签、Base Gas 值和 OP Gas 值数量不一致，请重新运行脚本并确保它们匹配！"
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

base_gas_values = [
$(printf "    '%s',\n" "${base_gas_values[@]}")
]

op_gas_values = [
$(printf "    '%s',\n" "${op_gas_values[@]}")
]
EOL

echo "$PYTHON_FILE 文件已生成。"

# 生成 bot.py 脚本
echo "正在生成 bot.py 脚本..."
cat > $BOT_FILE <<'EOL'
import time
import random
from web3 import Web3
from keys_and_addresses import private_keys, labels, base_gas_values, op_gas_values

# 配置 RPC URL
BASE_RPC_URL = "https://base-sepolia.gateway.tenderly.co"
OP_RPC_URL = "https://optimism-sepolia.gateway.tenderly.co"

# 转账金额（单位: wei）
TRANSFER_AMOUNT = Web3.to_wei(0.1, 'ether')

# 初始化 Web3 客户端
base_web3 = Web3(Web3.HTTPProvider(BASE_RPC_URL))
op_web3 = Web3(Web3.HTTPProvider(OP_RPC_URL))

def check_balance(web3, address):
    return web3.eth.get_balance(address)

def send_transaction(web3, private_key, to_address, gas_price):
    account = web3.eth.account.from_key(private_key)
    nonce = web3.eth.get_transaction_count(account.address)
    transaction = {
        'to': to_address,
        'value': TRANSFER_AMOUNT,
        'gas': 21000,
        'gasPrice': gas_price,
        'nonce': nonce,
    }
    signed_tx = web3.eth.account.sign_transaction(transaction, private_key)
    tx_hash = web3.eth.send_raw_transaction(signed_tx.rawTransaction)
    return tx_hash

for i, private_key in enumerate(private_keys):
    label = labels[i]
    base_gas_price = int(base_gas_values[i])
    op_gas_price = int(op_gas_values[i])

    base_account = base_web3.eth.account.from_key(private_key)
    op_account = op_web3.eth.account.from_key(private_key)

    print(f"开始处理钱包: {label} ({base_account.address})")

    while True:
        # 检查 Base 链余额
        base_balance = check_balance(base_web3, base_account.address)
        if base_balance > TRANSFER_AMOUNT:
            print(f"{label}: 在 Base 上余额充足，开始转账到 OP...")
            tx_hash = send_transaction(base_web3, private_key, op_account.address, base_gas_price)
            print(f"Base -> OP 转账交易哈希: {tx_hash.hex()}")
        else:
            print(f"{label}: 在 Base 上余额不足，跳过转账。")

        time.sleep(random.randint(20, 30))

        # 检查 OP 链余额
        op_balance = check_balance(op_web3, op_account.address)
        if op_balance > TRANSFER_AMOUNT:
            print(f"{label}: 在 OP 上余额充足，开始转账到 Base...")
            tx_hash = send_transaction(op_web3, private_key, base_account.address, op_gas_price)
            print(f"OP -> Base 转账交易哈希: {tx_hash.hex()}")
        else:
            print(f"{label}: 在 OP 上余额不足，跳过转账。")

        time.sleep(random.randint(20, 30))
EOL

chmod +x $BOT_FILE

echo "bot.py 脚本已生成。"

echo "配置完成，运行以下命令启动脚本:"
echo "python3 $BOT_FILE"
