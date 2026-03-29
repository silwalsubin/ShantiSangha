<script setup lang="ts">
defineProps<{ name: string; size?: number }>()
</script>

<template>
  <!-- Lotus / Logo & Coping — refined sacred lotus -->
  <svg v-if="name === 'lotus'" :width="size || 22" :height="size || 22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.2" stroke-linecap="round" stroke-linejoin="round">
    <!-- Central petal -->
    <path d="M12 3C10.5 7 10 10.5 10.5 13c.3 1.5 1 2 1.5 2s1.2-.5 1.5-2c.5-2.5 0-6-1.5-10Z" />
    <!-- Inner left petal -->
    <path d="M8 5.5c-1.8 3-2.5 6-1.5 8.5.5 1.2 1.5 2 3 2.2" />
    <!-- Inner right petal -->
    <path d="M16 5.5c1.8 3 2.5 6 1.5 8.5-.5 1.2-1.5 2-3 2.2" />
    <!-- Outer left petal -->
    <path d="M5 8.5C3.5 11.5 3.2 14 4.5 16c.8 1.2 2 1.8 3.5 2" />
    <!-- Outer right petal -->
    <path d="M19 8.5c1.5 3 1.8 5.5.5 7.5-.8 1.2-2 1.8-3.5 2" />
    <!-- Base curve -->
    <path d="M7.5 18.5C9 20 10.5 21 12 21s3-1 4.5-2.5" />
    <!-- Center dot -->
    <circle cx="12" cy="12" r="0.8" fill="currentColor" stroke="none" />
  </svg>

  <!-- Om / Dashboard — sacred home temple -->
  <svg v-else-if="name === 'om'" :width="size || 22" :height="size || 22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.2" stroke-linecap="round" stroke-linejoin="round">
    <!-- Temple roof -->
    <path d="M3 11l9-7 9 7" />
    <!-- Dome -->
    <path d="M8 6.5C9.5 4 12 3 12 3s2.5 1 4 3.5" />
    <!-- Walls -->
    <path d="M5 11v9a1 1 0 0 0 1 1h12a1 1 0 0 0 1-1v-9" />
    <!-- Door arch -->
    <path d="M9.5 21v-5.5a2.5 2.5 0 0 1 5 0V21" />
    <!-- Kalash on top -->
    <line x1="12" y1="4" x2="12" y2="2" />
    <circle cx="12" cy="1.5" r="0.6" fill="currentColor" stroke="none" />
  </svg>

  <!-- Sacred book / Journal -->
  <svg v-else-if="name === 'scroll'" :width="size || 22" :height="size || 22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.2" stroke-linecap="round" stroke-linejoin="round">
    <!-- Book shape -->
    <path d="M4 19.5v-15A2.5 2.5 0 0 1 6.5 2H19a1 1 0 0 1 1 1v18a1 1 0 0 1-1 1H6.5a2.5 2.5 0 0 1 0-5H20" />
    <!-- Decorative lines (scripture text) -->
    <path d="M8 7h8" />
    <path d="M8 10h6" />
    <path d="M8 13h4" />
    <!-- Om-like decorative mark -->
    <circle cx="16.5" cy="13" r="0.6" fill="currentColor" stroke="none" />
  </svg>

  <!-- Speech / Chat — elegant dialogue -->
  <svg v-else-if="name === 'dialogue'" :width="size || 22" :height="size || 22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.2" stroke-linecap="round" stroke-linejoin="round">
    <!-- Main bubble -->
    <path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z" />
    <!-- Decorative dots representing sacred dialogue -->
    <circle cx="9" cy="10" r="0.8" fill="currentColor" stroke="none" />
    <circle cx="12" cy="10" r="0.8" fill="currentColor" stroke="none" />
    <circle cx="15" cy="10" r="0.8" fill="currentColor" stroke="none" />
  </svg>

  <!-- Mandala / Mood — sacred geometry -->
  <svg v-else-if="name === 'chakra'" :width="size || 22" :height="size || 22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.2" stroke-linecap="round" stroke-linejoin="round">
    <!-- Outer ring -->
    <circle cx="12" cy="12" r="9.5" />
    <!-- Inner ring -->
    <circle cx="12" cy="12" r="5" />
    <!-- Center -->
    <circle cx="12" cy="12" r="1.5" />
    <!-- Cardinal spokes with petal tips -->
    <path d="M12 2.5v4" />
    <path d="M12 17.5v4" />
    <path d="M2.5 12h4" />
    <path d="M17.5 12h4" />
    <!-- Diagonal spokes -->
    <path d="M5.3 5.3l2.8 2.8" />
    <path d="M15.9 15.9l2.8 2.8" />
    <path d="M5.3 18.7l2.8-2.8" />
    <path d="M15.9 8.1l2.8-2.8" />
    <!-- Petal accents on inner ring -->
    <circle cx="12" cy="7" r="0.5" fill="currentColor" stroke="none" />
    <circle cx="12" cy="17" r="0.5" fill="currentColor" stroke="none" />
    <circle cx="7" cy="12" r="0.5" fill="currentColor" stroke="none" />
    <circle cx="17" cy="12" r="0.5" fill="currentColor" stroke="none" />
  </svg>

  <!-- Diya lamp / Insights — traditional oil lamp -->
  <svg v-else-if="name === 'diya'" :width="size || 22" :height="size || 22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.2" stroke-linecap="round" stroke-linejoin="round">
    <!-- Flame -->
    <path d="M12 3c-.8 1.5-1.5 3-1.5 4.5 0 1.5.7 2.5 1.5 2.5s1.5-1 1.5-2.5C13.5 6 12.8 4.5 12 3Z" fill="currentColor" opacity="0.15" />
    <path d="M12 3c-.8 1.5-1.5 3-1.5 4.5 0 1.5.7 2.5 1.5 2.5s1.5-1 1.5-2.5C13.5 6 12.8 4.5 12 3Z" />
    <!-- Lamp bowl -->
    <path d="M6.5 14c0-2.5 2.5-4 5.5-4s5.5 1.5 5.5 4" />
    <path d="M4 14h16" />
    <!-- Lamp base -->
    <path d="M5.5 14l1.5 5h10l1.5-5" />
    <!-- Pedestal -->
    <path d="M9 19v1.5c0 .3.2.5.5.5h5c.3 0 .5-.2.5-.5V19" />
    <!-- Wick -->
    <line x1="12" y1="10" x2="12" y2="11" />
  </svg>

  <!-- Conch shell / Voice — traditional shankha -->
  <svg v-else-if="name === 'shankha'" :width="size || 22" :height="size || 22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.2" stroke-linecap="round" stroke-linejoin="round">
    <!-- Shell body -->
    <path d="M12 2c4 0 7 3 7 7 0 3-1.5 5.5-4 7v2.5c0 1.8-1.2 3.5-3 3.5s-3-1.7-3-3.5V16c-2.5-1.5-4-4-4-7 0-4 3-7 7-7Z" />
    <!-- Spiral lines -->
    <path d="M10 8.5a2.5 2.5 0 0 1 4 0" />
    <path d="M9 11.5c1.5 1.2 4.5 1.2 6 0" />
    <path d="M10 14c1 .6 3 .6 4 0" />
    <!-- Sound waves -->
    <path d="M19.5 8c.8.8 1.2 2 1 3.2" opacity="0.5" />
    <path d="M21 6.5c1 1.2 1.5 3 1.2 4.8" opacity="0.3" />
  </svg>

  <!-- Dharma Wheel / alternate logo -->
  <svg v-else-if="name === 'dharma'" :width="size || 22" :height="size || 22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.2" stroke-linecap="round" stroke-linejoin="round">
    <!-- Outer rim -->
    <circle cx="12" cy="12" r="10" />
    <!-- Hub -->
    <circle cx="12" cy="12" r="3" />
    <!-- 8 spokes -->
    <path d="M12 2v7" />
    <path d="M12 15v7" />
    <path d="M2 12h7" />
    <path d="M15 12h7" />
    <path d="M4.93 4.93l4.95 4.95" />
    <path d="M14.12 14.12l4.95 4.95" />
    <path d="M4.93 19.07l4.95-4.95" />
    <path d="M14.12 9.88l4.95-4.95" />
    <!-- Hub center -->
    <circle cx="12" cy="12" r="0.8" fill="currentColor" stroke="none" />
  </svg>
</template>
