<script setup lang="ts">
/**
 * Loading skeleton placeholder.
 *
 * Renders animated pulse bars to indicate content loading.
 *
 * Usage:
 *   <Skeleton />                    — single bar, default height
 *   <Skeleton :count="3" />         — 3 bars
 *   <Skeleton height="h-20" />      — custom height
 *   <Skeleton width="w-3/4" />      — custom width
 */

withDefaults(defineProps<{
  count?: number
  height?: string
  width?: string
}>(), {
  count: 1,
  height: 'h-14',
  width: 'w-full',
})
</script>

<template>
  <div class="space-y-3">
    <div
      v-for="i in count"
      :key="i"
      class="animate-pulse rounded-sacred-lg bg-sacred-bg-pulse"
      :class="[height, width]"
    />
  </div>
</template>
