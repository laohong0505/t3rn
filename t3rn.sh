import time
import random
from web3 import Web3
from keys_and_addresses import private_keys, labels
from data_bridge import data_bridge
from colorama import Fore, Style

# 用户设置的 Gas 价格（单位：gwei）
GAS_PRICE = int(input("请输入自定义 Gas 价格（单位: gwei）："))

# 转账金额（单位：wei）
TRANSFER_AMOUNT = Web3.to_wei(0.1, "ether")

# 随机延迟范围（单位：秒）
DELAY_RANGE = (20, 30)

# Base 和 OP 的 RPC 地址
RPC_URLS = {
    "Base": "https://base-sepolia.gateway.tenderly.co",
    "OP": "https://optimism-sepolia.gateway.tenderly.co",
}

# 初始化 Web3 客户端
web3_clients = {
    chain: Web3(Web3.HTTPProvider(url)) for chain, url in RPC_URLS.items()
}

for chain, client in web3_clients.items():
    if not client.is_connected():
        print(Fore.RED + f"无法连接到 {chain} 节点。请检查 RPC 地址是否正确。" + Style.RESET_ALL)
        exit(1)

print(Fore.GREEN + "成功连接到所有链的节点！" + Style.RESET_ALL)

# 获取用户地址
addresses = [web3_clients["Base"].eth.account.from_key(key).address for key in private_keys]

# 检查余额函数
def get_balance(client, address):
    return client.eth.get_balance(address)

# 构建交易函数
def build_transaction(client, from_address, to_address, private_key):
    nonce = client.eth.get_transaction_count(from_address)
    transaction = {
        "to": to_address,
        "value": TRANSFER_AMOUNT,
        "gas": 21000,
        "gasPrice": Web3.to_wei(GAS_PRICE, "gwei"),
        "nonce": nonce,
    }
    signed_txn = client.eth.account.sign_transaction(transaction, private_key)
    return signed_txn

# 执行转账函数
def execute_transfer(from_chain, to_chain, from_index):
    from_client = web3_clients[from_chain]
    to_client = web3_clients[to_chain]

    from_address = addresses[from_index]
    to_address = addresses[from_index]  # 本地址互转
    private_key = private_keys[from_index]

    balance = get_balance(from_client, from_address)

    print(Fore.YELLOW + f"{labels[from_index]} 在 {from_chain} 的余额为 {Web3.from_wei(balance, 'ether')} ETH" + Style.RESET_ALL)

    if balance < TRANSFER_AMOUNT + Web3.to_wei(GAS_PRICE * 21000, "gwei"):
        print(Fore.RED + f"{labels[from_index]} 在 {from_chain} 上的余额不足，跳过此操作。" + Style.RESET_ALL)
        return False

    try:
        signed_txn = build_transaction(from_client, from_address, to_address, private_key)
        tx_hash = from_client.eth.send_raw_transaction(signed_txn.rawTransaction)
        print(Fore.GREEN + f"转账交易已发送！交易哈希: {tx_hash.hex()}" + Style.RESET_ALL)

        receipt = from_client.eth.wait_for_transaction_receipt(tx_hash)
        if receipt.status == 1:
            print(Fore.GREEN + f"交易成功！区块哈希: {receipt.blockHash.hex()}" + Style.RESET_ALL)
            return True
        else:
            print(Fore.RED + "交易失败！" + Style.RESET_ALL)
            return False
    except Exception as e:
        print(Fore.RED + f"交易过程中出现错误: {str(e)}" + Style.RESET_ALL)
        return False

# 主函数
if __name__ == "__main__":
    while True:
        for i in range(len(private_keys)):
            if execute_transfer("Base", "OP", i):
                time.sleep(random.randint(*DELAY_RANGE))

            if execute_transfer("OP", "Base", i):
                time.sleep(random.randint(*DELAY_RANGE))
