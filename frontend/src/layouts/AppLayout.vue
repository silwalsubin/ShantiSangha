<script setup lang="ts">
import { useRoute } from 'vue-router'
import { UserButton } from '@clerk/vue'
import SacredIcons from '@/components/icons/SacredIcons.vue'

const route = useRoute()

const rawBuildTime = import.meta.env.VITE_BUILD_TIME || ''
const buildTime = rawBuildTime
  ? new Date(rawBuildTime).toLocaleString('en-US', { month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit' })
  : 'dev'

const navItems = [
  { icon: 'om', label: 'Dashboard', href: '/app/dashboard' },
  { icon: 'dialogue', label: 'Chat', href: '/app/chat' },
  { icon: 'scroll', label: 'Journal', href: '/app/journal' },
  { icon: 'chakra', label: 'Mood', href: '/app/mood' },
  { icon: 'lotus', label: 'Coping', href: '/app/coping' },
  { icon: 'diya', label: 'Insights', href: '/app/insights' },
  { icon: 'shankha', label: 'Voice', href: '/app/voice' },
]

function isActive(href: string) {
  return route.path === href || route.path.startsWith(href + '/')
}
</script>

<template>
  <div class="min-h-screen bg-[linear-gradient(180deg,#faf5ed_0%,#f5ebe0_48%,#efe3d4_100%)] text-[#2b1e10]">
    <!-- Desktop Sidebar -->
    <aside class="fixed inset-y-0 left-0 z-30 hidden w-64 flex-col border-r border-[rgba(139,90,43,0.15)] bg-[rgba(250,245,237,0.95)] backdrop-blur-[20px] lg:flex">
      <!-- Logo -->
      <div class="flex h-20 items-center border-b border-[rgba(139,90,43,0.12)] px-6">
        <RouterLink to="/app/dashboard" class="flex items-center gap-3">
          <div class="flex h-9 w-9 items-center justify-center rounded-full bg-gradient-to-br from-[#c4873b] to-[#8b5a1b] text-white">
            <SacredIcons name="om" :size="18" />
          </div>
          <div>
            <span class="font-serif text-lg font-bold tracking-wide text-[#2b1e10]">ShantiSangha</span>
            <p class="text-[9px] uppercase tracking-[0.2em] text-[#9a7d5a]">Wellness Companion</p>
          </div>
        </RouterLink>
      </div>

      <!-- Decorative border -->
      <div class="mx-5 border-b border-dashed border-[rgba(139,90,43,0.15)]" />

      <!-- Nav -->
      <nav class="flex-1 overflow-y-auto px-4 py-5">
        <p class="mb-3 px-3 text-[9px] font-semibold uppercase tracking-[0.2em] text-[#a38d6d]">Practice</p>
        <ul class="space-y-0.5">
          <li v-for="item in navItems" :key="item.href">
            <RouterLink
              :to="item.href"
              class="group flex items-center gap-3 rounded-xl px-3 py-2.5 text-sm font-medium transition-all duration-200"
              :class="isActive(item.href)
                ? 'bg-gradient-to-r from-[rgba(196,135,59,0.15)] to-[rgba(196,135,59,0.05)] text-[#8b5a1b] shadow-[inset_2px_0_0_#c4873b]'
                : 'text-[#6b5740] hover:bg-[rgba(196,135,59,0.06)] hover:text-[#2b1e10]'"
            >
              <SacredIcons
                :name="item.icon"
                :size="20"
                class="shrink-0 transition-transform duration-200 group-hover:scale-110"
              />
              <span>{{ item.label }}</span>
            </RouterLink>
          </li>
        </ul>
      </nav>

      <!-- Sanskrit verse decoration -->
      <div class="mx-5 border-t border-dashed border-[rgba(139,90,43,0.12)] px-1 py-3">
        <p class="text-center text-[10px] italic leading-relaxed text-[#b5996f]">
          "Yoga is the journey of the self,<br>through the self, to the self."
        </p>
      </div>

      <!-- User -->
      <div class="border-t border-[rgba(139,90,43,0.12)] px-5 py-4">
        <UserButton />
      </div>

      <!-- Build info -->
      <div class="border-t border-[rgba(139,90,43,0.08)] px-5 py-2 text-[9px] tracking-wide text-[#b5996f]">
        &copy; ShantiSangha &middot; {{ buildTime }}
      </div>
    </aside>

    <!-- Main content -->
    <div class="lg:pl-64">
      <!-- Mobile top bar -->
      <div class="sticky top-0 z-20 flex h-14 items-center justify-between border-b border-[rgba(139,90,43,0.12)] bg-[rgba(250,245,237,0.95)] px-4 backdrop-blur-[20px] lg:hidden">
        <div class="flex items-center gap-2">
          <div class="flex h-7 w-7 items-center justify-center rounded-full bg-gradient-to-br from-[#c4873b] to-[#8b5a1b] text-white">
            <SacredIcons name="om" :size="14" />
          </div>
          <span class="font-serif text-lg font-bold text-[#2b1e10]">ShantiSangha</span>
        </div>
        <UserButton />
      </div>

      <main class="min-h-screen px-4 py-6 sm:px-6 lg:px-10 lg:py-8">
        <RouterView />
      </main>

      <!-- Mobile bottom tab bar -->
      <nav class="fixed inset-x-0 bottom-0 z-30 flex border-t border-[rgba(139,90,43,0.15)] bg-[rgba(250,245,237,0.97)] backdrop-blur-[20px] lg:hidden">
        <RouterLink
          v-for="item in navItems"
          :key="item.href"
          :to="item.href"
          class="flex flex-1 flex-col items-center gap-1 py-2.5 text-[9px] font-medium tracking-wide transition-colors"
          :class="isActive(item.href)
            ? 'text-[#8b5a1b]'
            : 'text-[#9a8568]'"
        >
          <SacredIcons :name="item.icon" :size="20" />
          <span>{{ item.label }}</span>
        </RouterLink>
      </nav>

      <!-- Mobile bottom spacer -->
      <div class="h-20 lg:hidden" />
    </div>
  </div>
</template>
