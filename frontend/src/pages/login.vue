<script setup lang="ts">
import { SignIn } from '@clerk/vue'
import SacredIcons from '@/components/icons/SacredIcons.vue'
</script>

<template>
  <div class="flex min-h-screen items-center justify-center bg-[radial-gradient(circle_at_top_left,rgba(196,135,59,0.18),transparent_35%),radial-gradient(circle_at_bottom_right,rgba(139,90,27,0.12),transparent_35%),linear-gradient(180deg,#faf5ed_0%,#f5ebe0_50%,#efe3d4_100%)] px-4">
    <div class="w-full max-w-md">
      <div class="mb-8 text-center">
        <RouterLink to="/" class="inline-flex flex-col items-center gap-3">
          <div class="flex h-14 w-14 items-center justify-center rounded-full bg-gradient-to-br from-[#c4873b] to-[#8b5a1b] text-white shadow-[0_4px_24px_rgba(139,90,27,0.25)]">
            <SacredIcons name="om" :size="28" />
          </div>
          <h1 class="font-serif text-3xl font-bold tracking-wide text-[#2b1e10]">ShantiSangha</h1>
        </RouterLink>
        <p class="mt-2 text-sm text-[#8a7356]">Welcome back. A calmer place to return to.</p>
      </div>
      <div class="rounded-2xl border border-[rgba(139,90,43,0.14)] bg-[rgba(250,245,237,0.88)] p-6 shadow-[0_24px_80px_rgba(82,54,29,0.1)] backdrop-blur-[20px]">
        <SignIn />
      </div>
      <p class="mt-6 text-center text-[10px] italic text-[#b5996f]">
        "Peace comes from within. Do not seek it without." — Buddha
      </p>
    </div>
  </div>
</template>
