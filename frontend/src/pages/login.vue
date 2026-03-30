<script setup lang="ts">
import { SignIn } from '@clerk/vue'
import SacredIcons from '@/components/icons/SacredIcons.vue'
</script>

<template>
  <div class="flex min-h-[100dvh] flex-col items-center justify-start bg-[radial-gradient(circle_at_top_left,rgba(196,135,59,0.18),transparent_35%),radial-gradient(circle_at_bottom_right,rgba(139,90,27,0.12),transparent_35%),linear-gradient(180deg,#faf5ed_0%,#f5ebe0_50%,#efe3d4_100%)] px-3 pb-8 pt-12 sm:justify-center sm:px-4 sm:pt-0">
    <div class="w-full max-w-[360px] sm:max-w-md">
      <!-- Logo -->
      <div class="mb-5 sm:mb-8 text-center">
        <RouterLink to="/" class="inline-flex flex-col items-center gap-2">
          <div class="logo-glow flex h-12 w-12 sm:h-16 sm:w-16 items-center justify-center rounded-full bg-gradient-to-br from-[#c4873b] to-[#8b5a1b] text-white">
            <SacredIcons name="vajra" :size="26" />
          </div>
          <h1 class="font-serif text-xl sm:text-3xl font-bold tracking-wide text-[#2b1e10]">ShantiSangha</h1>
        </RouterLink>
        <p class="mt-1 text-[11px] sm:text-sm text-[#9a8568]">Welcome back. A calmer place to return to.</p>
      </div>

      <!-- Auth card -->
      <div class="clerk-card overflow-hidden rounded-2xl border border-[rgba(139,90,43,0.12)] bg-[rgba(250,245,237,0.88)] shadow-[0_16px_60px_rgba(82,54,29,0.1)] backdrop-blur-[20px]">
        <SignIn />
      </div>

      <!-- Quote -->
      <p class="mt-4 sm:mt-6 text-center text-[10px] italic leading-relaxed text-[#b5996f]">
        "Peace comes from within. Do not seek it without." — Buddha
      </p>
    </div>
  </div>
</template>

<style scoped>
.logo-glow {
  animation: sacred-glow 3s ease-in-out infinite;
}

@keyframes sacred-glow {
  0%, 100% {
    box-shadow: 0 0 12px rgba(196, 135, 59, 0.3), 0 0 30px rgba(196, 135, 59, 0.1);
  }
  50% {
    box-shadow: 0 0 24px rgba(196, 135, 59, 0.5), 0 0 60px rgba(196, 135, 59, 0.2);
  }
}

.clerk-card :deep(.cl-card) {
  box-shadow: none !important;
  border: none !important;
  background: transparent !important;
}

.clerk-card :deep(.cl-rootBox) {
  width: 100% !important;
}

.clerk-card :deep(.cl-cardBox) {
  box-shadow: none !important;
  width: 100% !important;
}
</style>
