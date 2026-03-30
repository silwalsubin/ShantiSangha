/**
 * Tailwind configuration — single source of truth for all design tokens.
 *
 * RULE: No raw hex colors (#c4873b), rgba values, or arbitrary font sizes
 * should appear in .vue files. Use the sacred-* tokens defined here.
 *
 * Colors:    class="text-sacred-gold bg-sacred-bg border-sacred-border"
 * Shadows:   class="shadow-sacred"
 * Font size: class="text-sacred-xs text-sacred-heading"
 */

/** @type {import('tailwindcss').Config} */
export default {
  content: ['./index.html', './src/**/*.{vue,js,ts}'],
  theme: {
    extend: {
      colors: {
        sacred: {
          // Primary palette
          gold: '#c4873b',
          'gold-dark': '#8b5a1b',
          'gold-light': 'rgba(196,135,59,0.06)',

          // Text
          text: '#2b1e10',
          'text-secondary': '#6b5740',
          muted: '#9a8568',
          'muted-light': '#b5996f',
          label: '#a38d6d',

          // Backgrounds
          bg: '#faf5ed',
          'bg-warm': 'rgba(250,245,237,0.95)',
          'bg-card': 'rgba(250,245,237,0.88)',
          'bg-card-inner': 'rgba(250,245,237,0.7)',
          'bg-card-deep': 'rgba(250,245,237,0.6)',
          'bg-hover': 'rgba(139,90,43,0.06)',
          'bg-hover-strong': 'rgba(139,90,43,0.08)',
          'bg-pulse': 'rgba(139,90,43,0.06)',

          // Borders
          border: 'rgba(139,90,43,0.12)',
          'border-light': 'rgba(139,90,43,0.08)',
          'border-subtle': 'rgba(139,90,43,0.1)',
          'border-strong': 'rgba(139,90,43,0.15)',
          'border-focus': 'rgba(139,90,43,0.2)',

          // Status
          green: '#7aa87a',
          'green-dark': '#5a8a5a',
          'green-bg': 'rgba(122,168,122,0.06)',
          'green-border': 'rgba(122,168,122,0.25)',
          red: '#b45a3c',
          'red-bg': 'rgba(180,90,60,0.06)',
          'red-border': 'rgba(180,90,60,0.25)',

          // Error states (system red/green for validation)
          'error': 'rgba(220,50,50,0.06)',
          'error-border': 'rgba(220,50,50,0.12)',
          'error-strong': 'rgba(220,50,50,0.08)',
          'success-bg': 'rgba(90,160,90,0.12)',

          // Gradient helpers
          'gold-15': 'rgba(196,135,59,0.15)',
          'gold-05': 'rgba(196,135,59,0.05)',
          'gold-30': 'rgba(196,135,59,0.3)',
          'gold-14': 'rgba(196,135,59,0.14)',

          // Misc
          white: '#fff8f1',
        },
      },
      fontFamily: {
        serif: ['Georgia', 'Cambria', '"Times New Roman"', 'Times', 'serif'],
      },
      fontSize: {
        'sacred-xs': ['9px', { letterSpacing: '0.2em', fontWeight: '700', textTransform: 'uppercase' }],
        'sacred-label': ['10px', { letterSpacing: '0.2em', fontWeight: '600', textTransform: 'uppercase' }],
        'sacred-caption': ['10px', { letterSpacing: '0.15em', fontWeight: '500', textTransform: 'uppercase' }],
        'sacred-body': ['14px', { lineHeight: '1.6' }],
        'sacred-heading': ['24px', { lineHeight: '1.3', fontWeight: '600' }],
        'sacred-heading-sm': ['20px', { lineHeight: '1.3', fontWeight: '600' }],
      },
      boxShadow: {
        sacred: '0 4px 24px rgba(82,54,29,0.06)',
        'sacred-lg': '0 8px 40px rgba(82,54,29,0.08)',
        'sacred-button': '0 2px 8px rgba(139,90,27,0.2)',
        'sacred-glow': '0 4px 16px rgba(139,90,43,0.25)',
        'sacred-dropdown': '0 4px 16px rgba(82,54,29,0.12)',
      },
      borderRadius: {
        'sacred': '1rem',
        'sacred-lg': '1.25rem',
      },
    },
  },
  plugins: [],
}
