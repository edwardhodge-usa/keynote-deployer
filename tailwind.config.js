/** @type {import('tailwindcss').Config} */
export default {
  content: [
    "./index.html",
    "./src/**/*.{js,ts,jsx,tsx}",
  ],
  darkMode: 'media',
  theme: {
    extend: {
      colors: {
        primary: {
          DEFAULT: '#0a84ff',
          hover: '#0077ed',
          active: '#006edb',
        },
        sidebar: {
          light: '#f5f5f7',
          dark: '#1c1c1e',
        },
        content: {
          light: '#ffffff',
          dark: '#2c2c2e',
        },
        border: {
          light: '#d1d1d6',
          dark: '#38383a',
        },
      },
      fontFamily: {
        sans: ['-apple-system', 'BlinkMacSystemFont', 'SF Pro Display', 'Segoe UI', 'Roboto', 'sans-serif'],
        mono: ['SF Mono', 'Monaco', 'Consolas', 'monospace'],
      },
      fontSize: {
        'xxs': ['0.625rem', { lineHeight: '0.75rem' }],
      },
      borderRadius: {
        'macos': '10px',
      },
      boxShadow: {
        'macos': '0 2px 10px rgba(0, 0, 0, 0.1)',
        'macos-dark': '0 2px 10px rgba(0, 0, 0, 0.3)',
      },
    },
  },
  plugins: [],
}
