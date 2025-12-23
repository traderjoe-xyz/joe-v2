import React, { useState, useEffect, useMemo } from 'react';
import {
  BarChart, Bar, LineChart, Line, AreaChart, Area, XAxis, YAxis, CartesianGrid,
  Tooltip, ResponsiveContainer, Cell, ReferenceLine, ComposedChart, Brush
} from 'recharts';
import {
  Wallet, Settings, ChevronDown, Copy, ExternalLink, Plus, Minus,
  TrendingUp, TrendingDown, Activity, Clock, Check, X, AlertCircle,
  Droplet, Layers, BarChart3, DollarSign, Zap, Target, Menu,
  RefreshCw, Download, Upload, Info, ChevronLeft, ChevronRight,
  Maximize2, Minimize2, Filter, Search, Bell, LogOut, Globe,
  ArrowUpRight, ArrowDownRight, Coins, PieChart, History, Sliders
} from 'lucide-react';

// ============================================================================
// TYPES & INTERFACES
// ============================================================================

interface Token {
  symbol: string;
  address: string;
  decimals: number;
  icon: string;
  balance: string;
  usdValue: string;
  isFaucetAvailable: boolean;
}

interface Pool {
  id: string;
  tokenX: string;
  tokenY: string;
  binStep: number;
  tvl: string;
  volume24h: string;
  hasPosition: boolean;
  currentPrice: string;
  activeBin: number;
  baseFee: number;
  variableFee: number;
}

interface BinData {
  binId: number;
  priceX: number;
  priceY: number;
  liquidityUSD: number;
  userLiquidity: number;
  totalLiquidity: number;
  compositionX: number;
  compositionY: number;
  utilization: number;
}

interface Position {
  id: string;
  pool: string;
  tokenX: string;
  tokenY: string;
  inRange: boolean;
  totalValue: string;
  amountX: string;
  amountY: string;
  valueX: string;
  valueY: string;
  minBin: number;
  maxBin: number;
  minPrice: string;
  maxPrice: string;
  unclaimedFees: string;
  unclaimedX: string;
  unclaimedY: string;
  unclaimedValueX: string;
  unclaimedValueY: string;
  apr24h: string;
  apr7d: string;
  daysInPosition: number;
  totalFeesEarned: string;
}

interface Transaction {
  id: string;
  type: 'add' | 'remove' | 'claim' | 'rebalance';
  description: string;
  timestamp: number;
  status: 'confirmed' | 'pending' | 'failed';
  hash: string;
}

type DistributionShape = 'UNIFORM' | 'CURVE' | 'BID-ASK' | 'SPOT' | 'CUSTOM';

// ============================================================================
// CONSTANTS & CONFIGURATION
// ============================================================================

const BASE_SEPOLIA_CONFIG = {
  chainId: 84532,
  name: 'Base Sepolia',
  rpc: 'https://sepolia.base.org',
  explorer: 'https://sepolia.basescan.org',
  faucet: 'https://www.alchemy.com/faucets/base-sepolia',
  primaryColor: '#0052FF',
  testnetColor: '#F5841F',
};

const TOKEN_ADDRESSES = {
  ETH: '0x0000000000000000000000000000000000000000',
  WETH: '0x4200000000000000000000000000000000000006',
  USDC: '0x036CbD53842c5426634e7929541eC2318f3dCF7e',
  EURC: '0x0000000000000000000000000000000000000001', // Mock
};

const WALLETCONNECT_PROJECT_ID = '9dfccfa8a2a30761cd55cfbef8a4b1a5';

const COLORS = {
  primary: '#0052FF',
  testnet: '#F5841F',
  background: '#0a0b0d',
  cardBg: '#12131a',
  cardBorder: '#1f2937',
  success: '#22c55e',
  warning: '#f59e0b',
  error: '#ef4444',
  textPrimary: '#ffffff',
  textSecondary: '#9ca3af',
};

// ============================================================================
// MOCK DATA GENERATORS
// ============================================================================

const generateMockBinData = (activeBin: number, count: number = 150): BinData[] => {
  const basePrice = 3250; // ETH price
  const data: BinData[] = [];

  for (let i = -count/2; i < count/2; i++) {
    const binId = activeBin + i;
    const priceMultiplier = 1 + (i * 0.002); // 0.2% per bin
    const priceX = basePrice * priceMultiplier;

    // Create liquidity curve - higher near active bin
    const distanceFromActive = Math.abs(i);
    const liquidityBase = 50000;
    const liquidityMultiplier = Math.exp(-distanceFromActive / 20);
    const totalLiquidity = liquidityBase * liquidityMultiplier * (0.5 + Math.random());

    // User has liquidity in bins close to active
    const hasUserLiquidity = distanceFromActive < 25;
    const userLiquidity = hasUserLiquidity ? totalLiquidity * 0.05 * Math.random() : 0;

    data.push({
      binId,
      priceX,
      priceY: 1 / priceX,
      liquidityUSD: totalLiquidity,
      userLiquidity,
      totalLiquidity,
      compositionX: 50 + (i > 0 ? 10 : -10) * Math.random(),
      compositionY: 50 + (i < 0 ? 10 : -10) * Math.random(),
      utilization: 20 + Math.random() * 60,
    });
  }

  return data;
};

const generatePositionBinData = (position: Position): BinData[] => {
  const data: BinData[] = [];
  const minBin = position.minBin;
  const maxBin = position.maxBin;
  const binCount = maxBin - minBin + 1;

  // Parse price range
  const minPrice = parseFloat(position.minPrice.replace('$', '').replace(',', ''));
  const maxPrice = parseFloat(position.maxPrice.replace('$', '').replace(',', ''));
  const priceStep = (maxPrice - minPrice) / binCount;

  // Parse total position value for distribution
  const totalValue = parseFloat(position.totalValue.replace('$', '').replace(',', ''));
  const avgLiquidityPerBin = totalValue / binCount;

  for (let i = 0; i <= binCount; i++) {
    const binId = minBin + i;
    const priceX = minPrice + (priceStep * i);

    // Create varied liquidity distribution (higher in middle bins)
    const distanceFromCenter = Math.abs(i - binCount / 2);
    const liquidityMultiplier = 1 - (distanceFromCenter / binCount) * 0.3;
    const userLiquidity = avgLiquidityPerBin * liquidityMultiplier * (0.8 + Math.random() * 0.4);

    data.push({
      binId,
      priceX,
      priceY: 1 / priceX,
      liquidityUSD: userLiquidity * 1.5, // Total pool liquidity (user has part of it)
      userLiquidity,
      totalLiquidity: userLiquidity * 1.5,
      compositionX: 50 + (i > binCount / 2 ? 10 : -10) * Math.random(),
      compositionY: 50 + (i < binCount / 2 ? 10 : -10) * Math.random(),
      utilization: 40 + Math.random() * 40,
    });
  }

  return data;
};

const generateMockPositions = (): Position[] => {
  return [
    {
      id: '1',
      pool: 'ETH/USDC',
      tokenX: 'ETH',
      tokenY: 'USDC',
      inRange: true,
      totalValue: '$2,456.78',
      amountX: '0.45',
      amountY: '994.28',
      valueX: '$1,462.50',
      valueY: '$994.28',
      minBin: 8388590,
      maxBin: 8388650,
      minPrice: '$3,100',
      maxPrice: '$3,400',
      unclaimedFees: '$12.34',
      unclaimedX: '0.002',
      unclaimedY: '5.84',
      unclaimedValueX: '$6.50',
      unclaimedValueY: '$5.84',
      apr24h: '15.2',
      apr7d: '18.7',
      daysInPosition: 5,
      totalFeesEarned: '$45.67',
    },
    {
      id: '2',
      pool: 'WETH/USDC',
      tokenX: 'WETH',
      tokenY: 'USDC',
      inRange: false,
      totalValue: '$1,234.56',
      amountX: '0.25',
      amountY: '422.15',
      valueX: '$812.50',
      valueY: '$422.06',
      minBin: 8388500,
      maxBin: 8388580,
      minPrice: '$2,850',
      maxPrice: '$3,100',
      unclaimedFees: '$3.21',
      unclaimedX: '0.001',
      unclaimedY: '0.12',
      unclaimedValueX: '$3.25',
      unclaimedValueY: '$0.12',
      apr24h: '0.0',
      apr7d: '8.3',
      daysInPosition: 12,
      totalFeesEarned: '$28.45',
    },
    {
      id: '3',
      pool: 'USDC/EURC',
      tokenX: 'USDC',
      tokenY: 'EURC',
      inRange: true,
      totalValue: '$5,678.90',
      amountX: '2,850',
      amountY: '2,615',
      valueX: '$2,850.00',
      valueY: '$2,828.90',
      minBin: 8388608,
      maxBin: 8388628,
      minPrice: '$1.08',
      maxPrice: '$1.10',
      unclaimedFees: '$8.76',
      unclaimedX: '4.32',
      unclaimedY: '4.12',
      unclaimedValueX: '$4.32',
      unclaimedValueY: '$4.44',
      apr24h: '5.8',
      apr7d: '6.2',
      daysInPosition: 18,
      totalFeesEarned: '$92.34',
    },
  ];
};

const generateMockTransactions = (): Transaction[] => {
  return [
    {
      id: '1',
      type: 'add',
      description: 'Added 0.5 ETH + 1,625 USDC to ETH/USDC',
      timestamp: Date.now() - 2 * 60 * 60 * 1000,
      status: 'confirmed',
      hash: '0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef',
    },
    {
      id: '2',
      type: 'claim',
      description: 'Claimed 0.003 ETH + 8.45 USDC fees',
      timestamp: Date.now() - 5 * 60 * 60 * 1000,
      status: 'confirmed',
      hash: '0xabcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890',
    },
    {
      id: '3',
      type: 'remove',
      description: 'Removed 0.2 ETH + 650 USDC from ETH/USDC',
      timestamp: Date.now() - 24 * 60 * 60 * 1000,
      status: 'confirmed',
      hash: '0x7890abcdef1234567890abcdef1234567890abcdef1234567890abcdef123456',
    },
    {
      id: '4',
      type: 'rebalance',
      description: 'Rebalanced ETH/USDC position',
      timestamp: Date.now() - 48 * 60 * 60 * 1000,
      status: 'confirmed',
      hash: '0x567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234',
    },
  ];
};

const generateMockPools = (): Pool[] => {
  return [
    {
      id: 'eth-usdc-20',
      tokenX: 'ETH',
      tokenY: 'USDC',
      binStep: 20,
      tvl: '$125,432',
      volume24h: '$45,678',
      hasPosition: true,
      currentPrice: '3247.82',
      activeBin: 8388621,
      baseFee: 0.05,
      variableFee: 0.02,
    },
    {
      id: 'eth-usdc-10',
      tokenX: 'ETH',
      tokenY: 'USDC',
      binStep: 10,
      tvl: '$89,234',
      volume24h: '$32,456',
      hasPosition: false,
      currentPrice: '3247.82',
      activeBin: 8388621,
      baseFee: 0.05,
      variableFee: 0.015,
    },
    {
      id: 'weth-usdc-15',
      tokenX: 'WETH',
      tokenY: 'USDC',
      binStep: 15,
      tvl: '$76,543',
      volume24h: '$28,901',
      hasPosition: true,
      currentPrice: '3247.82',
      activeBin: 8388621,
      baseFee: 0.05,
      variableFee: 0.018,
    },
    {
      id: 'eth-eurc-20',
      tokenX: 'ETH',
      tokenY: 'EURC',
      binStep: 20,
      tvl: '$54,321',
      volume24h: '$18,765',
      hasPosition: false,
      currentPrice: '3012.45',
      activeBin: 8388600,
      baseFee: 0.05,
      variableFee: 0.02,
    },
    {
      id: 'usdc-eurc-1',
      tokenX: 'USDC',
      tokenY: 'EURC',
      binStep: 1,
      tvl: '$234,567',
      volume24h: '$89,012',
      hasPosition: true,
      currentPrice: '1.09',
      activeBin: 8388618,
      baseFee: 0.01,
      variableFee: 0.005,
    },
  ];
};

// ============================================================================
// UTILITY COMPONENTS
// ============================================================================

const TestnetBanner: React.FC = () => (
  <div className="bg-gradient-to-r from-orange-600 to-orange-500 text-white py-2 px-4 text-center text-sm font-medium">
    <div className="flex items-center justify-center gap-2">
      <AlertCircle size={16} />
      <span>TESTNET MODE - Base Sepolia</span>
      <span className="hidden sm:inline">•</span>
      <a
        href={BASE_SEPOLIA_CONFIG.faucet}
        target="_blank"
        rel="noopener noreferrer"
        className="hidden sm:inline underline hover:text-orange-100"
      >
        Get Test Tokens
      </a>
    </div>
  </div>
);

const NetworkBadge: React.FC = () => (
  <div className="flex items-center gap-2 px-3 py-1.5 bg-gray-800 rounded-lg border border-gray-700">
    <div className="w-2 h-2 rounded-full bg-orange-500 animate-pulse" />
    <span className="text-sm font-medium text-white">Base Sepolia</span>
  </div>
);

const CopyButton: React.FC<{ text: string }> = ({ text }) => {
  const [copied, setCopied] = useState(false);

  const handleCopy = () => {
    navigator.clipboard.writeText(text);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  };

  return (
    <button
      onClick={handleCopy}
      className="p-1.5 hover:bg-gray-700 rounded transition-colors"
      title="Copy to clipboard"
    >
      {copied ? <Check size={14} className="text-green-500" /> : <Copy size={14} className="text-gray-400" />}
    </button>
  );
};

const ExplorerLink: React.FC<{ address: string; type?: 'address' | 'tx' }> = ({ address, type = 'address' }) => (
  <a
    href={`${BASE_SEPOLIA_CONFIG.explorer}/${type}/${address}`}
    target="_blank"
    rel="noopener noreferrer"
    className="p-1.5 hover:bg-gray-700 rounded transition-colors"
    title="View on explorer"
  >
    <ExternalLink size={14} className="text-gray-400 hover:text-blue-400" />
  </a>
);

const LoadingSpinner: React.FC<{ size?: number }> = ({ size = 20 }) => (
  <div className="flex items-center justify-center">
    <RefreshCw size={size} className="animate-spin text-blue-500" />
  </div>
);

const SkeletonLoader: React.FC<{ className?: string }> = ({ className = '' }) => (
  <div className={`animate-pulse bg-gray-700 rounded ${className}`} />
);

// ============================================================================
// MAIN DASHBOARD COMPONENT
// ============================================================================

const TraderJoeDashboard: React.FC = () => {
  // ========== STATE ==========
  const [walletConnected, setWalletConnected] = useState(false);
  const [walletAddress, setWalletAddress] = useState('');
  const [selectedPool, setSelectedPool] = useState<Pool | null>(null);
  const [activeTab, setActiveTab] = useState<'liquidity' | 'positions' | 'analytics'>('liquidity');
  const [showSettings, setShowSettings] = useState(false);
  const [showRemoveModal, setShowRemoveModal] = useState(false);
  const [selectedPosition, setSelectedPosition] = useState<Position | null>(null);
  const [isLoading, setIsLoading] = useState(false);

  // Add Liquidity State
  const [distributionShape, setDistributionShape] = useState<DistributionShape>('CURVE');
  const [minPrice, setMinPrice] = useState('3100');
  const [maxPrice, setMaxPrice] = useState('3400');
  const [amountX, setAmountX] = useState('');
  const [amountY, setAmountY] = useState('');
  const [autoCalculate, setAutoCalculate] = useState(true);
  const [slippage, setSlippage] = useState('0.5');

  // Chart State
  const [chartZoom, setChartZoom] = useState(50); // bins to show
  const [chartOffset, setChartOffset] = useState(0);
  const [showOnlyUserLiquidity, setShowOnlyUserLiquidity] = useState(false);

  // Removal State
  const [removePercentage, setRemovePercentage] = useState(100);
  const [claimFeesOnRemove, setClaimFeesOnRemove] = useState(true);
  const [removalMode, setRemovalMode] = useState<'percentage' | 'bins'>('percentage');
  const [selectedBinsForRemoval, setSelectedBinsForRemoval] = useState<Set<number>>(new Set());
  const [binRangeStart, setBinRangeStart] = useState(0);
  const [binRangeEnd, setBinRangeEnd] = useState(0);

  // Mock Data
  const [tokens, setTokens] = useState<Token[]>([
    {
      symbol: 'ETH',
      address: TOKEN_ADDRESSES.ETH,
      decimals: 18,
      icon: '⟠',
      balance: '1.5000',
      usdValue: '$4,875.00',
      isFaucetAvailable: true,
    },
    {
      symbol: 'WETH',
      address: TOKEN_ADDRESSES.WETH,
      decimals: 18,
      icon: '⟠',
      balance: '0.2500',
      usdValue: '$812.50',
      isFaucetAvailable: false,
    },
    {
      symbol: 'USDC',
      address: TOKEN_ADDRESSES.USDC,
      decimals: 6,
      icon: '●',
      balance: '5,000.00',
      usdValue: '$5,000.00',
      isFaucetAvailable: true,
    },
    {
      symbol: 'EURC',
      address: TOKEN_ADDRESSES.EURC,
      decimals: 6,
      icon: '€',
      balance: '2,615.00',
      usdValue: '$2,828.90',
      isFaucetAvailable: true,
    },
  ]);

  const pools = useMemo(() => generateMockPools(), []);
  const positions = useMemo(() => generateMockPositions(), []);
  const transactions = useMemo(() => generateMockTransactions(), []);

  // ========== EFFECTS ==========
  useEffect(() => {
    // Select first pool by default
    if (!selectedPool && pools.length > 0) {
      setSelectedPool(pools[0]);
    }
  }, [pools, selectedPool]);

  // ========== BIN DATA ==========
  const binData = useMemo(() => {
    if (!selectedPool) return [];
    return generateMockBinData(selectedPool.activeBin, 150);
  }, [selectedPool]);

  const visibleBinData = useMemo(() => {
    const startIndex = Math.max(0, Math.floor(binData.length / 2) - chartZoom / 2 + chartOffset);
    const endIndex = Math.min(binData.length, startIndex + chartZoom);
    return binData.slice(startIndex, endIndex);
  }, [binData, chartZoom, chartOffset]);

  const positionBinData = useMemo(() => {
    if (!selectedPosition) return [];
    return generatePositionBinData(selectedPosition);
  }, [selectedPosition]);

  // Initialize bin range when position changes
  useEffect(() => {
    if (positionBinData.length > 0) {
      setBinRangeStart(0);
      setBinRangeEnd(Math.max(0, positionBinData.length - 1));
    }
  }, [positionBinData]);

  // ========== HANDLERS ==========
  const handleConnectWallet = async () => {
    setIsLoading(true);
    // Simulate wallet connection
    setTimeout(() => {
      setWalletConnected(true);
      setWalletAddress('0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb');
      setIsLoading(false);
    }, 1000);
  };

  const handleDisconnectWallet = () => {
    setWalletConnected(false);
    setWalletAddress('');
  };

  const handleFaucet = async (tokenSymbol: string) => {
    console.log(`Opening faucet for ${tokenSymbol}`);
    if (tokenSymbol === 'ETH') {
      window.open(BASE_SEPOLIA_CONFIG.faucet, '_blank');
    } else {
      // Simulate minting
      alert(`Minting test ${tokenSymbol}...`);
    }
  };

  const handleAddLiquidity = async () => {
    if (!amountX && !amountY) return;

    setIsLoading(true);
    // Simulate transaction
    setTimeout(() => {
      alert('Liquidity added successfully!');
      setIsLoading(false);
      setAmountX('');
      setAmountY('');
    }, 2000);
  };

  const handleRemoveLiquidity = async () => {
    if (!selectedPosition) return;

    setIsLoading(true);
    setTimeout(() => {
      alert(`Removed ${removePercentage}% of liquidity from ${selectedPosition.pool}`);
      setIsLoading(false);
      setShowRemoveModal(false);
      setSelectedPosition(null);
    }, 2000);
  };

  const handleClaimFees = async (positionId: string) => {
    setIsLoading(true);
    setTimeout(() => {
      alert(`Claimed fees for position ${positionId}`);
      setIsLoading(false);
    }, 1500);
  };

  const centerOnActiveBin = () => {
    setChartOffset(0);
  };

  const centerOnMyPosition = () => {
    // Find first user position bin
    const userBinIndex = binData.findIndex(b => b.userLiquidity > 0);
    if (userBinIndex !== -1) {
      const offset = userBinIndex - Math.floor(binData.length / 2);
      setChartOffset(offset);
    }
  };

  const toggleBinSelection = (binId: number) => {
    const newSelected = new Set(selectedBinsForRemoval);
    if (newSelected.has(binId)) {
      newSelected.delete(binId);
    } else {
      newSelected.add(binId);
    }
    setSelectedBinsForRemoval(newSelected);
  };

  const selectAllBins = () => {
    const allBinIds = new Set(positionBinData.map(b => b.binId));
    setSelectedBinsForRemoval(allBinIds);
  };

  const deselectAllBins = () => {
    setSelectedBinsForRemoval(new Set());
  };

  const calculateSelectedBinsValue = () => {
    if (selectedBinsForRemoval.size === 0 || positionBinData.length === 0) return 0;
    const selectedBins = positionBinData.filter(b => selectedBinsForRemoval.has(b.binId));
    const totalSelectedLiquidity = selectedBins.reduce((sum, b) => sum + b.userLiquidity, 0);
    return totalSelectedLiquidity;
  };

  const selectBinRange = (startIndex: number, endIndex: number) => {
    if (!positionBinData.length) return;
    const start = Math.min(startIndex, endIndex);
    const end = Math.max(startIndex, endIndex);
    const rangeBins = positionBinData.slice(start, end + 1).map(b => b.binId);
    setSelectedBinsForRemoval(new Set(rangeBins));
  };

  const handleBinRangeChange = (start: number, end: number) => {
    setBinRangeStart(start);
    setBinRangeEnd(end);
    selectBinRange(start, end);
  };

  const selectOutOfRangeBins = () => {
    if (!selectedPosition || !selectedPool) return;
    const activeBin = selectedPool.activeBin;
    const outOfRangeBins = positionBinData
      .filter(b => b.binId < activeBin || b.binId > activeBin)
      .map(b => b.binId);
    setSelectedBinsForRemoval(new Set(outOfRangeBins));
  };

  const selectInRangeBins = () => {
    if (!selectedPosition || !selectedPool) return;
    const activeBin = selectedPool.activeBin;
    const inRangeBins = positionBinData
      .filter(b => b.binId === activeBin)
      .map(b => b.binId);
    setSelectedBinsForRemoval(new Set(inRangeBins));
  };

  const selectLowLiquidityBins = () => {
    if (!positionBinData.length) return;
    const avgLiquidity = positionBinData.reduce((sum, b) => sum + b.userLiquidity, 0) / positionBinData.length;
    const lowLiqBins = positionBinData
      .filter(b => b.userLiquidity < avgLiquidity * 0.7)
      .map(b => b.binId);
    setSelectedBinsForRemoval(new Set(lowLiqBins));
  };

  const selectHighLiquidityBins = () => {
    if (!positionBinData.length) return;
    const avgLiquidity = positionBinData.reduce((sum, b) => sum + b.userLiquidity, 0) / positionBinData.length;
    const highLiqBins = positionBinData
      .filter(b => b.userLiquidity > avgLiquidity * 1.3)
      .map(b => b.binId);
    setSelectedBinsForRemoval(new Set(highLiqBins));
  };

  // ========== RENDER ==========
  return (
    <div className="min-h-screen bg-gray-950 text-white">
      {/* Testnet Banner */}
      <TestnetBanner />

      {/* Header */}
      <header className="border-b border-gray-800 bg-gray-900/50 backdrop-blur-sm sticky top-0 z-50">
        <div className="max-w-[1600px] mx-auto px-4 py-4">
          <div className="flex items-center justify-between">
            {/* Logo */}
            <div className="flex items-center gap-3">
              <div className="flex items-center gap-2">
                <Droplet className="text-blue-500" size={28} />
                <h1 className="text-xl font-bold bg-gradient-to-r from-blue-500 to-blue-400 bg-clip-text text-transparent">
                  LB Dashboard
                </h1>
              </div>
            </div>

            {/* Right Section */}
            <div className="flex items-center gap-3">
              <NetworkBadge />

              {walletConnected ? (
                <div className="flex items-center gap-2 px-4 py-2 bg-gray-800 rounded-lg border border-gray-700">
                  <Wallet size={16} className="text-blue-400" />
                  <span className="font-mono text-sm">
                    {walletAddress.slice(0, 6)}...{walletAddress.slice(-4)}
                  </span>
                  <CopyButton text={walletAddress} />
                  <ExplorerLink address={walletAddress} />
                  <button
                    onClick={handleDisconnectWallet}
                    className="ml-2 p-1 hover:bg-gray-700 rounded transition-colors"
                  >
                    <LogOut size={14} className="text-gray-400" />
                  </button>
                </div>
              ) : (
                <button
                  onClick={handleConnectWallet}
                  disabled={isLoading}
                  className="px-4 py-2 bg-blue-600 hover:bg-blue-700 rounded-lg font-medium transition-colors disabled:opacity-50 disabled:cursor-not-allowed flex items-center gap-2"
                >
                  {isLoading ? <LoadingSpinner size={16} /> : <Wallet size={16} />}
                  Connect Wallet
                </button>
              )}

              <button
                onClick={() => setShowSettings(true)}
                className="p-2 hover:bg-gray-800 rounded-lg transition-colors"
              >
                <Settings size={20} className="text-gray-400" />
              </button>
            </div>
          </div>
        </div>
      </header>

      {/* Main Content */}
      <main className="max-w-[1600px] mx-auto px-4 py-6">
        {!walletConnected ? (
          // Not Connected State
          <div className="flex flex-col items-center justify-center py-20">
            <div className="w-20 h-20 bg-gradient-to-br from-blue-600 to-blue-500 rounded-2xl flex items-center justify-center mb-6">
              <Wallet size={40} className="text-white" />
            </div>
            <h2 className="text-2xl font-bold mb-2">Connect Your Wallet</h2>
            <p className="text-gray-400 mb-6 text-center max-w-md">
              Connect your wallet to view and manage your Trader Joe liquidity positions on Base Sepolia testnet
            </p>
            <button
              onClick={handleConnectWallet}
              disabled={isLoading}
              className="px-6 py-3 bg-blue-600 hover:bg-blue-700 rounded-lg font-medium transition-colors disabled:opacity-50 flex items-center gap-2"
            >
              {isLoading ? <LoadingSpinner size={20} /> : <Wallet size={20} />}
              Connect Wallet
            </button>
            <div className="mt-8 p-4 bg-orange-500/10 border border-orange-500/20 rounded-lg max-w-md">
              <div className="flex items-start gap-2">
                <AlertCircle size={20} className="text-orange-500 flex-shrink-0 mt-0.5" />
                <div>
                  <p className="text-sm font-medium text-orange-400 mb-1">Need Test Tokens?</p>
                  <a
                    href={BASE_SEPOLIA_CONFIG.faucet}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="text-sm text-orange-300 underline hover:text-orange-200"
                  >
                    Get Sepolia ETH from Alchemy Faucet →
                  </a>
                </div>
              </div>
            </div>
          </div>
        ) : (
          <div className="grid grid-cols-1 lg:grid-cols-12 gap-6">
            {/* Left Sidebar */}
            <div className="lg:col-span-3 space-y-6">
              {/* Token Balances */}
              <div className="bg-gray-900 border border-gray-800 rounded-xl p-4">
                <h3 className="text-lg font-semibold mb-4 flex items-center gap-2">
                  <Coins size={20} className="text-blue-400" />
                  Test Token Balances
                </h3>
                <div className="space-y-3">
                  {tokens.map((token) => (
                    <div
                      key={token.symbol}
                      className="p-3 bg-gray-800/50 rounded-lg border border-gray-700/50 hover:border-gray-600/50 transition-colors"
                    >
                      <div className="flex items-center justify-between mb-2">
                        <div className="flex items-center gap-2">
                          <div className="w-8 h-8 bg-gradient-to-br from-blue-600 to-blue-500 rounded-full flex items-center justify-center text-lg">
                            {token.icon}
                          </div>
                          <div>
                            <div className="font-medium text-sm">{token.symbol}</div>
                            <div className="text-xs text-gray-500">Test Token</div>
                          </div>
                        </div>
                        {token.isFaucetAvailable && (
                          <button
                            onClick={() => handleFaucet(token.symbol)}
                            className="px-2 py-1 bg-orange-600/20 hover:bg-orange-600/30 border border-orange-500/30 rounded text-xs font-medium text-orange-400 transition-colors"
                          >
                            Faucet
                          </button>
                        )}
                      </div>
                      <div className="flex items-baseline justify-between">
                        <span className="text-lg font-semibold">{token.balance}</span>
                        <span className="text-sm text-gray-400">{token.usdValue}</span>
                      </div>
                    </div>
                  ))}
                </div>
              </div>

              {/* Pool Selector */}
              <div className="bg-gray-900 border border-gray-800 rounded-xl p-4">
                <h3 className="text-lg font-semibold mb-4 flex items-center gap-2">
                  <Layers size={20} className="text-blue-400" />
                  Select Pool
                </h3>
                <div className="space-y-2">
                  {pools.map((pool) => (
                    <button
                      key={pool.id}
                      onClick={() => setSelectedPool(pool)}
                      className={`w-full p-3 rounded-lg border transition-all text-left ${
                        selectedPool?.id === pool.id
                          ? 'bg-blue-600/20 border-blue-500/50'
                          : 'bg-gray-800/50 border-gray-700/50 hover:border-gray-600/50'
                      }`}
                    >
                      <div className="flex items-center justify-between mb-2">
                        <div className="flex items-center gap-2">
                          <span className="font-medium">{pool.tokenX}/{pool.tokenY}</span>
                          {pool.hasPosition && (
                            <div className="w-2 h-2 bg-green-500 rounded-full" />
                          )}
                        </div>
                        <span className="text-xs px-2 py-0.5 bg-gray-700 rounded font-mono">
                          {pool.binStep} bps
                        </span>
                      </div>
                      <div className="grid grid-cols-2 gap-2 text-xs text-gray-400">
                        <div>
                          <div className="text-gray-500">TVL</div>
                          <div className="font-medium text-white">{pool.tvl}</div>
                        </div>
                        <div>
                          <div className="text-gray-500">24h Vol</div>
                          <div className="font-medium text-white">{pool.volume24h}</div>
                        </div>
                      </div>
                    </button>
                  ))}
                </div>
              </div>

              {/* Testnet Helper Tools */}
              <div className="bg-gray-900 border border-orange-500/30 rounded-xl p-4">
                <h3 className="text-lg font-semibold mb-4 flex items-center gap-2">
                  <Zap size={20} className="text-orange-500" />
                  Testnet Tools
                </h3>
                <div className="space-y-2">
                  <a
                    href={BASE_SEPOLIA_CONFIG.faucet}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="w-full px-3 py-2 bg-orange-600/20 hover:bg-orange-600/30 border border-orange-500/30 rounded-lg text-sm font-medium text-orange-400 transition-colors flex items-center justify-center gap-2"
                  >
                    <ExternalLink size={14} />
                    Get Sepolia ETH
                  </a>
                  <button
                    onClick={() => handleFaucet('USDC')}
                    className="w-full px-3 py-2 bg-orange-600/20 hover:bg-orange-600/30 border border-orange-500/30 rounded-lg text-sm font-medium text-orange-400 transition-colors"
                  >
                    Mint Test USDC
                  </button>
                  <button
                    onClick={() => handleFaucet('EURC')}
                    className="w-full px-3 py-2 bg-orange-600/20 hover:bg-orange-600/30 border border-orange-500/30 rounded-lg text-sm font-medium text-orange-400 transition-colors"
                  >
                    Mint Test EURC
                  </button>
                </div>

                <div className="mt-4 pt-4 border-t border-gray-800">
                  <div className="text-xs text-gray-500 mb-2">Contract Addresses</div>
                  <div className="space-y-1 text-xs">
                    {Object.entries(TOKEN_ADDRESSES).map(([symbol, address]) => (
                      <div key={symbol} className="flex items-center justify-between">
                        <span className="text-gray-400">{symbol}</span>
                        <div className="flex items-center gap-1">
                          <span className="font-mono text-gray-500">
                            {address.slice(0, 6)}...{address.slice(-4)}
                          </span>
                          <CopyButton text={address} />
                          <ExplorerLink address={address} />
                        </div>
                      </div>
                    ))}
                  </div>
                </div>
              </div>
            </div>

            {/* Main Content Area */}
            <div className="lg:col-span-9 space-y-6">
              {/* Pool Stats Bar */}
              {selectedPool && (
                <div className="bg-gradient-to-br from-gray-900 to-gray-900/50 border border-gray-800 rounded-xl p-6">
                  <div className="grid grid-cols-2 md:grid-cols-4 lg:grid-cols-8 gap-4">
                    <div>
                      <div className="text-xs text-gray-500 mb-1">Current Price</div>
                      <div className="font-semibold">${selectedPool.currentPrice}</div>
                    </div>
                    <div>
                      <div className="text-xs text-gray-500 mb-1">Active Bin</div>
                      <div className="font-semibold font-mono">#{selectedPool.activeBin}</div>
                    </div>
                    <div>
                      <div className="text-xs text-gray-500 mb-1">Bin Step</div>
                      <div className="font-semibold">{selectedPool.binStep} bps</div>
                    </div>
                    <div>
                      <div className="text-xs text-gray-500 mb-1">Base Fee</div>
                      <div className="font-semibold">{selectedPool.baseFee}%</div>
                    </div>
                    <div>
                      <div className="text-xs text-gray-500 mb-1">Variable Fee</div>
                      <div className="font-semibold">{selectedPool.variableFee}%</div>
                    </div>
                    <div>
                      <div className="text-xs text-gray-500 mb-1">24h Volume</div>
                      <div className="font-semibold">{selectedPool.volume24h}</div>
                    </div>
                    <div>
                      <div className="text-xs text-gray-500 mb-1">TVL</div>
                      <div className="font-semibold">{selectedPool.tvl}</div>
                    </div>
                    <div>
                      <div className="text-xs text-gray-500 mb-1">Your Liquidity</div>
                      <div className="font-semibold text-green-400">$2,345.67</div>
                    </div>
                  </div>
                </div>
              )}

              {/* Tabs */}
              <div className="flex gap-2 border-b border-gray-800">
                <button
                  onClick={() => setActiveTab('liquidity')}
                  className={`px-4 py-2 font-medium transition-colors border-b-2 ${
                    activeTab === 'liquidity'
                      ? 'border-blue-500 text-blue-400'
                      : 'border-transparent text-gray-400 hover:text-gray-300'
                  }`}
                >
                  Add Liquidity
                </button>
                <button
                  onClick={() => setActiveTab('positions')}
                  className={`px-4 py-2 font-medium transition-colors border-b-2 ${
                    activeTab === 'positions'
                      ? 'border-blue-500 text-blue-400'
                      : 'border-transparent text-gray-400 hover:text-gray-300'
                  }`}
                >
                  Your Positions ({positions.length})
                </button>
                <button
                  onClick={() => setActiveTab('analytics')}
                  className={`px-4 py-2 font-medium transition-colors border-b-2 ${
                    activeTab === 'analytics'
                      ? 'border-blue-500 text-blue-400'
                      : 'border-transparent text-gray-400 hover:text-gray-300'
                  }`}
                >
                  Analytics
                </button>
              </div>

              {/* Tab Content */}
              {activeTab === 'liquidity' && (
                <div className="space-y-6">
                  {/* Liquidity Distribution Chart */}
                  <div className="bg-gray-900 border border-gray-800 rounded-xl p-6">
                    <div className="flex items-center justify-between mb-6">
                      <h3 className="text-lg font-semibold flex items-center gap-2">
                        <BarChart3 size={20} className="text-blue-400" />
                        Liquidity Distribution
                      </h3>
                      <div className="flex items-center gap-2">
                        <button
                          onClick={() => setShowOnlyUserLiquidity(!showOnlyUserLiquidity)}
                          className={`px-3 py-1.5 rounded-lg text-sm font-medium transition-colors ${
                            showOnlyUserLiquidity
                              ? 'bg-blue-600 text-white'
                              : 'bg-gray-800 text-gray-400 hover:text-white'
                          }`}
                        >
                          My Liquidity Only
                        </button>
                        <button
                          onClick={centerOnActiveBin}
                          className="px-3 py-1.5 bg-gray-800 hover:bg-gray-700 rounded-lg text-sm font-medium transition-colors"
                        >
                          Center on Active
                        </button>
                        <button
                          onClick={centerOnMyPosition}
                          className="px-3 py-1.5 bg-gray-800 hover:bg-gray-700 rounded-lg text-sm font-medium transition-colors"
                        >
                          My Position
                        </button>
                      </div>
                    </div>

                    <div className="mb-4">
                      <ResponsiveContainer width="100%" height={300}>
                        <BarChart data={visibleBinData}>
                          <CartesianGrid strokeDasharray="3 3" stroke="#374151" />
                          <XAxis
                            dataKey="priceX"
                            stroke="#9ca3af"
                            tick={{ fontSize: 12 }}
                            tickFormatter={(value) => `$${value.toFixed(0)}`}
                          />
                          <YAxis
                            stroke="#9ca3af"
                            tick={{ fontSize: 12 }}
                            tickFormatter={(value) => `$${(value / 1000).toFixed(0)}k`}
                          />
                          <Tooltip
                            contentStyle={{
                              backgroundColor: '#1f2937',
                              border: '1px solid #374151',
                              borderRadius: '8px',
                              fontSize: '12px',
                            }}
                            formatter={(value: any, name: string) => {
                              if (name === 'liquidityUSD') return [`$${value.toLocaleString()}`, 'Total Liquidity'];
                              if (name === 'userLiquidity') return [`$${value.toLocaleString()}`, 'Your Liquidity'];
                              return [value, name];
                            }}
                            labelFormatter={(binPrice) => `Price: $${binPrice.toFixed(2)}`}
                          />
                          <ReferenceLine
                            x={selectedPool?.currentPrice ? parseFloat(selectedPool.currentPrice) : 0}
                            stroke="#0052FF"
                            strokeWidth={2}
                            label={{ value: 'Active', position: 'top', fill: '#0052FF', fontSize: 12 }}
                          />
                          <Bar
                            dataKey={showOnlyUserLiquidity ? 'userLiquidity' : 'liquidityUSD'}
                            fill="#0052FF"
                            radius={[4, 4, 0, 0]}
                          >
                            {visibleBinData.map((entry, index) => (
                              <Cell
                                key={`cell-${index}`}
                                fill={
                                  entry.binId === selectedPool?.activeBin
                                    ? '#0052FF'
                                    : entry.userLiquidity > 0
                                    ? '#22c55e'
                                    : '#1f2937'
                                }
                                opacity={entry.userLiquidity > 0 || !showOnlyUserLiquidity ? 1 : 0.3}
                              />
                            ))}
                          </Bar>
                        </BarChart>
                      </ResponsiveContainer>
                    </div>

                    <div className="flex items-center justify-between">
                      <div className="flex items-center gap-4">
                        <button
                          onClick={() => setChartOffset(chartOffset - 10)}
                          className="p-2 bg-gray-800 hover:bg-gray-700 rounded-lg transition-colors"
                        >
                          <ChevronLeft size={16} />
                        </button>
                        <button
                          onClick={() => setChartOffset(chartOffset + 10)}
                          className="p-2 bg-gray-800 hover:bg-gray-700 rounded-lg transition-colors"
                        >
                          <ChevronRight size={16} />
                        </button>
                      </div>

                      <div className="flex items-center gap-3">
                        <span className="text-sm text-gray-400">Zoom:</span>
                        <input
                          type="range"
                          min="10"
                          max="150"
                          value={chartZoom}
                          onChange={(e) => setChartZoom(parseInt(e.target.value))}
                          className="w-32"
                        />
                        <span className="text-sm font-medium w-16">{chartZoom} bins</span>
                      </div>
                    </div>
                  </div>

                  {/* Add Liquidity Form */}
                  <div className="bg-gray-900 border border-gray-800 rounded-xl p-6">
                    <h3 className="text-lg font-semibold mb-6 flex items-center gap-2">
                      <Plus size={20} className="text-blue-400" />
                      Add Liquidity
                    </h3>

                    {/* Distribution Shape Selector */}
                    <div className="mb-6">
                      <label className="block text-sm font-medium text-gray-400 mb-3">
                        Distribution Shape
                      </label>
                      <div className="grid grid-cols-5 gap-2">
                        {[
                          { type: 'UNIFORM' as DistributionShape, icon: '▬', label: 'Uniform' },
                          { type: 'CURVE' as DistributionShape, icon: '⌒', label: 'Curve' },
                          { type: 'BID-ASK' as DistributionShape, icon: '∪', label: 'Bid-Ask' },
                          { type: 'SPOT' as DistributionShape, icon: '|', label: 'Spot' },
                          { type: 'CUSTOM' as DistributionShape, icon: '✎', label: 'Custom' },
                        ].map((shape) => (
                          <button
                            key={shape.type}
                            onClick={() => setDistributionShape(shape.type)}
                            className={`p-3 rounded-lg border transition-all ${
                              distributionShape === shape.type
                                ? 'bg-blue-600/20 border-blue-500/50'
                                : 'bg-gray-800/50 border-gray-700/50 hover:border-gray-600/50'
                            }`}
                          >
                            <div className="text-2xl mb-1">{shape.icon}</div>
                            <div className="text-xs font-medium">{shape.label}</div>
                          </button>
                        ))}
                      </div>
                    </div>

                    {/* Price Range Selector */}
                    <div className="mb-6">
                      <label className="block text-sm font-medium text-gray-400 mb-3">
                        Price Range
                      </label>

                      <div className="grid grid-cols-2 gap-4 mb-4">
                        <div>
                          <label className="block text-xs text-gray-500 mb-2">Min Price</label>
                          <div className="flex items-center gap-2">
                            <button
                              onClick={() => setMinPrice((parseFloat(minPrice) - 10).toString())}
                              className="p-2 bg-gray-800 hover:bg-gray-700 rounded transition-colors"
                            >
                              <Minus size={14} />
                            </button>
                            <input
                              type="number"
                              value={minPrice}
                              onChange={(e) => setMinPrice(e.target.value)}
                              className="flex-1 px-3 py-2 bg-gray-800 border border-gray-700 rounded-lg focus:outline-none focus:border-blue-500"
                            />
                            <button
                              onClick={() => setMinPrice((parseFloat(minPrice) + 10).toString())}
                              className="p-2 bg-gray-800 hover:bg-gray-700 rounded transition-colors"
                            >
                              <Plus size={14} />
                            </button>
                          </div>
                        </div>
                        <div>
                          <label className="block text-xs text-gray-500 mb-2">Max Price</label>
                          <div className="flex items-center gap-2">
                            <button
                              onClick={() => setMaxPrice((parseFloat(maxPrice) - 10).toString())}
                              className="p-2 bg-gray-800 hover:bg-gray-700 rounded transition-colors"
                            >
                              <Minus size={14} />
                            </button>
                            <input
                              type="number"
                              value={maxPrice}
                              onChange={(e) => setMaxPrice(e.target.value)}
                              className="flex-1 px-3 py-2 bg-gray-800 border border-gray-700 rounded-lg focus:outline-none focus:border-blue-500"
                            />
                            <button
                              onClick={() => setMaxPrice((parseFloat(maxPrice) + 10).toString())}
                              className="p-2 bg-gray-800 hover:bg-gray-700 rounded transition-colors"
                            >
                              <Plus size={14} />
                            </button>
                          </div>
                        </div>
                      </div>

                      <div className="flex gap-2">
                        {[
                          { label: 'Tight (±1%)', min: 3217, max: 3279 },
                          { label: 'Medium (±5%)', min: 3088, max: 3410 },
                          { label: 'Wide (±15%)', min: 2761, max: 3736 },
                        ].map((preset) => (
                          <button
                            key={preset.label}
                            onClick={() => {
                              setMinPrice(preset.min.toString());
                              setMaxPrice(preset.max.toString());
                            }}
                            className="px-3 py-1.5 bg-gray-800 hover:bg-gray-700 rounded-lg text-xs font-medium transition-colors"
                          >
                            {preset.label}
                          </button>
                        ))}
                      </div>
                    </div>

                    {/* Token Amount Inputs */}
                    <div className="mb-6 space-y-4">
                      <div>
                        <label className="block text-sm font-medium text-gray-400 mb-2">
                          {selectedPool?.tokenX || 'ETH'} Amount
                        </label>
                        <div className="relative">
                          <input
                            type="number"
                            value={amountX}
                            onChange={(e) => setAmountX(e.target.value)}
                            placeholder="0.0"
                            className="w-full px-4 py-3 bg-gray-800 border border-gray-700 rounded-lg focus:outline-none focus:border-blue-500 pr-20"
                          />
                          <button
                            onClick={() => setAmountX('1.5')}
                            className="absolute right-2 top-1/2 -translate-y-1/2 px-3 py-1 bg-blue-600/20 hover:bg-blue-600/30 text-blue-400 rounded text-sm font-medium transition-colors"
                          >
                            MAX
                          </button>
                        </div>
                        <div className="flex items-center justify-between mt-2 text-xs text-gray-500">
                          <span>Balance: 1.5 ETH</span>
                          <span>≈ $4,875.00</span>
                        </div>
                      </div>

                      <div>
                        <label className="block text-sm font-medium text-gray-400 mb-2">
                          {selectedPool?.tokenY || 'USDC'} Amount
                        </label>
                        <div className="relative">
                          <input
                            type="number"
                            value={amountY}
                            onChange={(e) => setAmountY(e.target.value)}
                            placeholder="0.0"
                            className="w-full px-4 py-3 bg-gray-800 border border-gray-700 rounded-lg focus:outline-none focus:border-blue-500 pr-20"
                          />
                          <button
                            onClick={() => setAmountY('5000')}
                            className="absolute right-2 top-1/2 -translate-y-1/2 px-3 py-1 bg-blue-600/20 hover:bg-blue-600/30 text-blue-400 rounded text-sm font-medium transition-colors"
                          >
                            MAX
                          </button>
                        </div>
                        <div className="flex items-center justify-between mt-2 text-xs text-gray-500">
                          <span>Balance: 5,000 USDC</span>
                          <span>≈ $5,000.00</span>
                        </div>
                      </div>
                    </div>

                    {/* Liquidity Preview */}
                    {(amountX || amountY) && (
                      <div className="mb-6 p-4 bg-blue-600/10 border border-blue-500/20 rounded-lg">
                        <h4 className="text-sm font-medium mb-3">Liquidity Preview</h4>
                        <div className="grid grid-cols-2 gap-4 text-sm">
                          <div>
                            <div className="text-gray-400">Total Value</div>
                            <div className="font-semibold">$9,875.00</div>
                          </div>
                          <div>
                            <div className="text-gray-400">Bins</div>
                            <div className="font-semibold">47 bins</div>
                          </div>
                          <div>
                            <div className="text-gray-400">Price Range</div>
                            <div className="font-semibold">${minPrice} - ${maxPrice}</div>
                          </div>
                          <div>
                            <div className="text-gray-400">Est. APR</div>
                            <div className="font-semibold text-green-400">12.5% - 25.3%</div>
                          </div>
                        </div>
                      </div>
                    )}

                    {/* Add Liquidity Button */}
                    <button
                      onClick={handleAddLiquidity}
                      disabled={!amountX && !amountY || isLoading}
                      className="w-full py-4 bg-blue-600 hover:bg-blue-700 disabled:bg-gray-700 disabled:cursor-not-allowed rounded-lg font-semibold text-lg transition-colors flex items-center justify-center gap-2"
                    >
                      {isLoading ? (
                        <>
                          <LoadingSpinner />
                          Adding Liquidity...
                        </>
                      ) : (
                        <>
                          <Plus size={20} />
                          Add Liquidity
                        </>
                      )}
                    </button>
                  </div>
                </div>
              )}

              {activeTab === 'positions' && (
                <div className="space-y-4">
                  {positions.map((position) => (
                    <div
                      key={position.id}
                      className="bg-gray-900 border border-gray-800 rounded-xl p-6 hover:border-gray-700 transition-colors"
                    >
                      {/* Header */}
                      <div className="flex items-center justify-between mb-4">
                        <div className="flex items-center gap-3">
                          <h4 className="text-lg font-semibold">{position.pool}</h4>
                          <span
                            className={`px-2 py-1 rounded text-xs font-medium ${
                              position.inRange
                                ? 'bg-green-600/20 text-green-400 border border-green-500/30'
                                : 'bg-orange-600/20 text-orange-400 border border-orange-500/30'
                            }`}
                          >
                            {position.inRange ? 'In Range' : 'Out of Range'}
                          </span>
                        </div>
                      </div>

                      <div className="grid md:grid-cols-3 gap-6">
                        {/* Value Section */}
                        <div>
                          <div className="text-sm text-gray-400 mb-2">Total Value</div>
                          <div className="text-2xl font-bold mb-3">{position.totalValue}</div>
                          <div className="space-y-1 text-sm">
                            <div className="flex items-center justify-between">
                              <span className="text-gray-400">{position.amountX} {position.tokenX}</span>
                              <span className="font-medium">{position.valueX}</span>
                            </div>
                            <div className="flex items-center justify-between">
                              <span className="text-gray-400">{position.amountY} {position.tokenY}</span>
                              <span className="font-medium">{position.valueY}</span>
                            </div>
                          </div>
                        </div>

                        {/* Range Section */}
                        <div>
                          <div className="text-sm text-gray-400 mb-2">Price Range</div>
                          <div className="text-lg font-semibold mb-2">
                            {position.minPrice} - {position.maxPrice}
                          </div>
                          <div className="text-xs text-gray-500">
                            Bins #{position.minBin} to #{position.maxBin}
                          </div>
                        </div>

                        {/* Performance Section */}
                        <div>
                          <div className="text-sm text-gray-400 mb-2">Performance</div>
                          <div className="space-y-1 text-sm">
                            <div className="flex items-center justify-between">
                              <span className="text-gray-400">APR (24h)</span>
                              <span className="font-medium text-green-400">{position.apr24h}%</span>
                            </div>
                            <div className="flex items-center justify-between">
                              <span className="text-gray-400">APR (7d)</span>
                              <span className="font-medium text-green-400">{position.apr7d}%</span>
                            </div>
                            <div className="flex items-center justify-between">
                              <span className="text-gray-400">Total Fees</span>
                              <span className="font-medium">{position.totalFeesEarned}</span>
                            </div>
                          </div>
                        </div>
                      </div>

                      {/* Unclaimed Fees */}
                      {parseFloat(position.unclaimedFees.replace('$', '')) > 0 && (
                        <div className="mt-4 p-3 bg-green-600/10 border border-green-500/20 rounded-lg">
                          <div className="flex items-center justify-between">
                            <div>
                              <div className="text-sm font-medium text-green-400 mb-1">
                                Unclaimed Fees: {position.unclaimedFees}
                              </div>
                              <div className="text-xs text-gray-400">
                                {position.unclaimedX} {position.tokenX} + {position.unclaimedY} {position.tokenY}
                              </div>
                            </div>
                            <button
                              onClick={() => handleClaimFees(position.id)}
                              className="px-4 py-2 bg-green-600 hover:bg-green-700 rounded-lg text-sm font-medium transition-colors"
                            >
                              Claim
                            </button>
                          </div>
                        </div>
                      )}

                      {/* Action Buttons */}
                      <div className="flex gap-2 mt-4">
                        <button className="flex-1 px-4 py-2 bg-gray-800 hover:bg-gray-700 rounded-lg text-sm font-medium transition-colors">
                          Add More
                        </button>
                        <button
                          onClick={() => {
                            setSelectedPosition(position);
                            setShowRemoveModal(true);
                          }}
                          className="flex-1 px-4 py-2 bg-red-600/20 hover:bg-red-600/30 border border-red-500/30 text-red-400 rounded-lg text-sm font-medium transition-colors"
                        >
                          Remove
                        </button>
                        <button className="flex-1 px-4 py-2 bg-gray-800 hover:bg-gray-700 rounded-lg text-sm font-medium transition-colors">
                          Rebalance
                        </button>
                      </div>
                    </div>
                  ))}
                </div>
              )}

              {activeTab === 'analytics' && (
                <div className="space-y-6">
                  {/* Analytics Content */}
                  <div className="bg-gray-900 border border-gray-800 rounded-xl p-6">
                    <h3 className="text-lg font-semibold mb-6 flex items-center gap-2">
                      <PieChart size={20} className="text-blue-400" />
                      Portfolio Analytics
                    </h3>
                    <div className="text-center text-gray-400 py-12">
                      Analytics charts coming soon...
                    </div>
                  </div>

                  {/* Transaction History */}
                  <div className="bg-gray-900 border border-gray-800 rounded-xl p-6">
                    <h3 className="text-lg font-semibold mb-6 flex items-center gap-2">
                      <History size={20} className="text-blue-400" />
                      Recent Transactions
                    </h3>
                    <div className="space-y-3">
                      {transactions.map((tx) => (
                        <div
                          key={tx.id}
                          className="flex items-center justify-between p-3 bg-gray-800/50 rounded-lg border border-gray-700/50 hover:border-gray-600/50 transition-colors"
                        >
                          <div className="flex items-center gap-3">
                            <div
                              className={`w-8 h-8 rounded-full flex items-center justify-center ${
                                tx.type === 'add'
                                  ? 'bg-green-600/20 text-green-400'
                                  : tx.type === 'remove'
                                  ? 'bg-red-600/20 text-red-400'
                                  : tx.type === 'claim'
                                  ? 'bg-blue-600/20 text-blue-400'
                                  : 'bg-orange-600/20 text-orange-400'
                              }`}
                            >
                              {tx.type === 'add' ? (
                                <Plus size={16} />
                              ) : tx.type === 'remove' ? (
                                <Minus size={16} />
                              ) : tx.type === 'claim' ? (
                                <DollarSign size={16} />
                              ) : (
                                <RefreshCw size={16} />
                              )}
                            </div>
                            <div>
                              <div className="font-medium text-sm">{tx.description}</div>
                              <div className="text-xs text-gray-500">
                                {new Date(tx.timestamp).toLocaleString()}
                              </div>
                            </div>
                          </div>
                          <div className="flex items-center gap-2">
                            <span
                              className={`px-2 py-1 rounded text-xs font-medium ${
                                tx.status === 'confirmed'
                                  ? 'bg-green-600/20 text-green-400'
                                  : tx.status === 'pending'
                                  ? 'bg-orange-600/20 text-orange-400'
                                  : 'bg-red-600/20 text-red-400'
                              }`}
                            >
                              {tx.status === 'confirmed' ? (
                                <Check size={12} className="inline" />
                              ) : tx.status === 'pending' ? (
                                <Clock size={12} className="inline" />
                              ) : (
                                <X size={12} className="inline" />
                              )}
                              <span className="ml-1">{tx.status}</span>
                            </span>
                            <ExplorerLink address={tx.hash} type="tx" />
                          </div>
                        </div>
                      ))}
                    </div>
                  </div>
                </div>
              )}
            </div>
          </div>
        )}
      </main>

      {/* Remove Liquidity Modal */}
      {showRemoveModal && selectedPosition && (
        <div className="fixed inset-0 bg-black/50 backdrop-blur-sm flex items-center justify-center z-50 p-4">
          <div className="bg-gray-900 border border-gray-800 rounded-xl max-w-3xl w-full p-6 max-h-[90vh] overflow-y-auto">
            <div className="flex items-center justify-between mb-6">
              <h3 className="text-xl font-bold">Remove Liquidity</h3>
              <button
                onClick={() => {
                  setShowRemoveModal(false);
                  setRemovalMode('percentage');
                  setSelectedBinsForRemoval(new Set());
                }}
                className="p-2 hover:bg-gray-800 rounded-lg transition-colors"
              >
                <X size={20} />
              </button>
            </div>

            <div className="mb-6">
              <div className="text-sm text-gray-400 mb-2">Pool</div>
              <div className="text-lg font-semibold">{selectedPosition.pool}</div>
              <div className="text-sm text-gray-500">
                Your Liquidity: {selectedPosition.totalValue} • {positionBinData.length} bins
              </div>
            </div>

            {/* Mode Toggle */}
            <div className="mb-6">
              <div className="flex gap-2 p-1 bg-gray-800 rounded-lg">
                <button
                  onClick={() => setRemovalMode('percentage')}
                  className={`flex-1 px-4 py-2 rounded-md font-medium transition-colors ${
                    removalMode === 'percentage'
                      ? 'bg-blue-600 text-white'
                      : 'text-gray-400 hover:text-white'
                  }`}
                >
                  Percentage Mode
                </button>
                <button
                  onClick={() => setRemovalMode('bins')}
                  className={`flex-1 px-4 py-2 rounded-md font-medium transition-colors ${
                    removalMode === 'bins'
                      ? 'bg-blue-600 text-white'
                      : 'text-gray-400 hover:text-white'
                  }`}
                >
                  Select Bins
                </button>
              </div>
            </div>

            {removalMode === 'percentage' ? (
              /* Percentage Mode */
              <div className="mb-6">
                <div className="flex items-center justify-between mb-3">
                  <label className="text-sm font-medium text-gray-400">Amount to Remove</label>
                  <span className="text-2xl font-bold text-blue-400">{removePercentage}%</span>
                </div>
                <input
                  type="range"
                  min="0"
                  max="100"
                  value={removePercentage}
                  onChange={(e) => setRemovePercentage(parseInt(e.target.value))}
                  className="w-full"
                />
                <div className="flex gap-2 mt-3">
                  {[25, 50, 75, 100].map((pct) => (
                    <button
                      key={pct}
                      onClick={() => setRemovePercentage(pct)}
                      className={`flex-1 px-3 py-1.5 rounded-lg text-sm font-medium transition-colors ${
                        removePercentage === pct
                          ? 'bg-blue-600 text-white'
                          : 'bg-gray-800 text-gray-400 hover:text-white'
                      }`}
                    >
                      {pct}%
                    </button>
                  ))}
                </div>
              </div>
            ) : (
              /* Bin Selection Mode */
              <div className="mb-6">
                <div className="flex items-center justify-between mb-3">
                  <label className="text-sm font-medium text-gray-400">Select Bins to Remove</label>
                  <div className="flex gap-2">
                    <button
                      onClick={selectAllBins}
                      className="px-3 py-1 text-xs bg-gray-800 hover:bg-gray-700 rounded transition-colors"
                    >
                      Select All
                    </button>
                    <button
                      onClick={deselectAllBins}
                      className="px-3 py-1 text-xs bg-gray-800 hover:bg-gray-700 rounded transition-colors"
                    >
                      Clear
                    </button>
                  </div>
                </div>

                {/* Quick Selection Presets */}
                <div className="mb-4 p-3 bg-gray-800/30 rounded-lg">
                  <div className="text-xs text-gray-500 mb-2">Quick Select:</div>
                  <div className="flex flex-wrap gap-2">
                    <button
                      onClick={selectOutOfRangeBins}
                      className="px-3 py-1.5 text-xs bg-orange-600/20 hover:bg-orange-600/30 border border-orange-500/30 text-orange-400 rounded transition-colors"
                    >
                      Out of Range
                    </button>
                    <button
                      onClick={selectInRangeBins}
                      className="px-3 py-1.5 text-xs bg-green-600/20 hover:bg-green-600/30 border border-green-500/30 text-green-400 rounded transition-colors"
                    >
                      In Range
                    </button>
                    <button
                      onClick={selectLowLiquidityBins}
                      className="px-3 py-1.5 text-xs bg-blue-600/20 hover:bg-blue-600/30 border border-blue-500/30 text-blue-400 rounded transition-colors"
                    >
                      Low Liquidity
                    </button>
                    <button
                      onClick={selectHighLiquidityBins}
                      className="px-3 py-1.5 text-xs bg-purple-600/20 hover:bg-purple-600/30 border border-purple-500/30 text-purple-400 rounded transition-colors"
                    >
                      High Liquidity
                    </button>
                  </div>
                </div>

                {/* Range Slider for Bin Selection */}
                <div className="mb-4 p-4 bg-gray-800/30 rounded-lg">
                  <div className="text-xs text-gray-400 mb-3">
                    Or drag slider to select bin range:
                  </div>
                  <div className="mb-3">
                    <div className="flex items-center justify-between mb-2 text-xs">
                      <span className="text-gray-500">Start: Bin #{positionBinData[binRangeStart]?.binId || '—'}</span>
                      <span className="text-gray-500">End: Bin #{positionBinData[binRangeEnd]?.binId || '—'}</span>
                    </div>
                    <div className="space-y-2">
                      <input
                        type="range"
                        min="0"
                        max={Math.max(0, positionBinData.length - 1)}
                        value={binRangeStart}
                        onChange={(e) => {
                          const newStart = parseInt(e.target.value);
                          setBinRangeStart(newStart);
                          if (newStart <= binRangeEnd) {
                            handleBinRangeChange(newStart, binRangeEnd);
                          }
                        }}
                        className="w-full"
                      />
                      <input
                        type="range"
                        min="0"
                        max={Math.max(0, positionBinData.length - 1)}
                        value={binRangeEnd}
                        onChange={(e) => {
                          const newEnd = parseInt(e.target.value);
                          setBinRangeEnd(newEnd);
                          if (binRangeStart <= newEnd) {
                            handleBinRangeChange(binRangeStart, newEnd);
                          }
                        }}
                        className="w-full"
                      />
                    </div>
                    <button
                      onClick={() => handleBinRangeChange(binRangeStart, binRangeEnd)}
                      className="mt-2 w-full px-3 py-1.5 bg-blue-600/20 hover:bg-blue-600/30 border border-blue-500/30 text-blue-400 rounded text-xs transition-colors"
                    >
                      Select Range: {Math.abs(binRangeEnd - binRangeStart) + 1} bins
                    </button>
                  </div>
                </div>

                {/* Bin Chart */}
                <div className="mb-4 p-4 bg-gray-800/50 rounded-lg">
                  <div className="text-xs text-gray-400 mb-3">
                    💡 Click bars to toggle • Drag brush below to select range • Selected: {selectedBinsForRemoval.size} / {positionBinData.length} bins
                  </div>
                  <ResponsiveContainer width="100%" height={250}>
                    <BarChart data={positionBinData}>
                      <CartesianGrid strokeDasharray="3 3" stroke="#374151" />
                      <XAxis
                        dataKey="priceX"
                        stroke="#9ca3af"
                        tick={{ fontSize: 11 }}
                        tickFormatter={(value) => `$${value.toFixed(0)}`}
                      />
                      <YAxis
                        stroke="#9ca3af"
                        tick={{ fontSize: 11 }}
                        tickFormatter={(value) => `$${(value / 1000).toFixed(0)}k`}
                      />
                      <Tooltip
                        contentStyle={{
                          backgroundColor: '#1f2937',
                          border: '1px solid #374151',
                          borderRadius: '8px',
                          fontSize: '12px',
                        }}
                        formatter={(value: any) => [`$${value.toLocaleString()}`, 'Your Liquidity']}
                        labelFormatter={(binPrice) => `Price: $${binPrice.toFixed(2)}`}
                      />
                      <Bar
                        dataKey="userLiquidity"
                        radius={[4, 4, 0, 0]}
                        onClick={(data: any) => toggleBinSelection(data.binId)}
                        cursor="pointer"
                      >
                        {positionBinData.map((entry, index) => (
                          <Cell
                            key={`cell-${index}`}
                            fill={selectedBinsForRemoval.has(entry.binId) ? '#ef4444' : '#0052FF'}
                            opacity={selectedBinsForRemoval.has(entry.binId) ? 1 : 0.6}
                          />
                        ))}
                      </Bar>
                      <Brush
                        dataKey="binId"
                        height={30}
                        stroke="#0052FF"
                        fill="#1f2937"
                        onChange={(range: any) => {
                          if (range && range.startIndex !== undefined && range.endIndex !== undefined) {
                            selectBinRange(range.startIndex, range.endIndex);
                            setBinRangeStart(range.startIndex);
                            setBinRangeEnd(range.endIndex);
                          }
                        }}
                      />
                    </BarChart>
                  </ResponsiveContainer>
                  <div className="mt-2 text-xs text-gray-500 text-center">
                    Blue: Not selected • Red: Selected for removal
                  </div>
                </div>

                {/* Bin List (scrollable) */}
                <div className="max-h-48 overflow-y-auto space-y-2">
                  {positionBinData.map((bin) => (
                    <div
                      key={bin.binId}
                      onClick={() => toggleBinSelection(bin.binId)}
                      className={`p-3 rounded-lg border cursor-pointer transition-all ${
                        selectedBinsForRemoval.has(bin.binId)
                          ? 'bg-red-600/20 border-red-500/50'
                          : 'bg-gray-800/50 border-gray-700/50 hover:border-gray-600'
                      }`}
                    >
                      <div className="flex items-center justify-between">
                        <div className="flex items-center gap-3">
                          <input
                            type="checkbox"
                            checked={selectedBinsForRemoval.has(bin.binId)}
                            onChange={() => toggleBinSelection(bin.binId)}
                            className="w-4 h-4"
                            onClick={(e) => e.stopPropagation()}
                          />
                          <div>
                            <div className="text-sm font-medium">Bin #{bin.binId}</div>
                            <div className="text-xs text-gray-500">Price: ${bin.priceX.toFixed(2)}</div>
                          </div>
                        </div>
                        <div className="text-right">
                          <div className="text-sm font-semibold">${bin.userLiquidity.toFixed(2)}</div>
                          <div className="text-xs text-gray-500">Your liquidity</div>
                        </div>
                      </div>
                    </div>
                  ))}
                </div>
              </div>
            )}

            <div className="mb-6 p-4 bg-gray-800/50 rounded-lg">
              <div className="text-sm font-medium mb-3">You will receive:</div>
              <div className="space-y-2 text-sm">
                <div className="flex items-center justify-between">
                  <span className="text-gray-400">{selectedPosition.tokenX}</span>
                  <span className="font-medium">
                    {removalMode === 'percentage'
                      ? (parseFloat(selectedPosition.amountX) * removePercentage / 100).toFixed(4)
                      : (parseFloat(selectedPosition.amountX) * (calculateSelectedBinsValue() / parseFloat(selectedPosition.totalValue.replace('$', '').replace(',', '')))).toFixed(4)
                    } (
                    ${removalMode === 'percentage'
                      ? (parseFloat(selectedPosition.valueX.replace('$', '').replace(',', '')) * removePercentage / 100).toFixed(2)
                      : (parseFloat(selectedPosition.valueX.replace('$', '').replace(',', '')) * (calculateSelectedBinsValue() / parseFloat(selectedPosition.totalValue.replace('$', '').replace(',', '')))).toFixed(2)
                    })
                  </span>
                </div>
                <div className="flex items-center justify-between">
                  <span className="text-gray-400">{selectedPosition.tokenY}</span>
                  <span className="font-medium">
                    {removalMode === 'percentage'
                      ? (parseFloat(selectedPosition.amountY) * removePercentage / 100).toFixed(2)
                      : (parseFloat(selectedPosition.amountY) * (calculateSelectedBinsValue() / parseFloat(selectedPosition.totalValue.replace('$', '').replace(',', '')))).toFixed(2)
                    } (
                    ${removalMode === 'percentage'
                      ? (parseFloat(selectedPosition.valueY.replace('$', '').replace(',', '')) * removePercentage / 100).toFixed(2)
                      : (parseFloat(selectedPosition.valueY.replace('$', '').replace(',', '')) * (calculateSelectedBinsValue() / parseFloat(selectedPosition.totalValue.replace('$', '').replace(',', '')))).toFixed(2)
                    })
                  </span>
                </div>
                <div className="pt-2 border-t border-gray-700 flex items-center justify-between font-semibold">
                  <span>Total</span>
                  <span>
                    ${removalMode === 'percentage'
                      ? (parseFloat(selectedPosition.totalValue.replace('$', '').replace(',', '')) * removePercentage / 100).toFixed(2)
                      : calculateSelectedBinsValue().toFixed(2)
                    }
                  </span>
                </div>
              </div>
            </div>

            <div className="mb-6">
              <label className="flex items-center gap-2 cursor-pointer">
                <input
                  type="checkbox"
                  checked={claimFeesOnRemove}
                  onChange={(e) => setClaimFeesOnRemove(e.target.checked)}
                  className="w-4 h-4 rounded border-gray-700 bg-gray-800"
                />
                <span className="text-sm">
                  Also claim unclaimed fees ({selectedPosition.unclaimedFees})
                </span>
              </label>
            </div>

            <div className="flex gap-3">
              <button
                onClick={() => {
                  setShowRemoveModal(false);
                  setRemovalMode('percentage');
                  setSelectedBinsForRemoval(new Set());
                }}
                className="flex-1 px-4 py-3 bg-gray-800 hover:bg-gray-700 rounded-lg font-medium transition-colors"
              >
                Cancel
              </button>
              <button
                onClick={handleRemoveLiquidity}
                disabled={isLoading || (removalMode === 'bins' && selectedBinsForRemoval.size === 0)}
                className="flex-1 px-4 py-3 bg-red-600 hover:bg-red-700 disabled:bg-gray-700 disabled:cursor-not-allowed rounded-lg font-medium transition-colors flex items-center justify-center gap-2"
              >
                {isLoading ? (
                  <>
                    <LoadingSpinner size={16} />
                    Removing...
                  </>
                ) : (
                  <>
                    <Minus size={16} />
                    Remove {removalMode === 'bins' ? `${selectedBinsForRemoval.size} Bin${selectedBinsForRemoval.size !== 1 ? 's' : ''}` : `${removePercentage}%`}
                  </>
                )}
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Floating Action Button - Get Test Tokens */}
      <a
        href={BASE_SEPOLIA_CONFIG.faucet}
        target="_blank"
        rel="noopener noreferrer"
        className="fixed bottom-6 right-6 w-14 h-14 bg-gradient-to-r from-orange-600 to-orange-500 hover:from-orange-700 hover:to-orange-600 rounded-full flex items-center justify-center shadow-lg shadow-orange-500/20 transition-all hover:scale-110 z-40"
        title="Get Test Tokens"
      >
        <Droplet size={24} className="text-white" />
      </a>
    </div>
  );
};

export default TraderJoeDashboard;
