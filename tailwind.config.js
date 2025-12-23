/** @type {import('tailwindcss').Config} */
export default {
  content: [
    "./index.html",
    "./src/**/*.{js,ts,jsx,tsx}",
    "./*.{js,ts,jsx,tsx}",
  ],
  theme: {
    extend: {
      colors: {
        base: {
          blue: '#0052FF',
          testnet: '#F5841F',
        },
        background: '#0a0b0d',
        foreground: '#ffffff',
        card: {
          DEFAULT: '#12131a',
          bg: '#12131a',
          border: '#1f2937',
        },
        border: '#1f2937',
        primary: {
          DEFAULT: '#0052FF',
          foreground: '#ffffff',
        },
        secondary: {
          DEFAULT: '#9ca3af',
          foreground: '#ffffff',
        },
        success: {
          DEFAULT: '#22c55e',
          foreground: '#ffffff',
        },
        warning: {
          DEFAULT: '#f59e0b',
          foreground: '#ffffff',
        },
        error: {
          DEFAULT: '#ef4444',
          foreground: '#ffffff',
        },
        testnet: {
          DEFAULT: '#F5841F',
          foreground: '#ffffff',
        },
      },
      animation: {
        'pulse-slow': 'pulse 3s cubic-bezier(0.4, 0, 0.6, 1) infinite',
      },
      backdropBlur: {
        xs: '2px',
      },
    },
  },
  plugins: [],
}
