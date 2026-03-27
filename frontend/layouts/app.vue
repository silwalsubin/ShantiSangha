<script setup lang="ts">
const route = useRoute()

const navItems = [
  { icon: '🏠', label: 'Dashboard', href: '/app/dashboard' },
  { icon: '💬', label: 'Chat', href: '/app/chat' },
  { icon: '📔', label: 'Journal', href: '/app/journal' },
  { icon: '📊', label: 'Mood', href: '/app/mood' },
  { icon: '🌿', label: 'Coping', href: '/app/coping' },
  { icon: '✨', label: 'Insights', href: '/app/insights' },
  { icon: '🎙️', label: 'Voice', href: '/app/voice' },
]

function isActive(href: string) {
  return route.path === href || route.path.startsWith(href + '/')
}
</script>

<template>
  <div class="min-h-screen bg-[linear-gradient(180deg,#f9f2e8_0%,#f6efe5_48%,#f2e7da_100%)] text-[#2b221a]">
    <!-- Desktop Sidebar -->
    <aside class="fixed inset-y-0 left-0 z-30 hidden w-60 flex-col border-r border-[rgba(101,76,52,0.12)] bg-[rgba(255,250,243,0.88)] backdrop-blur-[18px] lg:flex">
      <!-- Logo -->
      <div class="flex h-16 items-center border-b border-[rgba(101,76,52,0.1)] px-6">
        <NuxtLink to="/app/dashboard" class="flex items-center gap-2">
          <span class="font-serif text-xl font-bold text-[#2b221a]">ShantiSangha</span>
        </NuxtLink>
      </div>

      <!-- Nav -->
      <nav class="flex-1 overflow-y-auto px-3 py-4">
        <ul class="space-y-1">
          <li v-for="item in navItems" :key="item.href">
            <NuxtLink
              :to="item.href"
              class="flex items-center gap-3 rounded-xl px-3 py-2.5 text-sm font-medium transition-all"
              :class="isActive(item.href)
                ? 'bg-[rgba(138,91,63,0.12)] text-[#8a5b3f]'
                : 'text-[#6c5c4d] hover:bg-[rgba(138,91,63,0.06)] hover:text-[#2b221a]'"
            >
              <span class="text-base">{{ item.icon }}</span>
              <span>{{ item.label }}</span>
            </NuxtLink>
          </li>
        </ul>
      </nav>

      <!-- User -->
      <div class="border-t border-[rgba(101,76,52,0.1)] px-4 py-4">
        <UserButton />
      </div>
    </aside>

    <!-- Main content -->
    <div class="lg:pl-60">
      <!-- Mobile top bar -->
      <div class="sticky top-0 z-20 flex h-14 items-center justify-between border-b border-[rgba(101,76,52,0.1)] bg-[rgba(255,250,243,0.92)] px-4 backdrop-blur-[18px] lg:hidden">
        <span class="font-serif text-lg font-bold text-[#2b221a]">ShantiSangha</span>
        <UserButton />
      </div>

      <main class="min-h-screen px-4 py-6 sm:px-6 lg:px-8">
        <slot />
      </main>

      <!-- Mobile bottom tab bar -->
      <nav class="fixed inset-x-0 bottom-0 z-30 flex border-t border-[rgba(101,76,52,0.12)] bg-[rgba(255,250,243,0.95)] backdrop-blur-[18px] lg:hidden">
        <NuxtLink
          v-for="item in navItems"
          :key="item.href"
          :to="item.href"
          class="flex flex-1 flex-col items-center gap-0.5 py-2 text-[10px] font-medium transition-colors"
          :class="isActive(item.href) ? 'text-[#8a5b3f]' : 'text-[#6c5c4d]'"
        >
          <span class="text-base leading-none">{{ item.icon }}</span>
          <span>{{ item.label }}</span>
        </NuxtLink>
      </nav>

      <!-- Mobile bottom spacer -->
      <div class="h-16 lg:hidden" />
    </div>
  </div>
</template>
