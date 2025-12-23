# 🚀 Quick Start Guide

Get the Trader Joe LB Dashboard running in 5 minutes!

## Prerequisites

- Node.js 18+ installed
- MetaMask browser extension
- 5 minutes of your time ⏱️

## Step 1: Installation (1 minute)

```bash
# Install dependencies
npm install
```

## Step 2: Start Development Server (30 seconds)

```bash
# Start the dev server
npm run dev
```

The dashboard will automatically open at `http://localhost:3000`

## Step 3: Get Test Tokens (2 minutes)

### Option A: Use the Dashboard
1. Look for the orange "Get Test Tokens" button (floating on bottom-right)
2. Click it to open the Base Sepolia faucet
3. Connect your wallet and request test ETH

### Option B: Direct Links
- **Sepolia ETH**: https://www.alchemy.com/faucets/base-sepolia
- **Test USDC**: Click "Mint Test USDC" button in the dashboard
- **Test EURC**: Click "Mint Test EURC" button in the dashboard

## Step 4: Connect Wallet (30 seconds)

1. Click "Connect Wallet" in the top-right
2. Select MetaMask
3. Approve the connection
4. If prompted, switch to Base Sepolia network (chain ID: 84532)

## Step 5: Start Testing! (1 minute)

### Try Adding Liquidity:
1. Select a pool from the left sidebar (try "ETH/USDC - Bin Step 20")
2. Choose a distribution shape (try "CURVE")
3. Set your price range (use the "Medium (±5%)" preset)
4. Enter token amounts (click "MAX" for quick testing)
5. Click "Add Liquidity"

## 🎉 You're Done!

You now have a fully functional Trader Joe Liquidity Book dashboard running locally.

## Next Steps

### Explore Features
- ✅ View liquidity distribution chart
- ✅ Check your positions in the "Your Positions" tab
- ✅ Claim fees from active positions
- ✅ Remove liquidity
- ✅ View transaction history in "Analytics" tab

### Customize
- Edit `TraderJoeDashboard.tsx` to modify the UI
- Update token addresses in the constants section
- Change color scheme in `tailwind.config.js`

### Deploy
```bash
# Build for production
npm run build

# Preview production build
npm run preview
```

## Common Issues

### "Cannot connect wallet"
- Ensure MetaMask is installed and unlocked
- Check you're on Base Sepolia network (chain ID: 84532)
- Try refreshing the page

### "No test tokens"
- Visit the faucet: https://www.alchemy.com/faucets/base-sepolia
- Wait a few seconds for transaction confirmation
- Refresh the dashboard

### "Port 3000 already in use"
- Edit `vite.config.ts` and change the port number
- Or kill the process using port 3000

## Need Help?

- 📖 Read the full documentation: `DASHBOARD_README.md`
- 🐛 Found a bug? Open an issue on GitHub
- 💬 Questions? Check the FAQ in the main README

## Pro Tips 💡

1. **Open DevTools**: Press F12 to see console logs and debug
2. **Network Tab**: Monitor all blockchain interactions
3. **Small Amounts**: Always test with small amounts first
4. **Keep ETH**: Keep some Sepolia ETH for gas fees
5. **Bookmark Faucet**: Save time by bookmarking the faucet link

---

**Happy Testing! 🎊**

Ready to build something amazing with Trader Joe V2.1!
