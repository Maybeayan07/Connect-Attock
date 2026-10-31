import type { Config } from 'tailwindcss'

export default {
  content: ['./index.html', './src/**/*.{ts,tsx}'],
  theme: {
    extend: {
      colors: {
        navy: { 950: '#041427', 900: '#071c35', 800: '#0c2b4d', 700: '#123b65' },
        cyan: { 400: '#28d8e5', 500: '#10b8c7', 600: '#0795a5' },
        sand: '#f5f7f8',
        ink: '#102338',
        muted: '#617285',
      },
      fontFamily: { sans: ['Inter', 'sans-serif'], display: ['Space Grotesk', 'sans-serif'] },
      boxShadow: { soft: '0 18px 50px rgba(7, 28, 53, 0.08)', card: '0 10px 30px rgba(7, 28, 53, 0.06)' },
      borderRadius: { xl2: '1.25rem' },
      animation: { 'fade-up': 'fade-up 500ms ease-out both', 'route-dash': 'route-dash 18s linear infinite' },
      keyframes: {
        'fade-up': { '0%': { opacity: '0', transform: 'translateY(12px)' }, '100%': { opacity: '1', transform: 'translateY(0)' } },
        'route-dash': { to: { 'stroke-dashoffset': '-1000' } },
      },
    },
  },
  plugins: [],
} satisfies Config
