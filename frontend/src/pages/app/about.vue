<script setup lang="ts">
/**
 * About page — displays client and server version info.
 */

import { ref, onMounted } from 'vue'
import { useApi } from '@/composables/useApi'
import SacredIcons from '@/components/icons/SacredIcons.vue'

const api = useApi()

const clientGitHash = (import.meta.env.VITE_GIT_HASH || 'dev') as string
const clientBuildTime = import.meta.env.VITE_BUILD_TIME || 'unknown'
const clientBuildFormatted = clientBuildTime !== 'unknown'
  ? new Date(clientBuildTime).toLocaleString('en-US', { month: 'short', day: 'numeric', year: 'numeric', hour: 'numeric', minute: '2-digit' })
  : 'dev'

const server = ref<{ gitHash: string; gitHashFull: string; buildTime: string } | null>(null)
const serverLoading = ref(true)

const serverBuildFormatted = ref('loading...')

async function loadServerVersion() {
  try {
    server.value = await api.get<any>('/version')
    if (server.value?.buildTime && server.value.buildTime !== 'unknown') {
      serverBuildFormatted.value = new Date(server.value.buildTime).toLocaleString('en-US', {
        month: 'short', day: 'numeric', year: 'numeric', hour: 'numeric', minute: '2-digit'
      })
    } else {
      serverBuildFormatted.value = 'dev'
    }
  } catch {
    serverBuildFormatted.value = 'unavailable'
  } finally {
    serverLoading.value = false
  }
}

onMounted(() => loadServerVersion())
</script>

<template>
  <div class="mx-auto max-w-lg px-4 py-6 sm:py-10">
    <div class="flex items-center gap-3 mb-6">
      <div class="flex h-10 w-10 items-center justify-center rounded-full bg-gradient-to-br from-sacred-gold to-sacred-gold-dark text-white">
        <SacredIcons name="vajra" :size="28" />
      </div>
      <div>
        <h1 class="font-serif text-xl font-bold text-sacred-text">ShantiSangha</h1>
        <p class="text-xs text-sacred-muted">Version info</p>
      </div>
    </div>

    <!-- Client -->
    <div class="rounded-sacred-lg border border-sacred-border bg-sacred-bg-card-inner p-4 mb-4">
      <p class="text-sacred-xs text-sacred-label mb-3">Client</p>
      <div class="space-y-2">
        <div class="flex justify-between">
          <span class="text-sm text-sacred-text-secondary">Git hash</span>
          <code class="text-sm font-mono text-sacred-text">{{ clientGitHash.slice(0, 7) }}</code>
        </div>
        <div class="flex justify-between">
          <span class="text-sm text-sacred-text-secondary">Built</span>
          <span class="text-sm text-sacred-text">{{ clientBuildFormatted }}</span>
        </div>
      </div>
    </div>

    <!-- Server -->
    <div class="rounded-sacred-lg border border-sacred-border bg-sacred-bg-card-inner p-4">
      <p class="text-sacred-xs text-sacred-label mb-3">App Server</p>
      <div v-if="serverLoading" class="space-y-2">
        <div class="h-5 w-3/4 animate-pulse rounded bg-sacred-bg-pulse" />
        <div class="h-5 w-2/3 animate-pulse rounded bg-sacred-bg-pulse" />
      </div>
      <div v-else class="space-y-2">
        <div class="flex justify-between">
          <span class="text-sm text-sacred-text-secondary">Git hash</span>
          <code class="text-sm font-mono text-sacred-text">{{ server?.gitHash || 'dev' }}</code>
        </div>
        <div class="flex justify-between">
          <span class="text-sm text-sacred-text-secondary">Built</span>
          <span class="text-sm text-sacred-text">{{ serverBuildFormatted }}</span>
        </div>
      </div>
    </div>
  </div>
</template>
