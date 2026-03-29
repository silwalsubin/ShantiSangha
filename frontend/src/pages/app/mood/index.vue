<script setup lang="ts">
import { onMounted } from 'vue'
import { useRouter } from 'vue-router'

const router = useRouter()

// Mood feature has been replaced by Goals. Redirect to Journey.
onMounted(() => {
  router.replace('/app/journey')
})
</script>

<template>
  <div class="mx-auto max-w-2xl p-4 sm:p-6 text-center">
    <p class="text-sm text-[#6b5740]">Redirecting to your journey...</p>
  </div>
</template>
