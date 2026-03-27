<script setup lang="ts">
definePageMeta({ layout: false })
</script>

<template>
  <div class="flex min-h-screen items-center justify-center bg-[radial-gradient(circle_at_top_right,rgba(126,146,120,0.18),transparent_28%),linear-gradient(180deg,#f9f2e8_0%,#f6efe5_50%,#f2e7da_100%)] px-4">
    <div class="w-full max-w-md">
      <div class="mb-8 text-center">
        <NuxtLink to="/" class="inline-block">
          <h1 class="font-serif text-3xl font-bold text-[#2b221a]">ShantiSangha</h1>
        </NuxtLink>
        <p class="mt-2 text-sm text-[#6c5c4d]">Start your wellness journey today.</p>
      </div>
      <div class="rounded-3xl border border-[rgba(101,76,52,0.14)] bg-[rgba(255,250,243,0.84)] p-6 shadow-[0_24px_80px_rgba(82,54,29,0.1)] backdrop-blur-[18px]">
        <SignUp />
      </div>
    </div>
  </div>
</template>
