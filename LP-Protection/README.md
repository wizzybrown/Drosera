# Liquidity Protection Trap 🛡️

A Drosera Network trap that monitors a user's liquidity position in a liquidity pool and triggers automatic withdrawal when the position drops by 50% or more.

## 📋 Table of Contents

- [Features](#features)
- [Architecture](#architecture)  
- [Installation](#installation)
- [Configuration](#configuration)
- [Deployment](#deployment)
- [Usage](#usage)
- [Testing](#testing)
- [Security Considerations](#security-considerations)
- [Customization](#customization)

## ✨ Features

- 🔍 **Real-time Monitoring**: Continuously monitors liquidity positions through event tracking
- ⚡ **Automatic Triggers**: Executes emergency withdrawal when position drops by 50%+
- 🛡️ **Protection**: Helps prevent further losses during market volatility
- 📊 **Event Tracking**: Monitors Mint, Burn, and Sync events from liquidity pools
- 🔐 **Access Control**: Secure response contract with proper authorization
- 📈 **Preview Functionality**: Check potential withdrawal amounts without executing

## 🏗️ Architecture

### Components

1. **LiquidityProtectionTrap.sol**: Main trap contract that monitors events
2. **LiquidityWithdrawer.sol**: Response contract that handles emergency withdrawals
3. **Trap.sol**: Base contract from Drosera Network

### How It Works

1. **Monitoring**: The trap watches for liquidity-related events (Mint/Burn) from the specified pool
2. **Tracking**: Maintains state of the user's initial and current liquidity position
3. **Analysis**: Calculates percentage drop from initial deposit
4. **Response**: Triggers automatic withdrawal when drop >= 50%

## 🚀 Installation

### Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- [Drosera CLI](https://app.drosera.io/install)
- [Bun](https://bun.sh/) or [Node.js](https://nodejs.org/)

### Setup

1. **Clone this repository**:
   ```bash
   git clone <your-repo-url>
   cd liquidity-protection-trap
   ```

2. **Install dependencies**:
   ```bash
   bun install  # or npm install
   ```

3. **Install Foundry dependencies**:
   ```bash
   forge install
   ```

4. **Set up environment variables**:
   ```bash
   cp .env.example .env
   # Edit .env with your configuration
   ```

## ⚙️ Configuration

### Environment Variables

Create a `.env` file with:

```bash
# Deployment
PRIVATE_KEY=0x...
MONITORED_USER=0x...          # User address to monitor
LIQUIDITY_POOL=0x...          # LP contract address

# RPC URLs
MAINNET_RPC_URL=https://eth-mainnet.g.alchemy.com/v2/YOUR_KEY
GOERLI_RPC_URL=https://eth-goerli.g.alchemy.com/v2/YOUR_KEY
HOODI_RPC_URL=https://rpc.hoodi.ethpandaops.io

# API Keys
ALCHEMY_API_KEY=your_alchemy_key
ETHERSCAN_API_KEY=your_etherscan_key
```

### drosera.toml Configuration

Update `drosera.toml` with your deployed contract addresses:

```toml
[trap]
path = "out/LiquidityProtectionTrap.sol/LiquidityProtectionTrap.json"
response_contract = "0x..." # Your deployed LiquidityWithdrawer address
response_function = "emergencyWithdraw(address,address,uint256,uint256)"

[constructor_args]
monitored_user = "0x..."  # User to monitor
liquidity_pool = "0x..."  # LP contract (e.g., Uniswap V2 pair)
```

### Popular Pool Addresses

```toml
# Uniswap V2 Examples:
# USDC/ETH: 0xB4e16d0168e52d35CaCD2c6185b44281Ec28C9Dc
# WBTC/ETH: 0xBb2b8038a1640196FbE3e38816F3e67Cba72D940
# DAI/ETH: 0xA478c2975Ab1Ea89e8196811F51A7B7Ade33eB11
```

## 🚀 Deployment

### Step 1: Deploy Contracts

```bash
# Compile contracts
forge build

# Deploy to testnet first
npm run deploy:goerli

# Deploy to mainnet
npm run deploy:mainnet
```

### Step 2: Configure Drosera

```bash
# Update drosera.toml with deployed addresses
# Then deploy the trap
DROSERA_PRIVATE_KEY=0x... drosera apply
```

### Step 3: Set Permissions

1. **Authorize Drosera operators** in the LiquidityWithdrawer contract
2. **User must approve** the LiquidityWithdrawer to spend their LP tokens

```solidity
// User needs to call this on the LP token:
lpToken.approve(liquidityWithdrawerAddress, type(uint256).max);
```

## 📖 Usage

### Monitoring Active

Once deployed and configured:

1. The trap automatically monitors the specified liquidity pool
2. Tracks the user's liquidity position changes
3. Calculates percentage drops from initial deposit
4. Triggers emergency withdrawal when drop >= 50%

### Manual Operations

```bash
# Check trap status
drosera status

# View logs
drosera logs

# Update trap configuration
drosera apply
```

## 🧪 Testing

Run the test suite:

```bash
# Run all tests
forge test

# Run with verbosity
forge test -vv

# Run specific test
forge test --match-test testShouldRespondWithSignificantDrop

# Run coverage
forge coverage
```

## 🔒 Security Considerations

### Access Control

- Only authorized addresses can trigger withdrawals
- Owner can add/remove authorized callers
- Emergency recovery functions for stuck tokens

### User Requirements

- Users must pre-approve the LiquidityWithdrawer contract
- Consider using permit-based approvals for better UX
- Monitor gas costs for frequent operations

### Best Practices

1. **Test thoroughly** on testnets before mainnet deployment
2. **Monitor gas costs** for trap operations
3. **Set appropriate thresholds** based on market conditions
4. **Implement additional safety checks** in the response contract

## 🛠️ Customization

### Adjusting Threshold

Modify the threshold percentage in the trap contract:

```solidity
uint256 public constant THRESHOLD_PERCENTAGE = 75; // 75% drop threshold
```

### Advanced Liquidity Calculation

Replace the simplified calculation with oracle-based pricing:

```solidity
function _calculateLiquidityValue(uint256 amount0, uint256 amount1) internal view returns (uint256) {
    // Implement Chainlink price feeds
    // Consider token decimals and relative values
    // Add slippage protection
}
```

### Multi-Pool Support

To monitor multiple pools:

1. Deploy separate trap instances for each pool
2. Or modify the contract to accept pool arrays

### Custom Response Logic

Modify `LiquidityWithdrawer.sol` to:

- Add partial withdrawal options
- Implement slippage protection
- Add custom notification systems
- Integrate with other DeFi protocols

## 📁 Project Structure

```
liquidity-protection-trap/
├── src/
│   ├── Trap.sol                    # Base Drosera contract
│   ├── LiquidityProtectionTrap.sol # Main monitoring contract
│   └── LiquidityWithdrawer.sol     # Response contract
├── test/
│   └── LiquidityProtectionTrap.t.sol # Test suite
├── script/
│   └── Deploy.s.sol                # Deployment script
├── drosera.toml                    # Drosera configuration
├── foundry.toml                    # Foundry configuration
├── package.json                    # Project metadata
└── README.md                       # This file
```

## 🤝 Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## 📞 Support

- [Drosera Documentation](https://dev.drosera.io/)
- [Foundry Book](https://book.getfoundry.sh/)
- [Drosera Discord](https://discord.gg/drosera)

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## ⚠️ Disclaimer

This software is provided as-is and may contain bugs. Use at your own risk. Always test thoroughly on testnets before mainnet deployment. The authors are not responsible for any financial losses.