<script setup lang="ts">
defineProps<{ name: string; size?: number }>()
</script>

<template>
  <!-- Om / Dashboard -->
  <svg v-if="name === 'om'" :width="size || 22" :height="size || 22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round">
    <path d="M12 2c-1.5 2-3 4.5-3 7 0 2.5 1.5 4 3 4s3-1.5 3-4c0-2.5-1.5-5-3-7Z" />
    <path d="M7 13c-2 1-3.5 3-3.5 5.5C3.5 21 5.5 22 7 22c2 0 3.5-1.5 4-3" />
    <path d="M17 13c2 1 3.5 3 3.5 5.5 0 2.5-2 3.5-3.5 3.5-2 0-3.5-1.5-4-3" />
    <circle cx="17" cy="5" r="1.5" />
    <path d="M15 7c1 0 2.5.5 3 2" />
  </svg>

  <!-- Lotus / Coping -->
  <svg v-else-if="name === 'lotus'" :width="size || 22" :height="size || 22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round">
    <path d="M12 22c0-4-2-7-5-9 3-1 5 0 5 0s2-1 5 0c-3 2-5 5-5 9Z" />
    <path d="M12 13c-1-4-4-7-8-8 2 4 4 6 8 8Z" />
    <path d="M12 13c1-4 4-7 8-8-2 4-4 6-8 8Z" />
    <path d="M12 13c-3-3-7-4-10-3 3 3 6 4 10 3Z" />
    <path d="M12 13c3-3 7-4 10-3-3 3-6 4-10 3Z" />
    <path d="M12 13V3" />
  </svg>

  <!-- Scroll / Journal -->
  <svg v-else-if="name === 'scroll'" :width="size || 22" :height="size || 22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round">
    <path d="M17 3H7a2 2 0 0 0-2 2v14c0 1.1.9 2 2 2h1.5a1.5 1.5 0 0 0 0-3H7V5h10v13h-1.5a1.5 1.5 0 0 0 0 3H17a2 2 0 0 0 2-2V5a2 2 0 0 0-2-2Z" />
    <path d="M9 8h6M9 12h4" />
  </svg>

  <!-- Dialogue / Chat -->
  <svg v-else-if="name === 'dialogue'" :width="size || 22" :height="size || 22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round">
    <path d="M12 21c-1.5 0-6-1-8-3 0 0 1-2 3-3-2-1.5-3-3.5-3-6 0-4 3.5-7 8-7s8 3 8 7-3.5 7-8 7c-.5 0-1 0-1.5-.1L7 18l2.5-1" />
    <circle cx="9" cy="12" r=".75" fill="currentColor" />
    <circle cx="12" cy="12" r=".75" fill="currentColor" />
    <circle cx="15" cy="12" r=".75" fill="currentColor" />
  </svg>

  <!-- Chakra / Mood -->
  <svg v-else-if="name === 'chakra'" :width="size || 22" :height="size || 22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round">
    <circle cx="12" cy="12" r="9" />
    <circle cx="12" cy="12" r="4" />
    <circle cx="12" cy="12" r="1" fill="currentColor" />
    <path d="M12 3v5M12 16v5M3 12h5M16 12h5M5.6 5.6l3.5 3.5M14.9 14.9l3.5 3.5M5.6 18.4l3.5-3.5M14.9 9.1l3.5-3.5" />
  </svg>

  <!-- Diya / Insights -->
  <svg v-else-if="name === 'diya'" :width="size || 22" :height="size || 22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round">
    <path d="M12 6c-1-2-1-4 0-4s1 2 0 4Z" />
    <ellipse cx="12" cy="8" rx="2" ry="1.5" />
    <path d="M7 14c0-3 2-5 5-5s5 2 5 5" />
    <path d="M5 14h14" />
    <path d="M6 14l1 5h10l1-5" />
    <path d="M9 19h6v1H9z" />
  </svg>

  <!-- Shankha / Voice -->
  <svg v-else-if="name === 'shankha'" :width="size || 22" :height="size || 22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round">
    <path d="M12 3c3 0 6 2 6 6 0 3-1.5 5-4 6v3c0 1.5-1 3-2 3s-2-1.5-2-3v-3c-2.5-1-4-3-4-6 0-4 3-6 6-6Z" />
    <path d="M10 9c0-1 .9-2 2-2s2 1 2 2" />
    <path d="M9 12.5c1.5 1 4.5 1 6 0" />
    <path d="M7 7c-1 1-1.5 2.5-1 4" />
    <path d="M17 7c1 1 1.5 2.5 1 4" />
  </svg>
</template>
