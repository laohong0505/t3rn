# 导入 Web3 库
from web3 import Web3
from eth_account import Account
import time
import os
import random  # 引入随机模块

# 数据桥接配置
from data_bridge import data_bridge
from keys_and_addresses import private_keys, labels
from network_config import networks

# 文本居中函数
def center_text(text):
    terminal_width = os.get_terminal_size().columns
    lines = text.splitlines()
    centered_lines = [line.center(terminal_width) for line in lines]
    return "\n".join(centered_lines)

# 清理终端函数
def clear_terminal():
    os.system('cls' if os.name == 'nt' else 'clear')

description = """
自动桥接机器人  https://bridge.t1rn.io/
"""

# 每个链的颜色和符号
chain_symbols = {
    'Base': '\033[34m',  # Base 链颜色
    'OP Sepolia': '\033[91m',         
}

# 颜色定义
green_color = '\033[92m'
reset_color = '\033[0m'
menu_color = '\033[95m'  # 菜单文本颜色

# 每个网络的区块浏览器URL
explorer_urls = {
    'Base': 'https://base-sepolia-rpc.publicnode.com', 
    'OP Sepolia': 'https://sepolia-optimism.etherscan.io/tx/',
    'BRN': 'https://brn.explorer.caldera.xyz/tx/'
}

# 获取 BRN 余额的函数
def get_brn_balance(web3, my_address):
    balance = web3.eth.get_balance(my_address)
    return web3.from_wei(balance, 'ether')

# 检查链的余额函数
def check_balance(web3, my_address):
    balance = web3.eth.get_balance(my_address)
    return web3.from_wei(balance, 'ether')

# 创建和发送交易的函数
def send_bridge_transaction(web3, account, my_address, data, network_name):
    nonce = web3.eth.get_transaction_count(my_address, 'pending')
    value_in_ether = 0.1
    value_in_wei = web3.to_wei(value_in_ether, 'ether')

    try:
        gas_estimate = web3.eth.estimate_gas({
            'to': networks[network_name]['contract_address'],
            'from': my_address,
            'data': data,
            'value': value_in_wei
        })
        gas_limit = gas_estimate + 50000  # 增加安全边际
    except Exception as e:
        print(f"估计gas错误: {e}")
        return None

    # 动态获取链上实时 gas 价格
    try:
        gas_price = web3.eth.gas_price
    except Exception as e:
        print(f"获取链上实时 gas 价格失败: {e}")
        return None

    transaction = {
        'nonce': nonce,
        'to': networks[network_name]['contract_address'],
        'value': value_in_wei,
        'gas': gas_limit,
        'gasPrice': gas_price,
        'chainId': networks[network_name]['chain_id'],
        'data': data
    }

    try:
        signed_txn = web3.eth.account.sign_transaction(transaction, account.key)
    except Exception as e:
        print(f"签名交易错误: {e}")
        return None

    try:
        tx_hash = web3.eth.send_raw_transaction(signed_txn.raw_transaction)
        tx_receipt = web3.eth.wait_for_transaction_receipt(tx_hash)

        # 获取最新余额
        balance = web3.eth.get_balance(my_address)
        formatted_balance = web3.from_wei(balance, 'ether')

        # 获取区块浏览器链接
        explorer_link = f"{explorer_urls[network_name]}{web3.to_hex(tx_hash)}"

        # 显示交易信息
        print(f"{green_color}📤 发送地址: {account.address}")
        print(f"⛽ 使用Gas: {tx_receipt['gasUsed']}")
        print(f"🗳️  区块号: {tx_receipt['blockNumber']}")
        print(f"💰 ETH余额: {formatted_balance} ETH")
        brn_balance = get_brn_balance(Web3(Web3.HTTPProvider('https://brn.rpc.caldera.xyz/http')), my_address)
        print(f"🔵 BRN余额: {brn_balance} BRN")
        print(f"🔗 区块浏览器链接: {explorer_link}\n{reset_color}")

        return web3.to_hex(tx_hash), value_in_ether
    except Exception as e:
        print(f"发送交易错误: {e}")
        return None, None

# 在特定网络上处理交易的函数
def process_network_transactions(network_name, bridges, chain_data, successful_txs):
    web3 = Web3(Web3.HTTPProvider(chain_data['rpc_url']))

    while not web3.is_connected():
        print(f"无法连接到 {network_name}，正在尝试重新连接...")
        time.sleep(5)  # 等待 5 秒后重试
        web3 = Web3(Web3.HTTPProvider(chain_data['rpc_url']))
    
    print(f"成功连接到 {network_name}")

    for bridge in bridges:
        for i, private_key in enumerate(private_keys):
            account = Account.from_key(private_key)
            my_address = account.address

            data = data_bridge.get(bridge)
            if not data:
                print(f"桥接 {bridge} 数据不可用!")
                continue

            result = send_bridge_transaction(web3, account, my_address, data, network_name)
            if result:
                tx_hash, value_sent = result
                successful_txs += 1

                if value_sent is not None:
                    print(f"{chain_symbols[network_name]}🚀 成功交易总数: {successful_txs} | {labels[i]} | 桥接: {bridge} | 桥接金额: {value_sent:.5f} ETH ✅{reset_color}\n")
                else:
                    print(f"{chain_symbols[network_name]}🚀 成功交易总数: {successful_txs} | {labels[i]} | 桥接: {bridge} ✅{reset_color}\n")

                print(f"{'='*150}")
                print("\n")
            
            # 随机等待 20 到 30 秒
            wait_time = random.uniform(20, 30)
            print(f"⏳ 等待 {wait_time:.2f} 秒后继续...\n")
            time.sleep(wait_time)

    return successful_txs

# 主函数
def main():
    print("\033[92m" + center_text(description) + "\033[0m")
    print("\n\n")

    successful_txs = 0
    current_network = 'Base'
    alternate_network = 'OP Sepolia'

    while True:
        web3 = Web3(Web3.HTTPProvider(networks[current_network]['rpc_url']))

        while not web3.is_connected():
            print(f"无法连接到 {current_network}，正在尝试重新连接...")
            time.sleep(5)
            web3 = Web3(Web3.HTTPProvider(networks[current_network]['rpc_url']))

        print(f"成功连接到 {current_network}")

        my_address = Account.from_key(private_keys[0]).address
        balance = check_balance(web3, my_address)

        if balance < 0.1:
            print(f"{chain_symbols[current_network]}{current_network}余额不足 0.1 ETH，切换到 {alternate_network}{reset_color}")
            current_network, alternate_network = alternate_network, current_network

        successful_txs = process_network_transactions(current_network, ["Base - OP Sepolia"] if current_network == 'Base' else ["OP - Base"], networks[current_network], successful_txs)
        time.sleep(random.uniform(20, 30))

if __name__ == "__main__":
    main()
