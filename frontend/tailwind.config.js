/** @type {import('tailwindcss').Config} */
export default {
  content: ['./index.html', './src/**/*.{vue,js,ts}'],
  theme: {
    extend: {
      colors: {
        sacred: {
          gold: '#c4873b',
          'gold-dark': '#8b5a1b',
          text: '#2b1e10',
          'text-secondary': '#6b5740',
          muted: '#9a8568',
          'muted-light': '#b5996f',
          label: '#a38d6d',
          bg: '#faf5ed',
          'bg-card': 'rgba(250,245,237,0.88)',
          'bg-card-hover': 'rgba(250,245,237,0.7)',
          border: 'rgba(139,90,43,0.12)',
          'border-light': 'rgba(139,90,43,0.08)',
          'border-subtle': 'rgba(139,90,43,0.1)',
          green: '#7aa87a',
          'green-dark': '#5a8a5a',
          red: '#b45a3c',
        },
      },
      fontFamily: {
        serif: ['Georgia', 'Cambria', '"Times New Roman"', 'Times', 'serif'],
      },
      boxShadow: {
        sacred: '0 4px 24px rgba(82,54,29,0.06)',
        'sacred-lg': '0 8px 40px rgba(82,54,29,0.08)',
        'sacred-button': '0 2px 8px rgba(139,90,27,0.2)',
        'sacred-glow': '0 4px 16px rgba(139,90,43,0.25)',
      },
    },
  },
  plugins: [],
}
